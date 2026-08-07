@preconcurrency import FirebaseAuth
import CryptoKit
import Foundation
import ImageIO
import Observation
import Supabase
import UniformTypeIdentifiers

enum CloudLibraryState: Equatable, Sendable {
    case unavailable
    case off
    case ready
    case syncing
    case failed(String)

    var title: String {
        switch self {
        case .unavailable: "Setup required"
        case .off: "Off"
        case .ready: "Up to date"
        case .syncing: "Syncing"
        case .failed: "Needs attention"
        }
    }
}

struct CloudRelevantGarment: Decodable, Identifiable, Sendable {
    let recordID: String
    let scanID: UUID
    let garmentID: String
    let title: String
    let category: String?
    let cropPath: String?
    let similarity: Double

    var id: String { recordID }

    enum CodingKeys: String, CodingKey {
        case recordID = "record_id"
        case scanID = "scan_id"
        case garmentID = "garment_id"
        case title, category
        case cropPath = "crop_path"
        case similarity
    }
}

struct SupabaseCloudConfiguration: Sendable {
    let url: URL
    let publishableKey: String

    static var bundled: SupabaseCloudConfiguration? {
        guard let rawURL = Bundle.main.object(forInfoDictionaryKey: "STYLEZAM_SUPABASE_URL") as? String,
              let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https",
              url.host?.hasSuffix(".supabase.co") == true,
              let key = Bundle.main.object(
                forInfoDictionaryKey: "STYLEZAM_SUPABASE_PUBLISHABLE_KEY"
              ) as? String,
              !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !key.contains("SET_ME")
        else { return nil }
        return SupabaseCloudConfiguration(url: url, publishableKey: key)
    }
}

@MainActor
@Observable
final class SupabaseCloudLibrary {
    private(set) var state: CloudLibraryState = .unavailable
    private(set) var lastSyncedAt: Date?
    private(set) var usageBytes: Int64 = 0
    private(set) var lastUploadedCropCount = 0

    @ObservationIgnored private var gateway: SupabaseCloudGateway?
    @ObservationIgnored private var ownerID: String?
    @ObservationIgnored private var plan: AccountPlan = .free
    @ObservationIgnored private var pendingExport: CloudLibraryExport?
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    var isConfigured: Bool { gateway != nil }
    var isEnabled: Bool {
        guard let ownerID else { return false }
        return UserDefaults.standard.bool(forKey: enabledKey(ownerID))
    }

    var usageSummary: String {
        ByteCountFormatter.string(fromByteCount: usageBytes, countStyle: .file)
            + " of "
            + plan.cloudStorageAllowance
    }

    func configure(ownerID: String?, plan: AccountPlan, export: CloudLibraryExport) {
        syncTask?.cancel()
        pendingExport = export
        self.plan = plan
        guard let ownerID else {
            self.ownerID = nil
            gateway = nil
            state = .off
            return
        }
        self.ownerID = ownerID
        guard let configuration = SupabaseCloudConfiguration.bundled else {
            gateway = nil
            state = .unavailable
            return
        }
        gateway = SupabaseCloudGateway(configuration: configuration)
        state = isEnabled ? .ready : .off
        if isEnabled { scheduleSync(export, immediate: true) }
    }

    func updatePlan(_ plan: AccountPlan) {
        self.plan = plan
        if let pendingExport, isEnabled { scheduleSync(pendingExport) }
    }

    func setEnabled(_ enabled: Bool, export: CloudLibraryExport) {
        guard let ownerID else { return }
        UserDefaults.standard.set(enabled, forKey: enabledKey(ownerID))
        pendingExport = export
        if enabled, gateway != nil {
            state = .ready
            scheduleSync(export, immediate: true)
        } else {
            syncTask?.cancel()
            state = gateway == nil ? .unavailable : .off
        }
    }

