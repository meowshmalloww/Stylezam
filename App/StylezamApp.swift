import GoogleSignIn
import SwiftUI

@main
struct StylezamApp: App {
    @UIApplicationDelegateAdaptor(StylezamAppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var isShowingLaunchExperience = true
    @AppStorage("stylezam.onboarding.completed") private var onboardingCompleted = false

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
            .onOpenURL { url in
                _ = GIDSignIn.sharedInstance.handle(url)
            }
        }
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        if !onboardingCompleted {
            FirstRunExperienceView {
                withAnimation(.easeInOut(duration: 0.28)) {
                    onboardingCompleted = true
                }
            }
            .environment(model)
        } else if model.account.configurationState == .checking {
            ProgressView("Restoring your account")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(StylezamDesign.canvas)
        } else {
            RootView()
                .environment(model)
        }
    }
}
