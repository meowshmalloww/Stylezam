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
                        LabeledContent("Plan", value: account.plan.title)
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
                    if await model.account.deleteAccount() { model.clearLibrary() }
                }
            }
        } message: {
            Text("This deletes the Firebase Authentication user plus captures, crops, searches, saved products, and local profile data on this iPhone. It cannot be undone.")
        }
    }
}

struct InitialPlanSelectionView: View {
    let completion: () -> Void

    @Environment(AppModel.self) private var model

    private var currentPlan: AccountPlan {
        model.account.account?.plan ?? .free
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
                    Text("Start with the available plan today. Plus and Pro remain visible so their intended limits are clear, but they cannot be purchased yet.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(previewPlans) { plan in
                    PlanCard(plan: plan, active: plan == currentPlan)
                        .opacity(plan.isAvailable ? 1 : 0.66)
                }

                Text("Search results, prices, and provider availability can change. Confirm important details with the merchant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(StylezamDesign.pageInset)
            .padding(.bottom, 104)
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
                Text(account.plan == .developer ? "Unlimited internal access" : "Free plan")
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
                    Text("Free is active today. Paid plans are pricing previews until StoreKit subscriptions are implemented and tested.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)

                ForEach(visiblePlans) { plan in
                    PlanCard(plan: plan, active: model.account.account?.plan == plan)
                }

                Text("Allowances are product targets, not a promise of unlimited provider availability. Store pricing, taxes, and final limits may change before launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(StylezamDesign.pageInset)
            .padding(.bottom, 30)
        }
        .background(StylezamDesign.canvas)
        .navigationTitle("Plans")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PlanCard: View {
    let plan: AccountPlan
    let active: Bool

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
                    Text(plan.monthlyPrice)
                        .font(.title3.weight(.semibold))
                    if plan == .plus || plan == .pro {
                        Text("per month")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            EditorialRule()
            planLine("magnifyingglass", plan.productSearchAllowance)
            planLine("sparkles", plan.assistantAllowance)
            planLine("iphone", "On device garment detection")

            Text(active ? "CURRENT PLAN" : plan.isAvailable ? "AVAILABLE" : "COMING SOON")
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(active ? .white : .secondary)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(active ? StylezamDesign.cobalt : Color(uiColor: .tertiarySystemFill), in: Capsule())
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
