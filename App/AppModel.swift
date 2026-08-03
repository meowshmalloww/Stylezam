import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let settings: SettingsStore
    let library: LibraryStore
    let liveScreen: LiveScreenCaptureManager

    var selectedTab: AppTab = .home
    var isCapturePresented = false
    var activeSearch: SearchJobDTO?
    var activeSearchImageData: Data?
    var activeSearchOrigin: CaptureOrigin = .text
    var searchResults: [ProductResultDTO] = []
    var capabilities: CapabilitiesDTO?
    var serverMessage: String?
    var lastError: String?

    @ObservationIgnored private let activityManager = SearchActivityManager()
    @ObservationIgnored private let notifications = NotificationService()
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var lastCaptureRequest: Double = 0

    init(
        settings: SettingsStore = SettingsStore(),
        library: LibraryStore = LibraryStore(),
        liveScreen: LiveScreenCaptureManager = LiveScreenCaptureManager()
    ) {
        self.settings = settings
        self.library = library
        self.liveScreen = liveScreen
    }

    func start() async {
        await refreshCapabilities()
        handleExternalCaptureRequest()
        handlePendingNotification()
        if let pending = library.consumePendingShare() {
            await startSearch(pending)
        }
    }

    func refreshCapabilities() async {
        do {
            let client = try settings.client()
            async let health = client.health()
            async let capabilityRequest = client.capabilities()
            let (healthResponse, capabilityResponse) = try await (health, capabilityRequest)
            capabilities = capabilityResponse
            serverMessage = "Connected · API \(healthResponse.version)"
        } catch {
            capabilities = nil
            serverMessage = error.localizedDescription
        }
    }

    @discardableResult
    func startSearch(_ input: SearchInput, saveCapture: Bool = true) async -> String? {
        guard !input.isEmpty else { return nil }
        if let previous = activeSearch, !previous.status.isTerminal {
            searchTask?.cancel()
            if let client = try? settings.client() {
                try? await client.deleteSearch(id: previous.id)
            }
        }
        searchTask?.cancel()
        await activityManager.end()
        activeSearch = nil
        activeSearchImageData = input.imageData
        activeSearchOrigin = input.origin
        searchResults = []
        lastError = nil
        selectedTab = .search
        isCapturePresented = false
        do {
            let client = try settings.client()
            let submitted = try await client.createSearch(
                query: input.query,
                imageData: input.imageData,
                selectedRegion: input.selectedRegion
            )
            activeSearch = submitted
            if saveCapture {
                _ = try? library.addCapture(input: input, searchID: submitted.id)
            }
            await activityManager.start(for: submitted)
            searchTask = Task { [weak self] in
                await self?.pollSearch(id: submitted.id)
            }
            return submitted.id
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func resetSearch() {
        searchTask?.cancel()
        searchTask = nil
        activeSearch = nil
        activeSearchImageData = nil
        activeSearchOrigin = .text
        searchResults = []
        lastError = nil
        Task { await activityManager.end() }
    }

    func cancelActiveSearchAndReset() async {
        let runningID = activeSearch.flatMap { $0.status.isTerminal ? nil : $0.id }
        searchTask?.cancel()
        searchTask = nil
        await activityManager.end()
        activeSearch = nil
        activeSearchImageData = nil
        activeSearchOrigin = .text
        searchResults = []
        lastError = nil
        guard let runningID, let client = try? settings.client() else { return }
        try? await client.deleteSearch(id: runningID)
    }

    func focusOnDetectedItem(_ item: DetectedItemDTO) async {
        guard let job = activeSearch else { return }
        var sourceData = activeSearchImageData
        if sourceData == nil, let inputImageURL = job.inputImageURL {
            do {
                let (downloaded, response) = try await URLSession.shared.data(from: inputImageURL)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode)
                else {
                    throw APIClientError.invalidResponse
                }
                sourceData = downloaded
            } catch {
                lastError = "The original capture could not be loaded for item selection."
                return
            }
        }
        guard let sourceData else {
            lastError = "The original capture is no longer available. Capture the look again to select an item."
            return
        }
        await startSearch(
            SearchInput(
                query: job.query,
                imageData: sourceData,
                origin: activeSearchOrigin,
                selectedRegion: item.box
            ),
            saveCapture: false
        )
    }

    func retryActiveSearch() async {
        guard let job = activeSearch else { return }
        var sourceData = activeSearchImageData
        if sourceData == nil, let inputImageURL = job.inputImageURL {
            do {
                let (downloaded, response) = try await URLSession.shared.data(from: inputImageURL)
                guard let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode)
                else {
                    throw APIClientError.invalidResponse
                }
                sourceData = downloaded
            } catch {
                lastError = "The original capture could not be loaded for a new attempt."
                return
            }
        }
        let retryInput = SearchInput(
            query: job.query,
            imageData: sourceData,
            origin: activeSearchOrigin,
            selectedRegion: job.selectedRegion
        )
        guard !retryInput.isEmpty else {
            lastError = "The original search input is no longer available."
            return
        }
        let previousID = job.id
        if let replacementID = await startSearch(retryInput, saveCapture: false) {
            if library.replaceSearchID(previousID, with: replacementID) {
                Task {
                    guard let client = try? settings.client() else { return }
                    try? await client.deleteSearch(id: previousID)
                }
            }
        }
    }

    func deleteCapture(_ capture: SavedCapture) {
        library.deleteCapture(capture)
        Task {
            guard let client = try? settings.client() else { return }
            try? await client.deleteSearch(id: capture.searchID)
        }
    }

    func clearLibrary() {
        let searchIDs = library.captures.map(\.searchID)
        do {
            try library.clear()
        } catch {
            lastError = error.localizedDescription
            return
        }
        Task {
            guard let client = try? settings.client() else { return }
            await withTaskGroup(of: Void.self) { group in
                for id in searchIDs {
                    group.addTask { try? await client.deleteSearch(id: id) }
                }
            }
        }
    }

    func resumeSearch(id: String, imageData: Data? = nil) {
        searchTask?.cancel()
        activeSearchImageData = imageData
        activeSearchOrigin = imageData == nil ? .text : .photoLibrary
        selectedTab = .search
        searchTask = Task { [weak self] in
            await self?.pollSearch(id: id)
        }
    }

    func handleURL(_ url: URL) {
        guard url.scheme == "stylezam" else { return }
        switch url.host {
        case "capture":
            isCapturePresented = true
        case "import":
            if let pending = library.consumePendingShare() {
                Task { await startSearch(pending) }
            } else {
                isCapturePresented = true
            }
        case "search":
            let identifier = url.pathComponents.dropFirst().first
            if let identifier { resumeSearch(id: identifier) }
        default:
            break
        }
    }

    func handleExternalCaptureRequest() {
        let requestedAt = StylezamShared.defaults.double(
            forKey: StylezamShared.captureRequestKey
        )
        if requestedAt > lastCaptureRequest {
            lastCaptureRequest = requestedAt
            if let liveFrame = liveScreen.consumeLatestFrame() {
                Task {
                    await startSearch(
                        SearchInput(
                            query: nil,
                            imageData: liveFrame,
                            origin: .screenCapture
                        )
                    )
                }
            } else {
                isCapturePresented = true
            }
        }
        if let pending = library.consumePendingShare() {
            Task { await startSearch(pending) }
        }
    }

    func handlePendingNotification(searchID suppliedID: String? = nil) {
        let defaults = StylezamShared.defaults
        let searchID = suppliedID ?? defaults.string(forKey: StylezamShared.pendingSearchIDKey)
        guard let searchID, !searchID.isEmpty else { return }
        defaults.removeObject(forKey: StylezamShared.pendingSearchIDKey)
        resumeSearch(id: searchID)
    }

    private func pollSearch(id: String) async {
        do {
            let client = try settings.client()
            while !Task.isCancelled {
                let job = try await client.search(id: id)
                activeSearch = job
                await activityManager.update(with: job)
                if job.status == .completed {
                    let page = try await client.results(searchID: id)
                    searchResults = page.results
                    if settings.notificationsEnabled {
                        let allowed = await notifications.requestAuthorization()
                        if allowed {
                            await notifications.searchFinished(
                                resultCount: page.total,
                                searchID: id
                            )
                        }
                    }
                    return
                }
                if job.status == .failed || job.status == .cancelled {
                    lastError = job.errorMessage ?? "The search could not finish."
                    return
                }
                try await Task.sleep(for: .seconds(1.4))
            }
        } catch is CancellationError {
            return
        } catch {
            lastError = error.localizedDescription
        }
    }
}
