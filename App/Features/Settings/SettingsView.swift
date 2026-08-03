import AppIntents
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var isTesting = false
    @State private var isConfirmingClear = false

    var body: some View {
        @Bindable var settings = model.settings
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                HStack(alignment: .top, spacing: 14) {
                    OrbitingBrandMark(size: 70)
                    PageTitle(
                        title: "Settings",
                        subtitle: "Connect the service, choose capture shortcuts, and review what is enabled."
                    )
                }
                .padding(.top, 18)
                .motionReveal()

                serviceSection(settings: settings)
                    .motionReveal(delay: 0.05)
                captureSection
                    .motionReveal(delay: 0.1)
                providerSection
                    .motionReveal(delay: 0.15)
                preferencesSection(settings: settings)
                    .motionReveal(delay: 0.2)
                privacySection
                    .motionReveal(delay: 0.24)
            }
            .padding(.horizontal, StylezamDesign.pageInset)
            .padding(.bottom, 110)
        }
        .background(StylezamDesign.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Clear Stylezam library?",
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button("Clear captures and bookmarks", role: .destructive) {
                model.clearLibrary()
            }
        } message: {
            Text("This removes local captures and bookmarks, then asks the configured backend to delete their search jobs and uploaded images.")
        }
    }

    private func serviceSection(settings: SettingsStore) -> some View {
        @Bindable var settings = settings
        return setupSection(
            number: "01",
            title: "Service",
            detail: "The iPhone never stores provider API keys."
        ) {
            VStack(alignment: .leading, spacing: 13) {
                TextField("https://your-stylezam-server.example", text: $settings.backendURLString)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 15)
                    .frame(height: 54)
                    .glassEffect(
                        .regular,
                        in: RoundedRectangle(cornerRadius: StylezamDesign.compactRadius)
                    )

                SecureField("Service token (optional for localhost)", text: $settings.backendToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()
                    .padding(.horizontal, 15)
                    .frame(height: 54)
                    .glassEffect(
                        .regular,
                        in: RoundedRectangle(cornerRadius: StylezamDesign.compactRadius)
                    )

                Label("The token is stored in this iPhone’s Keychain.", systemImage: "key")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .center, spacing: 10) {
                    Circle()
                        .fill(model.capabilities == nil ? Color.red : StylezamDesign.cobalt)
                        .frame(width: 7, height: 7)
                    Text(model.serverMessage ?? "Connection not checked")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 6)
                    Button {
                        isTesting = true
                        Task {
                            await model.refreshCapabilities()
                            isTesting = false
                        }
                    } label: {
                        if isTesting {
                            ProgressView()
                                .frame(width: 82)
                        } else {
                            Text("Test")
                                .frame(width: 58)
                        }
                    }
                    .buttonStyle(.glass)
                }

                Text("Simulator: use 127.0.0.1. A physical iPhone needs an HTTPS URL or a service reachable on its network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var captureSection: some View {
        setupSection(
            number: "02",
            title: "Capture anywhere",
            detail: "The dependable path works on iOS 26; live screen adds an iOS 27 option."
        ) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 13) {
                        setupIcon("rectangle.on.rectangle.badge.plus", isPrimary: true)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("Screenshot Shortcut")
                                    .font(.headline)
                                Spacer()
                                StatusPill(text: "Recommended")
                            }
                            Text("Build a two-action Shortcut. It passes the actual screenshot into Stylezam instead of relying on background screen access.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    shortcutStep("01", "Take Screenshot")
                    shortcutStep("02", "Search Image with Stylezam")

                    ShortcutsLink()
                        .shortcutsLinkStyle(.automaticOutline)
                }
                .padding(18)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: StylezamDesign.cardRadius))

                featureRow(
                    icon: "switch.2",
                    title: "Control Center + Action Button",
                    detail: "Add Stylezam’s Capture a Look control in Control Center, then assign that control to the Action Button if you want one-press entry."
                )
                EditorialRule()
                featureRow(
                    icon: "square.and.arrow.up",
                    title: "Share sheet",
                    detail: "Share an image, URL, or text from another app to Search with Stylezam."
                )
                EditorialRule()
                featureRow(
                    icon: "rectangle.dashed.badge.record",
                    title: "iOS 27 live screen",
                    detail: model.liveScreen.statusSummary
                )

                if ScreenCaptureAvailability.isSDKAvailable {
                    HStack(spacing: 10) {
                        Button {
                            model.liveScreen.presentSystemPicker()
                        } label: {
                            Label(
                                model.liveScreen.isCapturing ? "Change screen" : "Choose a screen",
                                systemImage: "rectangle.dashed.badge.record"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(StylezamDesign.cobalt)

                        if model.liveScreen.isCapturing {
                            Button("Stop", role: .destructive) {
                                Task { await model.liveScreen.stopCapture() }
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }

                if let error = model.liveScreen.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Text("Apple’s system picker always initiates live screen selection. Protected video may be blank; Stylezam does not attempt silent recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var providerSection: some View {
        setupSection(
            number: "03",
            title: "Real providers",
            detail: "Unconfigured sources stay off; no sample listings are substituted."
        ) {
            if let capabilities = model.capabilities {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(capabilities.providers.enumerated()), id: \.element.id) { index, provider in
                        HStack(alignment: .top, spacing: 13) {
                            setupIcon(
                                provider.configured ? "checkmark" : "minus",
                                isPrimary: provider.configured
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(provider.name)
                                        .font(.headline)
                                    Spacer()
                                    Text(provider.configured ? "ON" : "OFF")
                                        .font(.caption2.monospacedDigit().weight(.bold))
                                        .foregroundStyle(provider.configured ? StylezamDesign.cobalt : .secondary)
                                }
                                if let detail = provider.detail {
                                    Text(detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                if let limit = provider.monthlyLimitNote {
                                    Text(limit.uppercased())
                                        .font(.caption2.weight(.semibold))
                                        .tracking(0.6)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .padding(.vertical, 13)
                        .motionReveal(delay: min(Double(index) * 0.04, 0.2), distance: 10)

                        if index < capabilities.providers.count - 1 {
                            EditorialRule()
                        }
                    }
                }
            } else {
                Text("Connect to the backend to inspect the sources and their hard monthly limits.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func preferencesSection(settings: SettingsStore) -> some View {
        @Bindable var settings = settings
        return setupSection(
            number: "04",
            title: "Completion",
            detail: "Search progress also appears as a local Live Activity."
        ) {
            Toggle("Notify when a search finishes", isOn: $settings.notificationsEnabled)
                .font(.headline)
                .tint(StylezamDesign.cobalt)
                .padding(18)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: StylezamDesign.cardRadius))
        }
    }

    private var privacySection: some View {
        setupSection(
            number: "05",
            title: "Privacy",
            detail: "A capture is transmitted only after you start a search or try-on."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Photos remain in Stylezam’s local archive and are uploaded to the configured backend only for the action you request. API keys remain server-side. Completed try-ons are downloaded back to the iPhone, then Stylezam removes its backend person photo and generated copy.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("YouCam’s current API terms state that provider-side user submissions are automatically deleted after one day and generated content after 30 days. Its Clothes v3 API does not publish an early-delete operation, so Stylezam does not claim one.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("No affiliate redirects, ad tracking, hidden browser history, or invented product results.")
                    .font(.subheadline.weight(.semibold))
                Button("Clear captures and bookmarks", role: .destructive) {
                    isConfirmingClear = true
                }
                .buttonStyle(.glass)
                .padding(.top, 2)
            }
        }
    }

    private func setupSection<Content: View>(
        number: String,
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            Text(title)
                .font(.title2.weight(.semibold))
                .fontDesign(.serif)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func shortcutStep(_ number: String, _ title: String) -> some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(StylezamDesign.cobalt)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
        .padding(.leading, 40)
    }

    private func setupIcon(_ symbol: String, isPrimary: Bool) -> some View {
        Image(systemName: symbol)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(isPrimary ? .white : .secondary)
            .frame(width: 32, height: 32)
            .background(isPrimary ? StylezamDesign.cobalt : Color.secondary.opacity(0.12), in: Circle())
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 13) {
            setupIcon(icon, isPrimary: false)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
