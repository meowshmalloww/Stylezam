import CoreML
import Foundation
import Observation

enum ModelPackStatus: Equatable, Sendable {
    case checking
    case ready(version: String)
    case unavailable(String)

    var shortLabel: String {
        switch self {
        case .checking:
            "Preparing"
        case let .ready(version):
            "Built in · \(version)"
        case .unavailable:
            "Unavailable"
        }
    }
}

enum ModelPackError: LocalizedError {
    case missingManifest
    case invalidManifest
    case missingModel
    case compilationFailed(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingManifest:
            "The bundled garment model manifest is missing. Reinstall this build of Stylezam."
        case .invalidManifest:
            "The bundled garment model manifest is invalid."
        case .missingModel:
            "The bundled garment model could not be found. Reinstall this build of Stylezam."
        case let .compilationFailed(message):
            "The bundled garment model could not be prepared. \(message)"
        case let .unavailable(message):
            message
        }
    }
}

/// Resolves the garment detector shipped inside the application bundle.
///
/// Xcode normally compiles the source `.mlpackage` into an optimized `.mlmodelc`
/// resource at build time. The source-package fallback keeps local development
/// builds usable if a project generator copies the package without compiling it.
@MainActor
@Observable
final class ModelPackManager {
    private(set) var status: ModelPackStatus = .checking
    private(set) var manifest: ModelPackManifestDTO?
    private(set) var activeModelURL: URL?
    private(set) var lastError: String?

    @ObservationIgnored private var prepareTask: Task<Void, Never>?

    init() {}

    var isInstalled: Bool {
        activeModelURL != nil
    }

    func refresh() async {
        if isInstalled { return }
        if let prepareTask {
            await prepareTask.value
            return
        }

        status = .checking
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let resolvedManifest = try Self.loadManifest()
                let modelURL = try await Self.resolveModelURL()
                manifest = resolvedManifest
                activeModelURL = modelURL
                lastError = nil
                status = .ready(version: resolvedManifest.version)
            } catch {
                manifest = nil
                activeModelURL = nil
                lastError = error.localizedDescription
                status = .unavailable(error.localizedDescription)
            }
        }
        prepareTask = task
        await task.value
        prepareTask = nil
    }

    private nonisolated static func loadManifest() throws -> ModelPackManifestDTO {
        guard let url = firstBundleURL(
            resource: "garment-segmentation",
            extension: "json"
        ) else {
            throw ModelPackError.missingManifest
        }
        let manifest = try JSONDecoder().decode(
            ModelPackManifestDTO.self,
            from: Data(contentsOf: url)
        )
        guard manifest.modelID == "garment-rfdetr-seg-small",
              manifest.inputResolution == 384,
              manifest.classNames.count == 46,
              manifest.classNames.prefix(27).allSatisfy({ !$0.isEmpty })
        else {
            throw ModelPackError.invalidManifest
        }
        return manifest
    }

    private nonisolated static func resolveModelURL() async throws -> URL {
        if let compiled = bundledCompiledModelURL() {
            return compiled
        }

        guard let package = firstBundleURL(
            resource: "StylezamGarmentSegmentation",
            extension: "mlpackage"
        ) else {
            throw ModelPackError.missingModel
        }
        do {
            return try await Task.detached(priority: .userInitiated) {
                try MLModel.compileModel(at: package)
            }.value
        } catch {
            throw ModelPackError.compilationFailed(error.localizedDescription)
        }
    }

    /// Compiled Core ML resources are directories. On physical devices,
    /// `Bundle.url(forResource:withExtension:)` can omit directory resources,
    /// even though the signed bundle contains them. Resolve the exact Xcode
    /// output path first, then enumerate as a defensive fallback.
    private nonisolated static func bundledCompiledModelURL() -> URL? {
        let expectedFilename = "StylezamGarmentSegmentation.mlmodelc"
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent(
                expectedFilename,
                isDirectory: true
            ),
            Bundle.main.resourceURL?.appendingPathComponent(
                expectedFilename,
                isDirectory: true
            ),
            Bundle.main.bundleURL
                .appendingPathComponent("Models", isDirectory: true)
                .appendingPathComponent(expectedFilename, isDirectory: true),
        ].compactMap { $0 }

        if let exactMatch = candidates.first(where: isCompiledModelDirectory) {
            return exactMatch
        }

        let resourceKeys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
        if let enumerator = FileManager.default.enumerator(
            at: Bundle.main.bundleURL,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) {
            for case let url as URL in enumerator where
                url.lastPathComponent == expectedFilename
                && isCompiledModelDirectory(url)
            {
                return url
            }
        }

#if DEBUG
        let visibleBundleItems = (
            try? FileManager.default.contentsOfDirectory(
                at: Bundle.main.bundleURL,
                includingPropertiesForKeys: resourceKeys
            )
        )?.map(\.lastPathComponent).sorted() ?? []
        print("STYLEZAM_MODEL_BUNDLE \(Bundle.main.bundleURL.path)")
        print("STYLEZAM_MODEL_CANDIDATES \(candidates.map(\.path))")
        print("STYLEZAM_MODEL_BUNDLE_ITEMS \(visibleBundleItems)")
#endif
        return nil
    }

    private nonisolated static func isCompiledModelDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) && isDirectory.boolValue
    }

    private nonisolated static func firstBundleURL(
        resource: String,
        extension fileExtension: String
    ) -> URL? {
        if let resolved = Bundle.main.url(
            forResource: resource,
            withExtension: fileExtension,
            subdirectory: "Models"
        ) ?? Bundle.main.url(forResource: resource, withExtension: fileExtension) {
            return resolved
        }
        let filename = "\(resource).\(fileExtension)"
        let candidates = [
            Bundle.main.bundleURL
                .appending(path: "Models", directoryHint: .isDirectory)
                .appending(path: filename, directoryHint: .isDirectory),
            Bundle.main.bundleURL.appending(path: filename, directoryHint: .isDirectory),
        ]
        return candidates.first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }
}