    func scheduleSync(_ export: CloudLibraryExport, immediate: Bool = false) {
        pendingExport = export
        guard isEnabled, let gateway, let ownerID else { return }
        syncTask?.cancel()
        let plan = plan
        syncTask = Task { [weak self] in
            if !immediate { try? await Task.sleep(for: .seconds(1.2)) }
            guard !Task.isCancelled else { return }
            self?.state = .syncing
            do {
                let outcome = try await gateway.sync(
                    export: export,
                    ownerID: ownerID,
                    quotaBytes: plan.cloudStorageBytes
                )
                guard !Task.isCancelled else { return }
                self?.usageBytes = outcome.usageBytes
                self?.lastUploadedCropCount = outcome.uploadedCropCount
                self?.lastSyncedAt = .now
                self?.state = .ready
            } catch is CancellationError {
                return
            } catch {
                self?.state = .failed(error.localizedDescription)
            }
        }
    }

    func syncNow(export: CloudLibraryExport) {
        scheduleSync(export, immediate: true)
    }

    func relevantGarments(for text: String, limit: Int = 4) async -> [CloudRelevantGarment] {
        guard isEnabled, let gateway else { return [] }
        return (try? await gateway.match(
            embedding: StylezamMetadataEmbedding.postgresVector(for: text),
            limit: max(1, min(limit, 6))
        )) ?? []
    }

    func deleteCloudLibrary() async throws {
        guard let ownerID else { return }
        guard let gateway else {
            if isEnabled { throw CloudLibraryError.configurationRequiredForDeletion }
            return
        }
        try await gateway.deleteAll(ownerID: ownerID)
        usageBytes = 0
        lastUploadedCropCount = 0
        lastSyncedAt = nil
        state = isEnabled ? .ready : .off
    }

    private func enabledKey(_ ownerID: String) -> String {
        "stylezam.cloud-library.enabled.\(ownerID)"
    }
}

private struct CloudSyncOutcome: Sendable {
    let usageBytes: Int64
    let uploadedCropCount: Int
}

