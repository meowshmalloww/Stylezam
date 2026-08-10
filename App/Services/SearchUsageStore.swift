import Foundation
import Observation

@MainActor
@Observable
final class SearchUsageStore {
    private static let googleVisionProviderID = "googlevision"

    private(set) var snapshot = SearchUsageSnapshot()
    private(set) var loadError: String?

    private let fileURL: URL
    private let googleVisionCounterURL: URL
    private var googleVisionCounter = GoogleVisionMonthlyCounter(
        month: SearchUsageStore.monthIdentifier(),
        reservedUnits: 0
    )

    init(rootURL: URL? = nil) {
        let root = rootURL ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(path: "Stylezam", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fileURL = root.appending(path: "search-usage.json")
        googleVisionCounterURL = root.appending(path: "google-vision-usage.json")
        load()
        loadGoogleVisionCounter()
    }

    var currentMonthRecords: [SearchUsageRecord] {
        let calendar = Calendar(identifier: .gregorian)
        return snapshot.records.filter { calendar.isDate($0.createdAt, equalTo: .now, toGranularity: .month) }
    }

    func requestCount(provider: String) -> Int {
        let diagnosticCount = currentMonthRecords
            .reduce(0) { count, record in
                count + record.providers.filter { $0 == provider }.count
            }
        guard provider == Self.googleVisionProviderID else { return diagnosticCount }
        normalizeGoogleVisionCounterMonth()
        return max(diagnosticCount, googleVisionCounter.reservedUnits)
    }

    var estimatedFireworksSpend: Double {
        currentMonthRecords
            .filter { $0.providers.contains("fireworks") }
            .reduce(0) { $0 + $1.estimatedCostUSD }
    }

    func logicalCount(kind: SearchUsageKind) -> Int {
        currentMonthRecords.filter {
            $0.kind == kind && $0.status != .failed
        }.count
    }

    func requestCount(kind: SearchUsageKind) -> Int {
        currentMonthRecords
            .filter { $0.kind == kind }
            .reduce(0) { $0 + $1.requestCount }
    }

    func attempts(for garmentKey: String) -> Int {
        snapshot.records.filter {
            $0.kind == .productSearch
                && $0.garmentKey == garmentKey
                && $0.status != .failed
        }.count
    }

    func failedAttempts(for garmentKey: String) -> Int {
        snapshot.records.filter {
            $0.kind == .productSearch
                && $0.garmentKey == garmentKey
                && $0.status == .failed
        }.count
    }

    /// Chooses one eligible visual provider for one garment request. The caller
    /// controls the maximum streak; production search uses one request so the
    /// route advances after every attempt.
    func routedImageProvider(
        from eligibleProviders: [ImageSearchProvider],
        maximumConsecutiveRequests: Int = 2
    ) -> ImageSearchProvider? {
        var eligible: [ImageSearchProvider] = []
        for provider in eligibleProviders where !eligible.contains(provider) {
            eligible.append(provider)
        }
        guard let first = eligible.first else { return nil }

        let recent = currentMonthRecords
            .filter { $0.kind == .productSearch && $0.providers.count == 1 }
            .sorted { $0.createdAt < $1.createdAt }
        guard let lastRecord = recent.last,
              let lastRaw = lastRecord.providers.first,
              let lastProvider = ImageSearchProvider(rawValue: lastRaw),
              let lastIndex = eligible.firstIndex(of: lastProvider)
        else { return first }

        let next = eligible[(lastIndex + 1) % eligible.count]
        guard lastRecord.status != .failed else { return next }

        let streak = recent.reversed().prefix { record in
            record.providers.first == lastRaw && record.status != .failed
        }.count
        return streak >= max(1, maximumConsecutiveRequests) ? next : lastProvider
    }

    /// Chooses exactly one keyword-shopping provider. Private AI search records
    /// contain Fireworks plus one shopping provider, so that second provider is
    /// the round-robin cursor. Failed attempts advance on the following search.
    func routedKeywordProvider(
        from eligibleProviders: [KeywordSearchProvider]
    ) -> KeywordSearchProvider? {
        var eligible: [KeywordSearchProvider] = []
        for provider in eligibleProviders where !eligible.contains(provider) {
            eligible.append(provider)
        }
        guard let first = eligible.first else { return nil }

        let recent = currentMonthRecords
            .filter { $0.kind == .productSearch && $0.providers.contains("fireworks") }
            .sorted { $0.createdAt < $1.createdAt }
        guard let lastRaw = recent.last?.providers.first(where: { $0 != "fireworks" }),
              let lastProvider = KeywordSearchProvider(rawValue: lastRaw),
              let lastIndex = eligible.firstIndex(of: lastProvider)
        else { return first }

        return eligible[(lastIndex + 1) % eligible.count]
    }

    @discardableResult
    func reserveProductSearch(
        garmentKey: String,
        providers: [String],
        perGarmentLimit: Int,
        providerMonthlyLimits: [String: Int],
        fireworksBudgetUSD: Double
    ) throws -> UUID {
        guard attempts(for: garmentKey) < perGarmentLimit else {
            throw ProductSearchError.garmentSearchLimitReached(perGarmentLimit)
        }
        for provider in providers {
            if let limit = providerMonthlyLimits[provider], requestCount(provider: provider) >= limit {
                throw ProductSearchError.monthlyRequestLimitReached(provider, limit)
            }
        }
        if providers.contains("fireworks"), estimatedFireworksSpend >= fireworksBudgetUSD {
            throw ProductSearchError.fireworksBudgetReached(fireworksBudgetUSD)
        }
        try reserveGoogleVisionUnits(in: providers)
        let id = UUID()
        snapshot.records.append(
            SearchUsageRecord(
                id: id,
                garmentKey: garmentKey,
                kind: .productSearch,
                providers: providers,
                createdAt: .now,
                status: .reserved,
                requestCount: providers.count,
                resultCount: 0,
                latencyMilliseconds: nil,
                estimatedCostUSD: 0,
                diagnostic: nil
            )
        )
        trimAndPersist()
        return id
    }

    @discardableResult
    func reserveAuxiliary(
        kind: SearchUsageKind,
        garmentKey: String?,
        provider: String,
        monthlyLimit: Int,
        fireworksBudgetUSD: Double
    ) throws -> UUID {
        if requestCount(provider: provider) >= monthlyLimit {
            throw ProductSearchError.monthlyRequestLimitReached(provider, monthlyLimit)
        }
        if provider == "fireworks", estimatedFireworksSpend >= fireworksBudgetUSD {
            throw ProductSearchError.fireworksBudgetReached(fireworksBudgetUSD)
        }
        try reserveGoogleVisionUnits(in: [provider])
        let id = UUID()
        snapshot.records.append(
            SearchUsageRecord(
                id: id,
                garmentKey: garmentKey,
                kind: kind,
                providers: [provider],
                createdAt: .now,
                status: .reserved,
                requestCount: 1,
                resultCount: 0,
                latencyMilliseconds: nil,
                estimatedCostUSD: 0,
                diagnostic: nil
            )
        )
        trimAndPersist()
        return id
    }

    func complete(
        _ id: UUID,
        resultCount: Int,
        latencyMilliseconds: Double,
        estimatedCostUSD: Double,
        diagnostic: String
    ) {
        update(
            id,
            status: .succeeded,
            resultCount: resultCount,
            latencyMilliseconds: latencyMilliseconds,
            estimatedCostUSD: estimatedCostUSD,
            diagnostic: diagnostic
        )
    }

    func fail(_ id: UUID, latencyMilliseconds: Double, diagnostic: String) {
        update(
            id,
            status: .failed,
            resultCount: 0,
            latencyMilliseconds: latencyMilliseconds,
            estimatedCostUSD: 0,
            diagnostic: diagnostic
        )
    }

    func resetUsage() {
        snapshot = SearchUsageSnapshot()
        try? persist()
    }

    private func reserveGoogleVisionUnits(in providers: [String]) throws {
        let requestedUnits = providers.filter { $0 == Self.googleVisionProviderID }.count
        guard requestedUnits > 0 else { return }
        normalizeGoogleVisionCounterMonth()
        let hardLimit = SettingsStore.googleVisionHardMonthlyLimit
        guard googleVisionCounter.reservedUnits + requestedUnits <= hardLimit else {
            throw ProductSearchError.monthlyRequestLimitReached(Self.googleVisionProviderID, hardLimit)
        }

        let previous = googleVisionCounter
        googleVisionCounter.reservedUnits += requestedUnits
        do {
            try persistGoogleVisionCounter()
        } catch {
            googleVisionCounter = previous
            throw ProductSearchError.provider(
                "Stylezam could not safely reserve the Google Vision unit locally, so no network request was sent."
            )
        }
    }

    private func normalizeGoogleVisionCounterMonth() {
        let month = Self.monthIdentifier()
        guard googleVisionCounter.month != month else { return }
        googleVisionCounter = GoogleVisionMonthlyCounter(month: month, reservedUnits: 0)
        try? persistGoogleVisionCounter()
    }

    private func loadGoogleVisionCounter() {
        let month = Self.monthIdentifier()
        if let data = try? Data(contentsOf: googleVisionCounterURL),
           let saved = try? JSONDecoder().decode(GoogleVisionMonthlyCounter.self, from: data),
           saved.month == month
        {
            googleVisionCounter = saved
        } else {
            googleVisionCounter = GoogleVisionMonthlyCounter(month: month, reservedUnits: 0)
        }

        // Migrate any current-month calls recorded before the durable hard-stop
        // counter existed. The separate counter is never cleared by diagnostics.
        let recordedUnits = currentMonthRecords.reduce(0) { count, record in
            count + record.providers.filter { $0 == Self.googleVisionProviderID }.count
        }
        googleVisionCounter.reservedUnits = max(googleVisionCounter.reservedUnits, recordedUnits)
        try? persistGoogleVisionCounter()
    }

    private func persistGoogleVisionCounter() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(googleVisionCounter).write(to: googleVisionCounterURL, options: .atomic)
    }

    private static func monthIdentifier(for date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: date)
    }

    private func update(
        _ id: UUID,
        status: SearchUsageStatus,
        resultCount: Int,
        latencyMilliseconds: Double,
        estimatedCostUSD: Double,
        diagnostic: String
    ) {
        guard let index = snapshot.records.firstIndex(where: { $0.id == id }) else { return }
        snapshot.records[index].status = status
        snapshot.records[index].resultCount = resultCount
        snapshot.records[index].latencyMilliseconds = latencyMilliseconds
        snapshot.records[index].estimatedCostUSD = estimatedCostUSD
        snapshot.records[index].diagnostic = diagnostic
        trimAndPersist()
    }

    private func trimAndPersist() {
        snapshot.records = Array(snapshot.records.suffix(1_000))
        do { try persist() } catch { loadError = error.localizedDescription }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            snapshot = try decoder.decode(
                SearchUsageSnapshot.self,
                from: Data(contentsOf: fileURL)
            )
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }
}

private struct GoogleVisionMonthlyCounter: Codable, Equatable {
    var month: String
    var reservedUnits: Int
}
