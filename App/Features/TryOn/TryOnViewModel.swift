import Foundation
import Observation

@MainActor
@Observable
final class TryOnViewModel {
    private let settings: SettingsStore
    private let productImageURL: URL

    var personImageData: Data?
    var job: TryOnJobDTO?
    var errorMessage: String?
    var completionMessage: String?
    var isShowingResult = true
    var resultImageData: Data?
    var resultFileURL: URL?

    @ObservationIgnored private var pollingTask: Task<Void, Never>?
    @ObservationIgnored private var remoteJobWasDeleted = false

    init(settings: SettingsStore, productImageURL: URL) {
        self.settings = settings
        self.productImageURL = productImageURL
    }

    var isProcessing: Bool {
        guard let job else { return false }
        return !job.status.isTerminal
    }

    func submit(category: String = "auto") async {
        guard let personImageData else { return }
        await deleteRemoteJobIfNeeded()
        pollingTask?.cancel()
        errorMessage = nil
        completionMessage = nil
        remoteJobWasDeleted = false
        removeCachedResult()
        do {
            let client = try settings.client()
            let submitted = try await client.createTryOn(
                productImageURL: productImageURL,
                garmentCategory: category,
                personImageData: personImageData
            )
            job = submitted
            pollingTask = Task { [weak self] in
                await self?.poll(id: submitted.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reset() {
        pollingTask?.cancel()
        pollingTask = nil
        job = nil
        errorMessage = nil
        completionMessage = nil
        isShowingResult = true
        remoteJobWasDeleted = false
        removeCachedResult()
    }

    func replacePersonImage(with data: Data) async {
        await deleteRemoteJobIfNeeded()
        reset()
        personImageData = data
    }

    func deleteRemoteJobIfNeeded() async {
        guard let job, !remoteJobWasDeleted else { return }
        pollingTask?.cancel()
        guard let client = try? settings.client() else { return }
        do {
            try await client.deleteTryOn(id: job.id)
            remoteJobWasDeleted = true
        } catch {
            errorMessage = "The preview is local, but Stylezam could not confirm server cleanup: \(error.localizedDescription)"
        }
    }

    private func poll(id: String) async {
        do {
            let client = try settings.client()
            while !Task.isCancelled {
                let update = try await client.tryOn(id: id)
                job = update
                if update.status == .failed {
                    errorMessage = update.errorMessage ?? "The try-on could not finish."
                    return
                }
                if update.status == .completed {
                    await cacheCompletedResult(update)
                    return
                }
                try await Task.sleep(for: .seconds(2.5))
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cacheCompletedResult(_ completedJob: TryOnJobDTO) async {
        guard let resultURL = completedJob.resultImageURL else {
            errorMessage = "YouCam completed the task without a result image."
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: resultURL)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  !data.isEmpty
            else {
                throw APIClientError.invalidResponse
            }
            let directory = FileManager.default.temporaryDirectory
                .appending(path: "StylezamPreviews", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let destination = directory.appending(path: "\(completedJob.id).jpg")
            try data.write(to: destination, options: .atomic)
            resultImageData = data
            resultFileURL = destination
            completionMessage = "Preview saved locally. Removing server copies…"
            await deleteRemoteJobIfNeeded()
            if remoteJobWasDeleted {
                completionMessage = "Preview is local; Stylezam’s server upload and generated copy were removed."
            }
        } catch {
            errorMessage = "The preview finished, but its image could not be saved locally: \(error.localizedDescription)"
        }
    }

    private func removeCachedResult() {
        if let resultFileURL {
            try? FileManager.default.removeItem(at: resultFileURL)
        }
        resultImageData = nil
        resultFileURL = nil
    }
}