private actor SupabaseCloudGateway {
    private let client: SupabaseClient
    private let bucket = "stylezam-private-library"

    init(configuration: SupabaseCloudConfiguration) {
        client = SupabaseClient(
            supabaseURL: configuration.url,
            supabaseKey: configuration.publishableKey,
            options: SupabaseClientOptions(
                auth: .init(accessToken: {
                    guard let user = Auth.auth().currentUser else { return nil }
                    return try await user.getIDTokenResult(forcingRefresh: false).token
                })
            )
        )
    }

    func sync(
        export: CloudLibraryExport,
        ownerID: String,
        quotaBytes: Int64
    ) async throws -> CloudSyncOutcome {
        var usage = try await usageBytes()
        var uploaded = 0
        var desiredPaths = Set<String>()
        let previousRemotePaths = try await allRemoteCropPaths(ownerID: ownerID)
        var garmentRows: [CloudGarmentRow] = []

        for value in export.garments {
            try Task.checkCancellation()
            let cropPath: String?
            let digest: String?
            if let cropURL = value.cropURL {
                let prepared = try CloudImagePreparer.prepare(fileURL: cropURL)
                let path = "\(ownerID)/garments/\(safePath(value.recordID))-\(prepared.digest).jpg"
                if !previousRemotePaths.contains(path) {
                    guard usage + Int64(prepared.data.count) <= quotaBytes else {
                        throw CloudLibraryError.quotaExceeded
                    }
                    try await client.storage.from(bucket).upload(
                        path,
                        data: prepared.data,
                        options: FileOptions(
                            cacheControl: "31536000",
                            contentType: "image/jpeg",
                            upsert: false
                        )
                    )
                    usage += Int64(prepared.data.count)
                    uploaded += 1
                }
                desiredPaths.insert(path)
                cropPath = path
                digest = prepared.digest
            } else {
                cropPath = nil
                digest = nil
            }
            garmentRows.append(
                CloudGarmentRow(ownerID: ownerID, value: value, cropPath: cropPath, digest: digest)
            )
        }

        var wardrobeRows: [CloudWardrobeRow] = []
        for value in export.wardrobe {
            try Task.checkCancellation()
            let prepared = try CloudImagePreparer.prepare(fileURL: value.cropURL)
            let path = "\(ownerID)/wardrobe/\(value.item.id.uuidString)-\(prepared.digest).jpg"
            if !previousRemotePaths.contains(path) {
                guard usage + Int64(prepared.data.count) <= quotaBytes else {
                    throw CloudLibraryError.quotaExceeded
                }
                try await client.storage.from(bucket).upload(
                    path,
                    data: prepared.data,
                    options: FileOptions(
                        cacheControl: "31536000",
                        contentType: "image/jpeg",
                        upsert: false
                    )
                )
                usage += Int64(prepared.data.count)
                uploaded += 1
            }
            desiredPaths.insert(path)
            wardrobeRows.append(
                CloudWardrobeRow(ownerID: ownerID, value: value, cropPath: path, digest: prepared.digest)
            )
        }

        try await reconcileGarments(garmentRows, ownerID: ownerID, desiredPaths: &desiredPaths)
        try await reconcileWardrobe(wardrobeRows, ownerID: ownerID, desiredPaths: &desiredPaths)
        try await reconcile(
            table: "stylezam_library_searches",
            rows: export.searches.map { CloudSearchRow(ownerID: ownerID, search: $0) },
            desiredIDs: Set(export.searches.map(\.id)),
            ownerID: ownerID
        )
        try await reconcile(
            table: "stylezam_library_products",
            rows: export.products.map { CloudProductRow(ownerID: ownerID, product: $0) },
            desiredIDs: Set(export.products.map(\.id)),
            ownerID: ownerID
        )
        try await reconcile(
            table: "stylezam_library_chats",
            rows: export.chats.map { CloudChatRow(ownerID: ownerID, thread: $0) },
            desiredIDs: Set(export.chats.map(\.id)),
            ownerID: ownerID
        )

        let stalePaths = Array(previousRemotePaths.subtracting(desiredPaths))
        if !stalePaths.isEmpty {
            for batch in stalePaths.chunked(size: 100) {
                try await client.storage.from(bucket).remove(paths: batch)
            }
        }
        usage = try await usageBytes()
        return CloudSyncOutcome(usageBytes: usage, uploadedCropCount: uploaded)
    }

    func match(embedding: String, limit: Int) async throws -> [CloudRelevantGarment] {
        struct Parameters: Encodable {
            let query_embedding: String
            let match_count: Int
        }
        return try await client
            .rpc(
                "stylezam_match_library_garments",
                params: Parameters(query_embedding: embedding, match_count: limit)
            )
            .execute()
            .value
    }

    func deleteAll(ownerID: String) async throws {
        let paths = Array(try await allRemoteCropPaths(ownerID: ownerID))
        for batch in paths.chunked(size: 100) {
            try await client.storage.from(bucket).remove(paths: batch)
        }
        for table in [
            "stylezam_library_chats", "stylezam_library_products",
            "stylezam_library_searches", "stylezam_library_wardrobe",
            "stylezam_library_garments",
        ] {
            try await client.from(table).delete(returning: .minimal)
                .eq("owner_id", value: ownerID).execute()
        }
    }

    private func usageBytes() async throws -> Int64 {
        try await client.rpc("stylezam_cloud_usage_bytes").execute().value
    }

    private func reconcileGarments(
        _ rows: [CloudGarmentRow],
        ownerID: String,
        desiredPaths: inout Set<String>
    ) async throws {
        try await reconcile(
            table: "stylezam_library_garments",
            rows: rows,
            desiredIDs: Set(rows.map(\.recordID)),
            ownerID: ownerID
        )
    }

    private func reconcileWardrobe(
        _ rows: [CloudWardrobeRow],
        ownerID: String,
        desiredPaths: inout Set<String>
    ) async throws {
        try await reconcile(
            table: "stylezam_library_wardrobe",
            rows: rows,
            desiredIDs: Set(rows.map { $0.recordID.uuidString }),
            ownerID: ownerID
        )
    }

    private func reconcile<Row: Encodable>(
        table: String,
        rows: [Row],
        desiredIDs: Set<String>,
        ownerID: String
    ) async throws {
        let remote: [CloudRemoteRecord] = try await client.from(table)
            .select("record_id")
            .eq("owner_id", value: ownerID)
            .execute()
            .value
        let stale = remote.map(\.recordID).filter { !desiredIDs.contains($0) }
        for batch in stale.chunked(size: 100) where !batch.isEmpty {
            let values: [any PostgrestFilterValue] = batch.map { $0 }
            try await client.from(table).delete(returning: .minimal)
                .in("record_id", values: values).execute()
        }
        for batch in rows.chunked(size: 100) where !batch.isEmpty {
            try await client.from(table)
                .upsert(batch, onConflict: "owner_id,record_id", returning: .minimal)
                .execute()
        }
    }

    private func allRemoteCropPaths(ownerID: String) async throws -> Set<String> {
        let garments: [CloudRemoteRecord] = try await client
            .from("stylezam_library_garments")
            .select("record_id,crop_path")
            .eq("owner_id", value: ownerID)
            .execute().value
        let wardrobe: [CloudRemoteRecord] = try await client
            .from("stylezam_library_wardrobe")
            .select("record_id,crop_path")
            .eq("owner_id", value: ownerID)
            .execute().value
        return Set((garments + wardrobe).compactMap(\.cropPath))
    }

    private func safePath(_ value: String) -> String {
        value.replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "/", with: "-")
    }
}

