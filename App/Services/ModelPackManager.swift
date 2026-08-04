import CoreML
import CryptoKit
import Foundation
import Network
import Observation

enum ModelPackStatus: Equatable, Sendable {
    case checking
    case notInstalled
    case requiresWiFi
    case downloading(Double)
    case compiling
    case installed(version: String)
    case unavailable(String)

    var shortLabel: String {
        switch self {
        case .checking: "Checking"
        case .notInstalled: "Not downloaded"
        case .requiresWiFi: "Waiting for Wi-Fi"
        case let .downloading(progress): "Downloading \(progress.formatted(.percent.precision(.fractionLength(0))))"
        case .compiling: "Preparing on this iPhone"
        case let .installed(version): "Installed · \(version)"
        case .unavailable: "Unavailable"
        }
    }
}

enum ModelPackError: LocalizedError {
    case wifiRequired
    case invalidFilePath
    case invalidResponse
    case invalidManifest
    case sizeMismatch
    case checksumMismatch
    case incompletePackage

    var errorDescription: String? {
        switch self {
        case .wifiRequired:
            "Connect to Wi-Fi to download the garment model."
        case .invalidFilePath:
            "The service returned an unsafe model file path."
        case .invalidResponse:
            "The model download returned an invalid response."
        case .invalidManifest:
            "The service returned an invalid model-pack manifest."
        case .sizeMismatch:
            "A model file did not match its published size."
        case .checksumMismatch:
            "A model file failed its integrity check."
        case .incompletePackage:
            "The downloaded Core ML package is incomplete."
        }
    }
}

@MainActor
@Observable
final class ModelPackManager {
    private(set) var status: ModelPackStatus = .checking
    private(set) var manifest: ModelPackManifestDTO?
    private(set) var activeModelURL: URL?
    private(set) var lastError: String?

    @ObservationIgnored private let rootURL: URL
    @ObservationIgnored private let currentManifestURL: URL
    @ObservationIgnored private var downloadTask: Task<Void, Never>?

    init() {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        rootURL = applicationSupport
            .appending(path: "Stylezam", directoryHint: .isDirectory)
            .appending(path: "ModelPacks", directoryHint: .isDirectory)
        currentManifestURL = rootURL.appending(path: "current.json")
        restoreInstalledPack()
    }

    var isInstalled: Bool {
        activeModelURL != nil
    }

