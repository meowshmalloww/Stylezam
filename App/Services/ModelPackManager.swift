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
        if let compiled = firstBundleURL(
            resource: "StylezamGarmentSegmentation",
            extension: "mlmodelc"
        ) {
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

    private nonisolated static func firstBundleURL(
        resource: String,
        extension fileExtension: String
    ) -> URL? {
        Bundle.main.url(
            forResource: resource,
            withExtension: fileExtension,
            subdirectory: "Models"
        ) ?? Bundle.main.url(forResource: resource, withExtension: fileExtension)
    }
}