private enum CloudLibraryError: LocalizedError {
    case quotaExceeded
    case unreadableImage
    case configurationRequiredForDeletion

    var errorDescription: String? {
        switch self {
        case .quotaExceeded:
            "Your Cloud Library storage allowance is full. Remove saved pieces or change plans."
        case .unreadableImage:
            "A garment crop could not be prepared for private cloud storage."
        case .configurationRequiredForDeletion:
            "Restore the Supabase Project URL and publishable key before deleting this account so its private Cloud Library can be removed first."
        }
    }
}

private enum CloudImagePreparer {
    struct Prepared: Sendable {
        let data: Data
        let digest: String
    }

    static func prepare(fileURL: URL) throws -> Prepared {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2_048,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                ] as CFDictionary
              )
        else { throw CloudLibraryError.unreadableImage }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else { throw CloudLibraryError.unreadableImage }
        CGImageDestinationAddImage(
            destination,
            image,
            [kCGImageDestinationLossyCompressionQuality: 0.84] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else {
            throw CloudLibraryError.unreadableImage
        }
        let data = output as Data
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return Prepared(data: data, digest: digest)
    }
}

private struct CloudRemoteRecord: Decodable {
    let recordID: String
    let cropPath: String?

    enum CodingKeys: String, CodingKey {
        case recordID = "record_id"
        case cropPath = "crop_path"
    }
}

private struct CloudGarmentRow: Encodable {
    let recordID: String
    let ownerID: String
    let scanID: UUID
    let garmentID: String
    let createdAt: Date
    let origin: String
    let captureMode: String
    let title: String
    let category: String?
    let detectorLabel: String
    let detectorConfidence: Double
    let reviewState: String?
    let accepted: Bool
    let colors: [String]
    let materials: [String]
    let patterns: [String]
    let details: [String]
    let visibleText: [String]
    let cropPath: String?
    let contentDigest: String?
    let metadataEmbedding: String
    let updatedAt = Date()

    init(ownerID: String, value: CloudGarmentExport, cropPath: String?, digest: String?) {
        recordID = value.recordID
        self.ownerID = ownerID
        scanID = value.scan.id
        garmentID = value.garment.id
        createdAt = value.scan.createdAt
        origin = value.scan.origin.rawValue
        captureMode = value.scan.mode.rawValue
        title = value.garment.title
        category = value.garment.category
        detectorLabel = value.garment.localLabel
        detectorConfidence = value.garment.localConfidence
        reviewState = value.garment.reviewState?.rawValue
        accepted = value.garment.isPipelineEligible
        colors = value.garment.colors
        materials = value.garment.materials
        patterns = value.garment.patterns
        details = value.garment.details
        visibleText = value.garment.visibleText
        self.cropPath = cropPath
        contentDigest = digest
        metadataEmbedding = StylezamMetadataEmbedding.postgresVector(
            for: WardrobeRetrievalService.searchableText(for: value.garment)
        )
    }

