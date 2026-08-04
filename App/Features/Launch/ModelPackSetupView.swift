import SwiftUI

struct ModelPackSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ON-DEVICE VISION")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.35)
                            .foregroundStyle(.secondary)
                        Text("Find each piece before anything leaves your iPhone.")
                            .font(.system(size: 34, weight: .semibold))
                            .tracking(-1.1)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("The garment model separates clothing and accessories into individual crops. The full photo stays local; only those crops can be sent for detailed labels.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(spacing: 0) {
                        setupRow(
                            icon: "iphone",
                            title: "Runs on this iPhone",
                            detail: "No Daytona GPU and no per-frame cloud upload"
                        )
                        EditorialRule().padding(.leading, 52)
                        setupRow(
                            icon: "wifi",
                            title: "Wi-Fi download only",
                            detail: sizeDescription
                        )
                        EditorialRule().padding(.leading, 52)
                        setupRow(
                            icon: "checkmark.shield",
                            title: "Integrity checked",
                            detail: "Every model file is verified before Core ML compiles it"
                        )
                    }
                    .padding(.horizontal, 16)
                    .background(
                        Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )

                    actionArea

                    if let attribution = model.modelPack.manifest?.attribution {
                        Text(attribution)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(StylezamDesign.pageInset)
                .padding(.bottom, 24)
            }
            .background(StylezamDesign.canvas)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Not now") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(isBusy)
        .onChange(of: model.modelPack.isInstalled) { _, installed in
            if installed {
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    dismiss()
                }
            }
        }
    }

    @ViewBuilder
    private var actionArea: some View {
        switch model.modelPack.status {
        case let .downloading(progress):
            HStack(spacing: 12) {
                ProgressView().tint(StylezamDesign.cobalt)
                Text("Downloading · \(progress.formatted(.percent.precision(.fractionLength(0))))")
                    .font(.headline.monospacedDigit())
            }
            .frame(maxWidth: .infinity, minHeight: 54)
        case .compiling:
            HStack(spacing: 12) {
                ProgressView().tint(StylezamDesign.cobalt)
                Text("Preparing Core ML")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
        case .requiresWiFi:
            VStack(alignment: .leading, spacing: 12) {
                Label("Connect to Wi-Fi, then try again.", systemImage: "wifi.exclamationmark")
                    .font(.subheadline.weight(.medium))
                downloadButton
            }
        case .installed:
            Label("Garment model installed", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(StylezamDesign.cobalt)
        default:
            if (try? model.settings.client()) == nil {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Connect the deployed Stylezam service first. The app does not use localhost on iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        model.selectedTab = .settings
                        dismiss()
                    } label: {
                        Text("Open Developer Debug")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(StylezamDesign.cobalt)
                }
            } else {
                downloadButton
            }
        }
    }

    private var downloadButton: some View {
        Button {
            guard let client = try? model.settings.client() else { return }
            model.modelPack.download(using: client)
        } label: {
            HStack {
                Text("Download garment model")
                Spacer()
                Image(systemName: "arrow.down")
            }
            .fontWeight(.semibold)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
        }
        .buttonStyle(.glassProminent)
        .tint(StylezamDesign.cobalt)
    }

    private var sizeDescription: String {
        if let bytes = model.modelPack.manifest?.totalBytes {
            return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
        return "About 59 MB for the current model pack"
    }

    private var isBusy: Bool {
        switch model.modelPack.status {
        case .downloading, .compiling: true
        default: false
        }
    }

    private func setupRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(StylezamDesign.cobalt)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
    }
}
