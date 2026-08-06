import AppIntents
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

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
                            detail: "Verified role · vision, provider readiness, quotas, and request logs"
                        )
                    }

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
                Text("Add both Stylezam controls from Control Center’s edit gallery. Capture a Look opens the camera. Live Screen opens Apple’s required picker; after you choose Share Entire Screen, return to the fashion content and Stylezam scans it automatically.")
                    .foregroundStyle(.secondary)
                setupStep("1", "Open Control Center and tap +")
                setupStep("2", "Choose Add a Control")
                setupStep("3", "Add Capture a Look and Live Screen")
            }

            Section {
                Text("This route passes the actual screenshot into Stylezam for garment detection and works on iOS 18 through iOS 27.")
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
                Text("Capture a Look opens Stylezam’s front/back camera. Live Screen is separate because iOS requires explicit system consent. Stylezam cannot dismiss itself back to the previous app, but the authorized stream and automatic detector continue while Stylezam is in the background.")
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

                LabeledContent("Device", value: ScreenCaptureAvailability.deviceSummary)
                LabeledContent("Installed build", value: ScreenCaptureAvailability.buildSummary)
                if model.liveScreen.automaticallySavedPieceCount > 0 {
                    LabeledContent(
                        "Auto-saved this run",
                        value: "\(model.liveScreen.automaticallySavedPieceCount) pieces"
                    )
                }

                if let recovery = ScreenCaptureAvailability.recoverySummary {
                    Text(recovery)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Link(
                        "Apple’s iOS screen-capture requirements",
                        destination: URL(string: "https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-on-ios")!
                    )
                    .font(.subheadline)
                }

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
                    Text(ScreenCaptureAvailability.badge)
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
                title: "Only when you create a try-on",
                icon: "wand.and.sparkles",
                detail: "After you allow the upload, Stylezam sends the selected person photo and product image to YouCam, downloads the generated preview, and requests remote task deletion."
            )
            privacySection(
                title: "Service credentials",
                icon: "key",
                detail: "Search keys are developer-managed. This private build imports them from an ignored environment file into the device-only Keychain. A YouCam key can also be saved directly to this iPhone for prototype testing; credentials are never written to Library media or JSON."
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

                NavigationLink {
                    LiveScreenDebugView()
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Live Screen Inspector")
                            Text("See the latest authorized frame, boxes, crops, and pipeline state")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "rectangle.dashed.badge.record")
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

                Toggle(
                    "Automatic capture in Live camera",
                    isOn: $settings.liveAutoCaptureEnabled
                )
                    .tint(StylezamDesign.cobalt)

                Toggle(
                    "Automatic capture in Live Screen",
                    isOn: $settings.liveScreenAutoCaptureEnabled
                )
                    .tint(StylezamDesign.cobalt)

                Toggle(
                    "Retain Live Screen detection boxes",
                    isOn: Binding(
                        get: { settings.liveScreenBoundingBoxDebugEnabled },
                        set: { model.setLiveScreenDebugArtifactsEnabled($0) }
                    )
                )
                    .tint(StylezamDesign.cobalt)
            } header: {
                Text("Capture behavior")
            } footer: {
                Text("Five is the safe default. Live Screen saves after two agreeing observations. The debug toggle retains only the latest authorized frame and its real model boxes in memory; it never draws over another app. Increasing the item limit uses more memory and can make local crop generation slower.")
            }

            Section {
                Picker("Preferred provider", selection: $settings.imageSearchProvider) {
                    ForEach(ImageSearchProvider.allCases) { provider in
                        Text(provider.title).tag(provider)
                    }
                }
                LabeledContent(
                    "Routing",
                    value: model.eligibleImageSearchProviders.contains(settings.imageSearchProvider)
                        ? "Pinned to preference"
                        : "Eligible fallback"
                )
                LabeledContent("Eligible providers") {
                    Text(model.eligibleImageSearchProviders.count, format: .number)
                        .monospacedDigit()
                }
                LabeledContent(
                    "Active provider",
                    value: model.activeImageSearchProvider?.title ?? "None ready"
                )

                Stepper(
                    "Successful searches per piece: \(settings.productSearchesPerPiece)",
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
                Text("One tap makes one request to the preferred eligible provider and can return several products. If that provider requires a public image URL or is not configured, Stylezam uses an eligible fallback. Fireworks remains exclusive to Stylezam AI and AI-guided refinements.")
            }

            Section {
                readinessRow(
                    title: "YouCam",
                    detail: "Photo virtual try-on",
                    status: YouCamCredentialStore.isConfigured ? "Configured" : "Not configured",
                    isReady: YouCamCredentialStore.isConfigured
                )
                providerReadinessRow(kind: .fireworks, detail: "Stylezam AI")
                providerReadinessRow(kind: .serper, detail: "AI-guided shopping")
                ForEach(ImageSearchProvider.allCases) { provider in
                    imageProviderReadinessRow(provider)
                }
            } header: {
                Text("Provider readiness")
            } footer: {
                Text("Provider credentials remain read-only. This private build imports them from the ignored .env launch environment into this iPhone's Keychain. Try On also exposes a local YouCam connection field when its credential is missing.")
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
                runtimeRow(
                    title: "Virtual try-on",
                    value: YouCamCredentialStore.isConfigured ? "YouCam configured" : "Needs YouCam key"
                )
            }
        }
        .navigationTitle("Developer Debug")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var searchRuntimeStatus: String {
        let count = model.eligibleImageSearchProviders.count
        return count > 0 ? "\(count) route\(count == 1 ? "" : "s") ready" : "No route ready"
    }

    private func providerReadinessRow(kind: SearchCredentialKind, detail: String) -> some View {
        readinessRow(
            title: kind.title,
            detail: detail,
            status: model.credentials.hasCredential(kind) ? "Ready" : "Not configured",
            isReady: model.credentials.hasCredential(kind)
        )
    }

    private func imageProviderReadinessRow(_ provider: ImageSearchProvider) -> some View {
        let hasKey = model.credentials.hasCredential(provider.credential)
        let isEligible = model.eligibleImageSearchProviders.contains(provider)
        let status: String
        if !hasKey {
            status = "Not configured"
        } else if provider == .brightData,
                  model.settings.brightDataZone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            status = "Needs SERP zone"
        } else if !provider.acceptsPrivateImageData && !isEligible {
            status = "Needs crop hosting"
        } else {
            status = "Ready"
        }
        return readinessRow(
            title: provider.title,
            detail: provider.acceptsPrivateImageData ? "Private crop upload" : "Public HTTPS crop required",
            status: status,
            isReady: isEligible
        )
    }

    private func readinessRow(
        title: String,
        detail: String,
        status: String,
        isReady: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isReady ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(isReady ? StylezamDesign.cobalt : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(status)
                .font(.caption.weight(.medium))
                .foregroundStyle(isReady ? StylezamDesign.cobalt : .secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func runtimeRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(
                    value == "Ready" || value == "On device" || value.contains("route")
                        ? StylezamDesign.cobalt
                        : .secondary
                )
        }
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
            Section {
                HStack {
                    Text("Web Detection units per month")
                    Spacer()
                    TextField("Limit", value: $settings.googleVisionMonthlyLimit, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 92)
                }
            } header: {
                Text("Google Cloud Vision")
            } footer: {
                Text("Hard-stopped at 1,000. Stylezam sends one image with only one WEB_DETECTION feature, so each dispatched search reserves one unit. This limit can be lowered but not raised.")
            }
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
                diagnosticCount("Google Vision", provider: "googlevision")
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
                Button("Clear local diagnostics", role: .destructive) { confirmReset = true }
            } footer: {
                Text("This clears local request diagnostics and normal feature counters. The separate Google Vision hard-stop counter is intentionally preserved, because clearing app history cannot restore Google units or billing allowances.")
            }
        }
        .navigationTitle("Search Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Clear local diagnostics?", isPresented: $confirmReset) {
            Button("Clear diagnostics", role: .destructive) { model.searchUsage.resetUsage() }
        }
    }

    private func diagnosticCount(_ title: String, provider: String) -> some View {
        LabeledContent(title) {
            Text(model.searchUsage.requestCount(provider: provider), format: .number)
                .monospacedDigit()
        }
    }
}
