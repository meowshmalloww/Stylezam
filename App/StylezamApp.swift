import GoogleSignIn
import SwiftUI

@main
struct StylezamApp: App {
    private static let currentOnboardingVersion = 4

    @UIApplicationDelegateAdaptor(StylezamAppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var isShowingLaunchExperience = true
    @AppStorage("stylezam.onboarding.version") private var onboardingVersion = 0
    @AppStorage("stylezam.initial-plan.uid") private var confirmedPlanUID = ""

    var body: some Scene {
        WindowGroup {
            ZStack {
                authenticatedContent

                if isShowingLaunchExperience {
                    LaunchExperienceView {
                        withAnimation(.easeOut(duration: 0.24)) {
                            isShowingLaunchExperience = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .task { await model.start() }
            .stylezamControlIntentHandler(model: model)
            .onOpenURL { url in
                _ = GIDSignIn.sharedInstance.handle(url)
                model.handleURL(url)
            }
        }
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        if onboardingVersion < Self.currentOnboardingVersion {
            FirstRunExperienceView {
                withAnimation(.easeInOut(duration: 0.28)) {
                    onboardingVersion = Self.currentOnboardingVersion
                }
            }
            .environment(model)
        } else if model.account.configurationState == .checking {
            ProgressView("Restoring your account")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(StylezamDesign.canvas)
        } else if model.account.account == nil {
            LoginView()
                .environment(model)
        } else if let account = model.account.account,
                  confirmedPlanUID != account.uid
        {
            InitialPlanSelectionView {
                withAnimation(.easeInOut(duration: 0.28)) {
                    confirmedPlanUID = account.uid
                }
            }
            .environment(model)
        } else {
            RootView()
                .environment(model)
        }
    }
}

private extension View {
    @ViewBuilder
    func stylezamControlIntentHandler(model: AppModel) -> some View {
        if #available(iOS 26.0, *) {
            onAppIntentExecution(OpenStylezamIntent.self) { intent in
                model.handleControlDestination(intent.target)
            }
        } else {
            self
        }
    }
}