    enum CodingKeys: String, CodingKey {
        case recordID = "record_id", ownerID = "owner_id", scanID = "scan_id"
        case garmentID = "garment_id", createdAt = "created_at", origin
        case captureMode = "capture_mode", title, category
        case detectorLabel = "detector_label", detectorConfidence = "detector_confidence"
        case reviewState = "review_state", accepted, colors, materials, patterns, details
        case visibleText = "visible_text", cropPath = "crop_path"
        case contentDigest = "content_digest", metadataEmbedding = "metadata_embedding"
        case updatedAt = "updated_at"
    }
}

private struct CloudWardrobeRow: Encodable {
    let recordID: UUID
    let ownerID: String
    let savedAt: Date
    let title: String
    let category: String
    let cropPath: String
    let contentDigest: String
    let sourceScanID: UUID?
    let sourceGarmentID: String?
    let sourceProduct: ProductResultDTO?
    let updatedAt = Date()

    init(ownerID: String, value: CloudWardrobeExport, cropPath: String, digest: String) {
        recordID = value.item.id
        self.ownerID = ownerID
        savedAt = value.item.savedAt
        title = value.item.title
        category = value.item.category.rawValue
        self.cropPath = cropPath
        contentDigest = digest
        sourceScanID = value.item.sourceScanID
        sourceGarmentID = value.item.sourceGarmentID
        sourceProduct = value.item.sourceProduct
    }

    enum CodingKeys: String, CodingKey {
        case recordID = "record_id", ownerID = "owner_id", savedAt = "saved_at"
        case title, category, cropPath = "crop_path", contentDigest = "content_digest"
        case sourceScanID = "source_scan_id", sourceGarmentID = "source_garment_id"
        case sourceProduct = "source_product", updatedAt = "updated_at"
    }
}

private struct CloudSearchRow: Encodable {
    let recordID: String
    let ownerID: String
    let scanID: UUID
    let garmentID: String
    let createdAt: Date
    let pipeline: String
    let providerSummary: String
    let generatedQuery: String?
    let resultCount: Int
    let results: [ProductResultDTO]
    let updatedAt = Date()

    init(ownerID: String, search: SavedProductSearch) {
        recordID = search.id; self.ownerID = ownerID; scanID = search.scanID
        garmentID = search.garmentID; createdAt = search.createdAt
        pipeline = search.pipeline.rawValue; providerSummary = search.providerSummary
        generatedQuery = search.generatedQuery; resultCount = search.results.count
        results = search.results
    }

    enum CodingKeys: String, CodingKey {
        case recordID = "record_id", ownerID = "owner_id", scanID = "scan_id"
        case garmentID = "garment_id", createdAt = "created_at", pipeline
        case providerSummary = "provider_summary", generatedQuery = "generated_query"
        case resultCount = "result_count", results, updatedAt = "updated_at"
    }
}

private struct CloudProductRow: Encodable {
    let recordID: String
    let ownerID: String
    let savedAt: Date
    let product: ProductResultDTO
    let updatedAt = Date()

    init(ownerID: String, product: SavedProduct) {
        recordID = product.id; self.ownerID = ownerID
        savedAt = product.savedAt; self.product = product.product
    }

    enum CodingKeys: String, CodingKey {
        case recordID = "record_id", ownerID = "owner_id", savedAt = "saved_at"
        case product, updatedAt = "updated_at"
    }
}

private struct CloudChatRow: Encodable {
    let recordID: String
    let ownerID: String
    let scanID: UUID
    let garmentID: String
    let messages: [StylezamChatMessage]
    let updatedAt: Date

    init(ownerID: String, thread: StylezamChatThread) {
        recordID = thread.id; self.ownerID = ownerID; scanID = thread.scanID
        garmentID = thread.garmentID; messages = thread.messages; updatedAt = thread.updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case recordID = "record_id", ownerID = "owner_id", scanID = "scan_id"
        case garmentID = "garment_id", messages, updatedAt = "updated_at"
    }
}

private extension Array {
    func chunked(size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
