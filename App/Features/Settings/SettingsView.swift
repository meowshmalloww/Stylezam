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
                        detail: "On-device vision, local storage, and deletion"
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
                        detail: "Bundled model, vision inspector, and capture limits"
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
                detail: "The garment model, detection, segmentation, captured photos, and transparent garment crops all stay on this iPhone. The model is included with the app."
            )
            privacySection(
                title: "No processing server",
                icon: "network.slash",
                detail: "Stylezam does not upload captures or crops for detection and does not require a server, service token, or AI-provider key."
            )
            privacySection(
                title: "Network access",
                icon: "safari",
                detail: "This local vision build does not perform product retrieval or virtual try-on. Older saved product cards can still open their merchant links when you choose them."
            )

            Section {
                Button("Clear Library", role: .destructive) {
                    isConfirmingClear = true
                }
            } header: {
                Text("Your data")
            } footer: {
                Text("This removes local captures, garment crops, legacy searches, saved products, and appearance previews. Nothing is deleted from another device or service.")
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

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            Section {
                NavigationLink {
                    VisionDebugView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Vision Inspector")
                            Text("See real boxes, masks, crops, confidence, and timing")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "viewfinder.rectangular")
                            .foregroundStyle(StylezamDesign.cobalt)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Garment model")
                        Text(model.modelPack.status.shortLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: model.modelPack.isInstalled ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(model.modelPack.isInstalled ? StylezamDesign.cobalt : .secondary)
                }

                if let manifest = model.modelPack.manifest {
                    LabeledContent("Model size") {
                        Text(
                            ByteCountFormatter.string(
                                fromByteCount: Int64(manifest.totalBytes),
                                countStyle: .file
                            )
                        )
                    }
                    LabeledContent("Input", value: "\(manifest.inputResolution) × \(manifest.inputResolution)")
                    LabeledContent("Classes", value: "\(manifest.classNames.count)")
                }
            } header: {
                Text("On-device vision")
            } footer: {
                Text("The verified Core ML model is part of the app bundle and uses Apple’s local compute path. There is no model download and no processing server.")
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
                Text("Five is the safe default. Increasing the limit uses more memory and can make local segmentation and crop generation slower.")
            }

            Section("Runtime") {
                runtimeRow(title: "Garment detection", value: model.modelPack.isInstalled ? "Ready" : "Unavailable")
                runtimeRow(title: "Segmentation crops", value: "On device")
                runtimeRow(title: "Product retrieval", value: "Not built yet")
                runtimeRow(title: "Virtual try-on", value: "Not built yet")
            }
        }
        .navigationTitle("Developer Debug")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func runtimeRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(value == "Ready" || value == "On device" ? StylezamDesign.cobalt : .secondary)
        }
    }
}
