import Foundation
import Observation

@MainActor
@Observable
final class SearchUsageStore {
    private(set) var snapshot = SearchUsageSnapshot()
    private(set) var loadError: String?

    private let fileURL: URL

    init() {
        let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appending(path: "Stylezam", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fileURL = root.appending(path: "search-usage.json")
        load()
    }

    var currentMonthRecords: [SearchUsageRecord] {
        let calendar = Calendar(identifier: .gregorian)
        return snapshot.records.filter { calendar.isDate($0.createdAt, equalTo: .now, toGranularity: .month) }
    }

    func requestCount(provider: String) -> Int {
        currentMonthRecords
            .reduce(0) { count, record in
                count + record.providers.filter { $0 == provider }.count
            }
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
