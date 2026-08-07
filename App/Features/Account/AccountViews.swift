import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            StylezamDesign.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 36)
                BrandMarkView(size: 70)
                    .shadow(color: StylezamDesign.cobalt.opacity(0.18), radius: 24, y: 12)
                Text("Welcome to Stylezam")
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-1)
                    .padding(.top, 22)
                Text("Your captures and profile choices stay on this iPhone. Google securely identifies your account.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 9)
                    .padding(.horizontal, 30)

                LoginPanel()
                    .padding(.top, 34)

                Spacer()
                Text("By continuing, you agree to use Stylezam responsibly. Product matches and prices should be verified with the merchant.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 34)
                    .padding(.bottom, 20)
            }
        }
    }
}

struct LoginPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            switch model.account.configurationState {
            case .checking:
                ProgressView("Preparing secure sign in")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            case .ready:
                Button {
                    Task { await model.account.signInWithGoogle() }
                } label: {
                    HStack(spacing: 12) {
                        Text("G")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(StylezamDesign.cobalt)
                            .frame(width: 30, height: 30)
                            .background(.white, in: Circle())
                        Text(model.account.isWorking ? "Connecting securely…" : "Continue with Google")
                            .font(.headline)
                        Spacer()
                        if model.account.isWorking {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.right")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                    .padding(.horizontal, 17)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                }
                .stylezamGlassButton(prominent: true)
                .tint(StylezamDesign.cobalt)
                .disabled(model.account.isWorking)
            case .missingPlist, .invalidPlist:
                FirebaseSetupCard(state: model.account.configurationState)
            }

            if let error = model.account.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, StylezamDesign.pageInset)
    }
}

