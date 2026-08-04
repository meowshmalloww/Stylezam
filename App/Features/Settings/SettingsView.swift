import AppIntents
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                NavigationLink {
                    ControlSetupView()
                } label: {
                    SettingsLinkLabel(
                        icon: "button.programmable",
                        title: "Capture & Controls",
                        detail: "Shortcut, Control Center, Action Button, and live screen"
                    )
                }

                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    SettingsLinkLabel(
                        icon: "bell",
                        title: "Notifications",
                        detail: model.settings.notificationsEnabled ? "Capture completion alerts are on" : "Capture completion alerts are off"
                    )
                }

                NavigationLink {
                    PrivacySettingsView()
                } label: {
                    SettingsLinkLabel(
                        icon: "hand.raised",
                        title: "Privacy",
                        detail: "On-device vision, crop uploads, storage, and deletion"
                    )
                }
            }

            Section("Advanced") {
                NavigationLink {
                    DeveloperSettingsView()
                } label: {
                    SettingsLinkLabel(
                        icon: "hammer",
                        title: "Developer Debug",
                        detail: "Service connection, model pack, and capture limits"
                    )
                }
            }

            Section {
                Text("Stylezam 0.1 · iOS 26+")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
        }
        .contentMargins(.top, 12, for: .scrollContent)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SettingsLinkLabel: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(StylezamDesign.cobalt)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ControlSetupView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                Text("Use Apple’s system entry points when Stylezam is not already open.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Text("This route passes the actual screenshot into Stylezam for garment detection and works on iOS 26.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                setupStep("1", "Add Take Screenshot")
                setupStep("2", "Add Scan Image with Stylezam")
                ShortcutsLink()
                    .shortcutsLinkStyle(.automaticOutline)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } header: {
                Label("Screenshot Shortcut", systemImage: "rectangle.on.rectangle")
            } footer: {
                Text("Recommended for searching anything visible on screen without keeping a recorder active.")
            }

            Section {
                Text("Edit Control Center, add Stylezam’s Capture a Look control, then assign it to the Action Button for one-press access.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Control Center & Action Button", systemImage: "button.programmable")
            }

            Section {
                Text("Open the Share sheet on a fashion image and choose Stylezam to scan its visible pieces.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Share from another app", systemImage: "square.and.arrow.up")
            }

            Section {
                Text(model.liveScreen.statusSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if ScreenCaptureAvailability.isSDKAvailable {
                    Button {
                        model.liveScreen.presentSystemPicker()
                    } label: {
                        Label(
                            model.liveScreen.isCapturing ? "Change captured screen" : "Choose a screen",
                            systemImage: "rectangle.dashed.badge.record"
                        )
                    }

                    if model.liveScreen.isCapturing {
                        Button("Stop screen capture", role: .destructive) {
                            Task { await model.liveScreen.stopCapture() }
                        }
                    }
                }

                if let error = model.liveScreen.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                HStack {
                    Label("Live screen", systemImage: "rectangle.dashed.badge.record")
                    Spacer()
                    Text(ScreenCaptureAvailability.isSDKAvailable ? "AVAILABLE" : "iOS 27")
                }
            } footer: {
                Text("Apple’s system picker always starts the session. Protected video may appear blank; Stylezam never attempts silent recording.")
            }
        }
        .navigationTitle("Capture & Controls")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func setupStep(_ number: String, _ title: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(title)
                .font(.subheadline.weight(.medium))
        }
    }
}

private struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        List {
            Section {
                Toggle(isOn: $settings.notificationsEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Capture finished")
                        Text("Send a local alert when garment labels are ready.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(StylezamDesign.cobalt)
            } footer: {
                Text("You can change system notification permissions later in the iPhone Settings app.")
            }

            Section("Live Activity") {
                Label {
                    Text("Capture and live-screen status can appear on the Lock Screen and Dynamic Island independently of completion alerts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .foregroundStyle(StylezamDesign.cobalt)
                }
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrivacySettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var isConfirmingClear = false

    var body: some View {
        List {
            privacySection(
                title: "On this iPhone",
                icon: "iphone",
                detail: "Captured photos, segmented garment crops, saved products, and appearance previews are stored in Stylezam’s local Library. The downloadable garment model runs here too."
            )
            privacySection(
                title: "Sent when you ask",
                icon: "arrow.up.doc",
                detail: "The full capture stays on your iPhone during garment detection. Up to your configured item limit of segmented crops can be sent for detailed labels; the server deletes its temporary copies after the response."
            )
            privacySection(
                title: "Server credentials",
                icon: "key",
                detail: "The Fireworks credential stays on the CPU-only server. The Stylezam production service token is stored in Keychain. Stylezam does not put provider keys in the app."
            )

            Section {
                Button("Clear Library", role: .destructive) {
                    isConfirmingClear = true
                }
            } header: {
                Text("Your data")
            } footer: {
                Text("This removes local captures, garment crops, legacy searches, saved products, and appearance previews. Crop-label uploads are already deleted by the Stylezam server after each request; provider retention can differ by service.")
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Clear Stylezam Library?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear captures, saved products, and try-ons", role: .destructive) {
                model.clearLibrary()
            }
        } message: {
            Text("This action cannot be undone.")
        }
    }

    private func privacySection(title: String, icon: String, detail: String) -> some View {
        Section {
            Label {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(StylezamDesign.cobalt)
            }
        } header: {
            Text(title)
        }
    }
}

private struct DeveloperSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var isTesting = false

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                TextField("https://your-stylezam-service.example", text: $settings.backendURLString)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()

                SecureField("Service token", text: $settings.backendToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()

                Button {
                    isTesting = true
                    Task {
                        await model.refreshCapabilities()
                        await model.modelPack.refresh(using: try? model.settings.client())
                        isTesting = false
                    }
                } label: {
                    HStack {
                        Text("Test connection")
                        Spacer()
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
            } header: {
                Text("Connection")
            } footer: {
                Text(model.serverMessage ?? "Use the deployed HTTPS address. Localhost is intentionally rejected on iPhone; the production service token is stored in Keychain.")
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Garment model")
                        Text(model.modelPack.status.shortLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: model.modelPack.isInstalled ? "checkmark.circle.fill" : "arrow.down.circle")
                        .foregroundStyle(model.modelPack.isInstalled ? StylezamDesign.cobalt : .secondary)
                }

                if model.modelPack.isInstalled {
                    Button("Remove downloaded model", role: .destructive) {
                        do {
                            try model.modelPack.removeInstalledPack()
                        } catch {
                            model.lastError = error.localizedDescription
                        }
                    }
                } else {
                    Button("Download on Wi-Fi") {
                        guard let client = try? model.settings.client() else {
                            model.lastError = APIClientError.invalidBaseURL.localizedDescription
                            return
                        }
                        model.modelPack.download(using: client)
                    }
                    .disabled(isModelBusy)
                }
            } header: {
                Text("On-device vision")
            } footer: {
                Text("The current verified Core ML pack is about 59 MB. It is integrity-checked, compiled on this iPhone, and never runs on Daytona.")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Maximum pieces per scan")
                        Spacer()
                        Text(settings.maxDetectedItems, format: .number)
                            .font(.body.monospacedDigit().weight(.semibold))
                    }
                    Slider(
                        value: Binding(
                            get: { Double(settings.maxDetectedItems) },
                            set: { settings.maxDetectedItems = Int($0.rounded()) }
                        ),
                        in: 1...12,
                        step: 1
                    )
                    .tint(StylezamDesign.cobalt)
                }

                Toggle("Automatic capture in Live mode", isOn: $settings.liveAutoCaptureEnabled)
                    .tint(StylezamDesign.cobalt)
            } header: {
                Text("Capture behavior")
            } footer: {
                Text("Five is the safe default. Increasing the limit uses more memory, produces more crop uploads, and can make labeling slower.")
            }

            Section("Service roles") {
                serviceRow(
                    title: "Detailed crop labels",
                    ready: model.capabilities?.garmentLabeling == true
                )
                serviceRow(
                    title: "Model-pack delivery",
                    ready: model.capabilities?.modelPackAvailable == true
                )
                Text("The deployed service is CPU-only. Product retrieval, price lookup, YouCam, and GPU vision workers are not active in this phase.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Developer Debug")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var isModelBusy: Bool {
        switch model.modelPack.status {
        case .downloading, .compiling: true
        default: false
        }
    }

    private func serviceRow(title: String, ready: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(ready ? "Ready" : "Off")
                .font(.caption.weight(.medium))
                .foregroundStyle(ready ? StylezamDesign.cobalt : .secondary)
        }
    }
}