    func refresh(using client: APIClient?) async {
        if isInstalled {
            return
        }
        guard let client else {
            status = .notInstalled
            return
        }
        status = .checking
        do {
            manifest = try await client.garmentModelPack()
            status = .notInstalled
            lastError = nil
        } catch {
            status = .unavailable(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func download(using client: APIClient) {
        downloadTask?.cancel()
        downloadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let resolvedManifest = try await client.garmentModelPack()
                manifest = resolvedManifest
                guard await WiFiRequirement.isConnected else {
                    throw ModelPackError.wifiRequired
                }
                try await install(resolvedManifest, using: client)
            } catch is CancellationError {
                return
            } catch ModelPackError.wifiRequired {
                status = .requiresWiFi
                lastError = ModelPackError.wifiRequired.localizedDescription
            } catch {
                status = .unavailable(error.localizedDescription)
                lastError = error.localizedDescription
            }
        }
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        status = isInstalled ? .installed(version: manifest?.version ?? "") : .notInstalled
    }

    func removeInstalledPack() throws {
        downloadTask?.cancel()
        if let manifest {
            let directory = installedDirectory(for: manifest)
            if FileManager.default.fileExists(atPath: directory.path) {
                try FileManager.default.removeItem(at: directory)
            }
        }
        try? FileManager.default.removeItem(at: currentManifestURL)
        manifest = nil
        activeModelURL = nil
        lastError = nil
        status = .notInstalled
    }

    private func install(_ manifest: ModelPackManifestDTO, using client: APIClient) async throws {
        try Self.validate(manifest)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let staging = rootURL.appending(
            path: "Staging-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let package = staging.appending(
            path: "StylezamGarmentSegmentation.mlpackage",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        var downloadedBytes = 0
        for file in manifest.files {
            try Task.checkCancellation()
            let relative = try Self.safeRelativePath(file.path)
            let destination = package.appending(path: relative)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let request = try client.modelPackDownloadRequest(for: file.url)
            let (temporaryURL, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode)
            else {
                throw ModelPackError.invalidResponse
            }
            let attributes = try FileManager.default.attributesOfItem(atPath: temporaryURL.path)
            guard (attributes[.size] as? NSNumber)?.intValue == file.bytes else {
                throw ModelPackError.sizeMismatch
            }
            guard try Self.sha256(of: temporaryURL) == file.sha256.lowercased() else {
                throw ModelPackError.checksumMismatch
            }
            try FileManager.default.copyItem(at: temporaryURL, to: destination)
            downloadedBytes += file.bytes
            status = .downloading(
                min(1, Double(downloadedBytes) / Double(max(1, manifest.totalBytes)))
            )
        }

        guard FileManager.default.fileExists(atPath: package.appending(path: "Manifest.json").path),
              FileManager.default.fileExists(
                  atPath: package.appending(path: "Data/com.apple.CoreML/model.mlmodel").path
              ),
              FileManager.default.fileExists(
                  atPath: package.appending(path: "Data/com.apple.CoreML/weights/weight.bin").path
              )
        else {
            throw ModelPackError.incompletePackage
        }

        status = .compiling
        let compiledTemporary = try await Task.detached(priority: .userInitiated) {
            try MLModel.compileModel(at: package)
        }.value
        let destinationDirectory = installedDirectory(for: manifest)
        if FileManager.default.fileExists(atPath: destinationDirectory.path) {
            try FileManager.default.removeItem(at: destinationDirectory)
        }
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )
        let compiledDestination = destinationDirectory.appending(
            path: "StylezamGarmentSegmentation.mlmodelc",
            directoryHint: .isDirectory
        )
        try FileManager.default.copyItem(at: compiledTemporary, to: compiledDestination)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(manifest).write(to: currentManifestURL, options: .atomic)

        self.manifest = manifest
        activeModelURL = compiledDestination
        status = .installed(version: manifest.version)
        lastError = nil
    }

    private func restoreInstalledPack() {
        do {
            guard FileManager.default.fileExists(atPath: currentManifestURL.path) else {
                status = .notInstalled
                return
            }
            let restored = try JSONDecoder().decode(
                ModelPackManifestDTO.self,
                from: Data(contentsOf: currentManifestURL)
            )
            try Self.validate(restored)
            let compiled = installedDirectory(for: restored).appending(
                path: "StylezamGarmentSegmentation.mlmodelc",
                directoryHint: .isDirectory
            )
            guard FileManager.default.fileExists(atPath: compiled.path) else {
                throw ModelPackError.incompletePackage
            }
            manifest = restored
            activeModelURL = compiled
            status = .installed(version: restored.version)
        } catch {
            manifest = nil
            activeModelURL = nil
            status = .unavailable(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    private func installedDirectory(for manifest: ModelPackManifestDTO) -> URL {
        rootURL
            .appending(path: manifest.modelID, directoryHint: .isDirectory)
            .appending(path: manifest.version, directoryHint: .isDirectory)
    }

    private nonisolated static func safeRelativePath(_ value: String) throws -> String {
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard !value.hasPrefix("/"),
              !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else {
            throw ModelPackError.invalidFilePath
        }
        return components.joined(separator: "/")
    }

    private nonisolated static func validate(_ manifest: ModelPackManifestDTO) throws {
        let requiredPaths: Set<String> = [
            "Manifest.json",
            "Data/com.apple.CoreML/model.mlmodel",
            "Data/com.apple.CoreML/weights/weight.bin",
        ]
        guard safePathComponent(manifest.modelID),
              safePathComponent(manifest.version),
              manifest.inputResolution == 384,
              manifest.classNames.count == 46,
              !manifest.files.isEmpty,
              manifest.files.count <= 8,
              Set(manifest.files.map(\.path)) == requiredPaths,
              manifest.files.allSatisfy({
                  $0.bytes > 0
                      && $0.sha256.range(
                          of: "^[0-9a-fA-F]{64}$",
                          options: .regularExpression
                      ) != nil
              })
        else {
            throw ModelPackError.invalidManifest
        }
        let computedTotal = manifest.files.reduce(into: Int64(0)) {
            $0 += Int64($1.bytes)
        }
        guard computedTotal == Int64(manifest.totalBytes),
              computedTotal <= 250 * 1_048_576
        else {
            throw ModelPackError.invalidManifest
        }
        for file in manifest.files {
            _ = try safeRelativePath(file.path)
        }
    }

    private nonisolated static func safePathComponent(_ value: String) -> Bool {
        guard !value.isEmpty, value != ".", value != ".." else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
                || $0 == "-"
                || $0 == "_"
                || $0 == "."
        }
    }

    private nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            digest.update(data: data)
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private enum WiFiRequirement {
    static var isConnected: Bool {
        get async {
            await withCheckedContinuation { continuation in
                let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
                let queue = DispatchQueue(label: "com.stylezam.model-pack.wifi")
                monitor.pathUpdateHandler = { path in
                    monitor.cancel()
                    continuation.resume(returning: path.status == .satisfied)
                }
                monitor.start(queue: queue)
            }
        }
    }
}
