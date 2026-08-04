import AppIntents
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("stylezam.onboarding.completed") private var onboardingCompleted = false

    var body: some View {
        List {
            if let account = model.account.account {
                Section {
                    NavigationLink {
                        AccountView()
                    } label: {
                        AccountIdentityHeader(account: account)
                    }

                    NavigationLink {
                        SubscriptionPlansView()
                    } label: {
                        SettingsLinkLabel(
                            icon: "creditcard",
                            title: "Membership",
                            detail: account.plan == .developer ? "Developer · unlimited internal usage" : "Free · Plus and Pro previews"
                        )
                    }
                } header: {
                    Text("Account")
                }
            } else {
                Section {
                    NavigationLink {
                        LoginView()
                    } label: {
                        SettingsLinkLabel(
                            icon: "person.crop.circle",
                            title: "Sign in",
                            detail: "Required · continue with your Google account"
                        )
                    }
                } header: {
                    Text("Account")
                }
            }

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

            if developerToolsAvailable {
                Section("Developer") {
                    NavigationLink {
                        DeveloperSettingsView()
                    } label: {
                        SettingsLinkLabel(
                            icon: "hammer",
                            title: "Developer Debug",
                            detail: "Verified role · vision, providers, quotas, credentials, and request logs"
                        )
                    }

                    Button {
                        withAnimation(.easeInOut(duration: 0.28)) {
                            onboardingCompleted = false
                        }
                    } label: {
                        SettingsLinkLabel(
                            icon: "sparkles.rectangle.stack",
                            title: "Replay First Run",
                            detail: "Preview the new-user welcome screen without deleting your Library"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Text("Stylezam · Private developer build")
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

    private var developerToolsAvailable: Bool {
        model.account.isDeveloper
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
                Text("Add both Stylezam controls from Control Center’s edit gallery. Capture a Look opens the camera. Live Screen opens Stylezam and immediately asks Apple to show its screen picker.")
                    .foregroundStyle(.secondary)
                setupStep("1", "Open Control Center and tap +")
                setupStep("2", "Choose Add a Control")
                setupStep("3", "Add Capture a Look and Live Screen")
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
                Text("Capture a Look opens Stylezam’s front/back camera. Live Screen is a separate control because iOS requires explicit system consent before Stylezam can view another app’s screen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Label("Two controls", systemImage: "button.programmable")
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
                detail: "Garment detection and cropping run on this iPhone. Captures, crops, searches, saved products, and previews are stored locally."
            )
            privacySection(
                title: "Only when you search",
                icon: "network",
                detail: "Stylezam sends only the selected garment crop to the provider you configured after you tap Find. The Qwen route sends the crop to Fireworks; Serper receives generated text keywords, not the photo."
            )
            privacySection(
                title: "Developer credentials",
                icon: "key",
                detail: "Provider keys are stored in the device-only Keychain and never written to the Library. Direct provider keys are intended for your private developer build, not a public App Store release."
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
                    LabeledContent(
                        "Model tile",
                        value: "\(manifest.inputResolution) × \(manifest.inputResolution) · fixed"
                    )
                    LabeledContent("Still-photo source", value: "Up to 5120 px")
                    LabeledContent("Detail passes", value: "1 global + up to 6 tiles")
                    LabeledContent("Classes", value: "\(manifest.classNames.count)")
                }
            } header: {
                Text("On-device vision")
            } footer: {
                Text("384 × 384 is one model tile, not the saved-photo or crop resolution. Still photos retain up to a 5120 px long edge and use overlapping detail tiles before boxes are projected back onto the high-resolution source.")
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

            Section {
                LabeledContent("Exact product search") {
                    Text("Visual provider")
                        .foregroundStyle(.secondary)
                }

                Picker("Image provider", selection: $settings.imageSearchProvider) {
                    ForEach(ImageSearchProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }

                if !settings.imageSearchProvider.acceptsPrivateImageData {
                    TextField("Public HTTPS garment image URL", text: $settings.publicImageURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                if settings.imageSearchProvider == .brightData {
                    TextField("Bright Data SERP zone", text: $settings.brightDataZone)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Stepper(
                    "Searches per piece: \(settings.productSearchesPerPiece)",
                    value: $settings.productSearchesPerPiece,
                    in: 1...5
                )
                Stepper(
                    "Results shown: \(settings.productResultLimit)",
                    value: $settings.productResultLimit,
                    in: 1...20
                )

                NavigationLink("Monthly safety limits") {
                    SearchLimitsDebugView()
                }
            } header: {
                Text("Product search")
            } footer: {
                Text("The main Search button sends the selected crop directly to the visual provider. Fireworks is used only by Stylezam AI and AI-guided refinements. Failed requests remain retryable; provider request diagnostics are still retained.")
            }

            Section {
                ForEach(SearchCredentialKind.allCases) { kind in
                    NavigationLink {
                        CredentialEditorView(kind: kind)
                    } label: {
                        HStack {
                            Text(kind.title)
                            Spacer()
                            Text(model.credentials.hasCredential(kind) ? "Stored" : "Missing")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(model.credentials.hasCredential(kind) ? StylezamDesign.cobalt : .secondary)
                        }
                    }
                }
            } header: {
                Text("Provider credentials")
            } footer: {
                Text("Values are stored in the device-only Keychain. Stylezam never shows a saved key again; paste a replacement to rotate it.")
            }

            Section {
                NavigationLink {
                    SearchDiagnosticsView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Search Usage & Diagnostics")
                            Text("Request count, outcome, latency, result count, and estimated Fireworks spend")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "waveform.path.ecg")
                            .foregroundStyle(StylezamDesign.cobalt)
                    }
                }
            } header: {
                Text("Observability")
            }

            Section("Runtime") {
                runtimeRow(title: "Garment detection", value: model.modelPack.isInstalled ? "Ready" : "Unavailable")
                runtimeRow(title: "Segmentation crops", value: "On device")
                runtimeRow(title: "Product retrieval", value: searchRuntimeStatus)
                runtimeRow(title: "Virtual try-on", value: "Not built yet")
            }
        }
        .navigationTitle("Developer Debug")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var searchRuntimeStatus: String {
        switch model.settings.productSearchPipeline {
        case .privateAIText:
            model.credentials.hasCredential(.fireworks) && model.credentials.hasCredential(.serper)
                ? "Ready" : "Keys missing"
        case .directImage:
            model.credentials.hasCredential(model.settings.imageSearchProvider.credential)
                ? "Configured" : "Key missing"
        }
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

private struct CredentialEditorView: View {
    @Environment(AppModel.self) private var model
    let kind: SearchCredentialKind

    @State private var replacement = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    Label(
                        model.credentials.hasCredential(kind) ? "Stored" : "Missing",
                        systemImage: model.credentials.hasCredential(kind) ? "checkmark.circle.fill" : "circle"
                    )
                    .foregroundStyle(model.credentials.hasCredential(kind) ? StylezamDesign.cobalt : .secondary)
                }
                SecureField("Paste API key", text: $replacement)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button(model.credentials.hasCredential(kind) ? "Replace key" : "Save key") {
                    do {
                        try model.credentials.setCredential(replacement, for: kind)
                        replacement = ""
                        message = "Saved to this iPhone's Keychain."
                    } catch {
                        message = error.localizedDescription
                    }
                }
                .disabled(replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } footer: {
                Text("The existing value is intentionally unreadable in the UI. Saving replaces it atomically.")
            }

            if model.credentials.hasCredential(kind) {
                Section {
                    Button("Remove key from this iPhone", role: .destructive) {
                        do {
                            try model.credentials.removeCredential(kind)
                            message = "Removed from the Keychain."
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
            }

            if let message {
                Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SearchLimitsDebugView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var settings = model.settings
        Form {
            requestLimit("SearchAPI.io", value: $settings.searchAPIMonthlyLimit)
            requestLimit("SerpApi", value: $settings.serpAPIMonthlyLimit)
            requestLimit("Bright Data", value: $settings.brightDataMonthlyLimit)
            requestLimit("Lykdat", value: $settings.lykdatMonthlyLimit)
            requestLimit("Serper", value: $settings.serperMonthlyLimit)

            Section("Fireworks") {
                HStack {
                    Text("Monthly safety budget")
                    Spacer()
                    TextField("USD", value: $settings.fireworksMonthlyBudgetUSD, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                }
                TextField("Model ID", text: $settings.fireworksModelID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Search locale") {
                TextField("Country code", text: $settings.searchCountry)
                    .textInputAutocapitalization(.never)
                TextField("Language code", text: $settings.searchLanguage)
                    .textInputAutocapitalization(.never)
            }
        }
        .navigationTitle("Safety Limits")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func requestLimit(_ title: String, value: Binding<Int>) -> some View {
        Section(title) {
            HStack {
                Text("Requests per month")
                Spacer()
                TextField("Limit", value: value, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 92)
            }
        }
    }
}

private struct SearchDiagnosticsView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmReset = false

    var body: some View {
        List {
            Section("This month") {
                diagnosticCount("Fireworks", provider: "fireworks")
                diagnosticCount("Serper", provider: "serper")
                diagnosticCount("Lykdat", provider: "lykdat")
                diagnosticCount("SearchAPI.io", provider: "searchapi")
                diagnosticCount("SerpApi", provider: "serpapi")
                diagnosticCount("Bright Data", provider: "brightdata")
                LabeledContent("Estimated Fireworks spend") {
                    Text(model.searchUsage.estimatedFireworksSpend, format: .currency(code: "USD"))
                        .monospacedDigit()
                }
            }

            Section("Latest dispatched calls") {
                if model.searchUsage.snapshot.records.isEmpty {
                    Text("No calls recorded yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(model.searchUsage.snapshot.records.reversed().prefix(40)) { record in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(record.providers.joined(separator: " + "))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(record.status.rawValue.uppercased())
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(record.status == .succeeded ? StylezamDesign.cobalt : record.status == .failed ? .red : .secondary)
                            }
                            HStack(spacing: 7) {
                                Text(record.createdAt.formatted(date: .abbreviated, time: .standard))
                                Text("·")
                                Text("\(record.requestCount) call\(record.requestCount == 1 ? "" : "s")")
                                Text("·")
                                Text("\(record.resultCount) results")
                            }
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            if let latency = record.latencyMilliseconds {
                                Text("Latency \(latency.formatted(.number.precision(.fractionLength(0)))) ms")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            if let diagnostic = record.diagnostic {
                                Text(diagnostic)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                }
            }

            Section {
                Button("Reset local usage ledger", role: .destructive) { confirmReset = true }
            } footer: {
                Text("This resets only Stylezam's local safety ledger. It does not restore provider credits or reset provider billing counters.")
            }
        }
        .navigationTitle("Search Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Reset local usage ledger?", isPresented: $confirmReset) {
            Button("Reset ledger", role: .destructive) { model.searchUsage.resetUsage() }
        }
    }

    private func diagnosticCount(_ title: String, provider: String) -> some View {
        LabeledContent(title) {
            Text(model.searchUsage.requestCount(provider: provider), format: .number)
                .monospacedDigit()
        }
    }
}
