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
                        detail: model.settings.notificationsEnabled ? "Search completion alerts are on" : "Search completion alerts are off"
                    )
                }

                NavigationLink {
                    PrivacySettingsView()
                } label: {
                    SettingsLinkLabel(
                        icon: "hand.raised",
                        title: "Privacy",
                        detail: "Uploads, local storage, retention, and deletion"
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
                        detail: "Backend address, service token, and server engines"
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
                Text("This route passes the actual screenshot into Stylezam and works on iOS 26.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                setupStep("1", "Add Take Screenshot")
                setupStep("2", "Add Search Image with Stylezam")
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
                Text("Open the Share sheet on an image or product page and choose Search with Stylezam.")
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
                        Text("Search finished")
                        Text("Send a local alert when matches are ready.")
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
                    Text("Search progress can appear on the Lock Screen and Dynamic Island independently of completion alerts.")
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
                detail: "Search history, saved products, and downloaded try-on previews are stored in Stylezam’s local Library."
            )
            privacySection(
                title: "Sent when you ask",
                icon: "arrow.up.doc",
                detail: "A photo leaves your iPhone only after you start a search or request a try-on. The configured backend processes that action."
            )
            privacySection(
                title: "Server credentials",
                icon: "key",
                detail: "OpenAI, Fireworks, Qwen, retrieval, and try-on keys stay on the server. The optional Stylezam service token is stored in Keychain."
            )

            Section {
                Button("Clear Library", role: .destructive) {
                    isConfirmingClear = true
                }
            } header: {
                Text("Your data")
            } footer: {
                Text("This removes local searches, saved products, and try-on previews, then asks the configured backend to delete related jobs and uploaded images. Provider retention can differ by service.")
            }
        }
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Clear Stylezam Library?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear searches, saved products, and try-ons", role: .destructive) {
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

    private var visibleProviders: [ProviderCapabilityDTO] {
        let ids = Set([
            "openai-vision",
            "fireworks-vision",
            "qwen-vision",
            "grounded-sam2",
            "youcam-clothes-v3",
        ])
        return model.capabilities?.providers.filter { ids.contains($0.id) } ?? []
    }

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                TextField("Backend address", text: $settings.backendURLString)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()

                SecureField("Service token (optional)", text: $settings.backendToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()

                Button {
                    isTesting = true
                    Task {
                        await model.refreshCapabilities()
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
                Text(model.serverMessage ?? "The optional service token is stored in Keychain.")
            }

            Section("API engines · backend only") {
                if visibleProviders.isEmpty {
                    Text("Connect to a backend to inspect OpenAI, Fireworks, Qwen, local vision, and YouCam.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(visibleProviders, id: \.id) { provider in
                        ProviderStatusRow(provider: provider)
                    }
                }
            }

            Section("Provider configuration") {
                Text("Add STYLEZAM_OPENAI_API_KEY, STYLEZAM_FIREWORKS_API_KEY, or STYLEZAM_QWEN_API_KEY to the backend environment and restart it. Model names and monthly caps are configured beside each server key.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Grounding DINO, SAM2, and CLIP are optional GPU-backed server workers. YouCam remains optional until virtual try-on is enabled for the deployment.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Developer Debug")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProviderStatusRow: View {
    let provider: ProviderCapabilityDTO

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: provider.configured ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(provider.configured ? StylezamDesign.cobalt : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(provider.name)
                    Spacer()
                    Text(provider.configured ? "Ready" : "Off")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let detail = provider.detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let limit = provider.monthlyLimitNote {
                    Text(limit)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