private struct FirebaseSetupCard: View {
    let state: FirebaseConfigurationState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Firebase setup required", systemImage: "wrench.and.screwdriver")
                .font(.headline)
            Text(state.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 7) {
                setupLine("1", "Register com.stylezam.app in Firebase")
                setupLine("2", "Enable Google in Authentication")
                setupLine("3", "Add the downloaded plist and URL scheme")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(StylezamDesign.hairline, lineWidth: 1)
        }
    }

    private func setupLine(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(StylezamDesign.cobalt)
                .frame(width: 18)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @State private var isEditingProfile = false
    @State private var confirmSignOut = false
    @State private var confirmDelete = false

    var body: some View {
        List {
            if let account = model.account.account {
                Section {
                    AccountIdentityHeader(account: account)
                        .listRowInsets(EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18))
                }

                Section {
                    Button("Edit profile") { isEditingProfile = true }
                    NavigationLink {
                        SubscriptionPlansView()
                    } label: {
                        LabeledContent("Plan", value: model.activePlan.title)
                    }
                    Button("Refresh account access") {
                        Task { await model.account.refreshDeveloperAccess() }
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Profile edits are stored only on this iPhone. Your Google identity is managed by Firebase Authentication.")
                }

                Section {
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                    Button("Delete account and local library", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isEditingProfile) {
            ProfileEditorView()
                .environment(model)
        }
        .confirmationDialog("Sign out of Stylezam?", isPresented: $confirmSignOut) {
            Button("Sign out", role: .destructive) { model.account.signOut() }
        }
        .confirmationDialog(
            "Permanently delete this Stylezam account?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete account and library", role: .destructive) {
                Task {
                    _ = await model.deleteAccountAndLibrary()
                }
            }
        } message: {
            Text("This deletes the Firebase Authentication user plus every local capture, crop, search, saved product, person photo, and profile on this iPhone. It cannot be undone.")
        }
    }
}

struct InitialPlanSelectionView: View {
    let completion: () -> Void

    @Environment(AppModel.self) private var model
    @State private var billingPeriod: SubscriptionBillingPeriod = .annual

    private var currentPlan: AccountPlan {
        model.activePlan
    }

    private var previewPlans: [AccountPlan] {
        currentPlan == .developer ? [.developer, .free, .plus, .pro] : [.free, .plus, .pro]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 10) {
                    BrandMarkView(size: 38)
                    StylezamWordmark()
                }

                VStack(alignment: .leading, spacing: 8) {
                    EditorialKicker(text: "YOUR MEMBERSHIP")
                    Text("Choose your plan.")
                        .font(.system(size: 40, weight: .semibold))
                        .tracking(-1.3)
                    Text("Choose monthly flexibility or annual value. Your captures, Library, and try-on photos stay on this iPhone.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                BillingPeriodPicker(selection: $billingPeriod)

                ForEach(previewPlans) { plan in
                    PlanCard(
                        plan: plan,
                        period: billingPeriod,
                        price: model.subscriptions.price(for: plan, period: billingPeriod),
                        annualSavings: model.subscriptions.annualSavings(for: plan),
                        active: plan == currentPlan,
                        productAvailable: model.subscriptions.product(
                            for: plan,
                            period: billingPeriod
                        ) != nil,
                        isPurchasing: model.subscriptions.isPurchasing,
                        onChoose: plan == .plus || plan == .pro ? {
                            Task {
                                if await model.purchaseSubscription(
                                    plan: plan,
                                    period: billingPeriod
                                ) { completion() }
                            }
                        } : nil
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                if let message = model.subscriptions.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Search results, prices, and provider availability can change. Confirm important details with the merchant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(StylezamDesign.pageInset)
            .padding(.bottom, 104)
            .animation(.easeInOut(duration: 0.24), value: billingPeriod)
        }
        .background(StylezamDesign.canvas)
        .safeAreaInset(edge: .bottom) {
            Button(action: completion) {
                HStack {
                    Text("Continue with \(currentPlan.title)")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
            }
            .stylezamGlassButton(prominent: true)
            .tint(StylezamDesign.cobalt)
            .padding(.horizontal, StylezamDesign.pageInset)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
    }
}

struct AccountIdentityHeader: View {
    @Environment(AppModel.self) private var model
    let account: StylezamAccount

    var body: some View {
        HStack(spacing: 16) {
            AccountAvatar(account: account, size: 62)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(account.visibleName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    Text(account.roleLabel)
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.7)
                        .foregroundStyle(account.isDeveloper ? .white : StylezamDesign.cobalt)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(account.isDeveloper ? StylezamDesign.cobalt : StylezamDesign.cobalt.opacity(0.1), in: Capsule())
                }
                Text(account.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(model.activePlan.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(StylezamDesign.cobalt)
            }
        }
    }
}

struct AccountAvatar: View {
    let account: StylezamAccount
    var size: CGFloat

    var body: some View {
        AsyncImage(url: account.photoURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Text(account.initials)
                .font(.system(size: size * 0.28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(StylezamDesign.cobalt)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().stroke(StylezamDesign.hairline, lineWidth: 1) }
    }
}

private struct ProfileEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var profile = LocalUserProfile.initial(displayName: "")

    var body: some View {
        NavigationStack {
            Form {
                Section("Public in Stylezam") {
                    TextField("Display name", text: $profile.displayName)
                    TextField("Username", text: $profile.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Your style in a sentence", text: $profile.styleNote, axis: .vertical)
                        .lineLimit(3...5)
                }
                Section {
                    Text("These fields stay on this iPhone and are not uploaded to Firebase or Firestore.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.account.updateProfile(profile)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let existing = model.account.account?.profile { profile = existing }
            }
        }
    }
}

struct SubscriptionPlansView: View {
    @Environment(AppModel.self) private var model
    @State private var billingPeriod: SubscriptionBillingPeriod = .annual

    private var visiblePlans: [AccountPlan] {
        model.account.isDeveloper ? [.developer, .free, .plus, .pro] : [.free, .plus, .pro]
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    EditorialKicker(text: "Membership")
                    Text("Choose your pace.")
                        .font(.system(size: 34, weight: .semibold))
                        .tracking(-1)
                    Text("Choose monthly flexibility or save with annual billing. Prices and purchases come directly from the App Store.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)

                BillingPeriodPicker(selection: $billingPeriod)

                ForEach(visiblePlans) { plan in
                    PlanCard(
                        plan: plan,
                        period: billingPeriod,
                        price: model.subscriptions.price(for: plan, period: billingPeriod),
                        annualSavings: model.subscriptions.annualSavings(for: plan),
                        active: model.activePlan == plan,
                        productAvailable: model.subscriptions.product(
                            for: plan,
                            period: billingPeriod
                        ) != nil,
                        isPurchasing: model.subscriptions.isPurchasing,
                        onChoose: plan == .plus || plan == .pro ? {
                            Task {
                                _ = await model.purchaseSubscription(
                                    plan: plan,
                                    period: billingPeriod
                                )
                            }
                        } : nil
                    )
                }

                Button("Restore purchases") {
                    Task { await model.restoreSubscriptions() }
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)

                if let message = model.subscriptions.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text("Subscription limits apply to product searches and Stylezam AI questions. Shopping providers and merchant availability can still change.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(StylezamDesign.pageInset)
            .padding(.bottom, 30)
            .animation(.easeInOut(duration: 0.24), value: billingPeriod)
        }
        .background(StylezamDesign.canvas)
        .navigationTitle("Plans")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PlanCard: View {
    let plan: AccountPlan
    let period: SubscriptionBillingPeriod
    let price: String
    let annualSavings: Int?
    let active: Bool
    let productAvailable: Bool
    let isPurchasing: Bool
    let onChoose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title)
                        .font(.title2.weight(.semibold))
                    Text(plan.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(price)
                        .font(.title3.weight(.semibold))
                        .contentTransition(.numericText())
                    if plan == .plus || plan == .pro {
                        Text(period == .monthly ? "per month" : "per year")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            EditorialRule()
            planLine("magnifyingglass", plan.productSearchAllowance)
            planLine("sparkles", plan.assistantAllowance)
            planLine("iphone", "On device garment detection")

            HStack(spacing: 9) {
                Text(active ? "CURRENT PLAN" : plan == .free ? "ALWAYS AVAILABLE" : productAvailable ? "APP STORE" : "NOT CONFIGURED")
                    .font(.caption2.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(active ? .white : .secondary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(active ? StylezamDesign.cobalt : Color(uiColor: .tertiarySystemFill), in: Capsule())

                if period == .annual, let annualSavings, annualSavings > 0,
                   plan == .plus || plan == .pro
                {
                    Text("SAVE \(annualSavings)%")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(StylezamDesign.cobalt)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(StylezamDesign.cobalt.opacity(0.1), in: Capsule())
                }
                Spacer()
            }

            if !active, let onChoose, plan == .plus || plan == .pro {
                Button(action: onChoose) {
                    HStack {
                        Text(productAvailable ? "Choose \(plan.title)" : "Unavailable from App Store")
                        Spacer()
                        if isPurchasing {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.right")
                        }
                    }
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .frame(height: 50)
                }
                .stylezamGlassButton(prominent: true)
                .tint(StylezamDesign.cobalt)
                .disabled(!productAvailable || isPurchasing)
            }
        }
        .padding(19)
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(active ? StylezamDesign.cobalt : StylezamDesign.hairline, lineWidth: active ? 1.5 : 1)
        }
    }

    private func planLine(_ icon: String, _ title: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(.primary)
    }
}

private struct BillingPeriodPicker: View {
    @Binding var selection: SubscriptionBillingPeriod

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SubscriptionBillingPeriod.allCases) { period in
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                        selection = period
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(period.title)
                            .font(.subheadline.weight(.semibold))
                        if period == .annual {
                            Text("BEST VALUE")
                                .font(.system(size: 8, weight: .bold))
                                .tracking(0.6)
                                .foregroundStyle(selection == period ? .white.opacity(0.78) : StylezamDesign.cobalt)
                        }
                    }
                    .foregroundStyle(selection == period ? .white : .primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(selection == period ? StylezamDesign.cobalt : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
        .overlay { Capsule().stroke(StylezamDesign.hairline, lineWidth: 0.75) }
    }
}
