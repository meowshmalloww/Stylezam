import SwiftUI

@main
struct StylezamApp: App {
    @UIApplicationDelegateAdaptor(StylezamAppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var isShowingLaunchExperience = true
    @State private var isShowingModelSetup = false
    @AppStorage("stylezam.did-offer-model-pack") private var didOfferModelPack = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView()
                    .environment(model)

                if isShowingLaunchExperience {
                    LaunchExperienceView {
                        withAnimation(.easeOut(duration: 0.24)) {
                            isShowingLaunchExperience = false
                        }
                        if !didOfferModelPack, !model.modelPack.isInstalled {
                            didOfferModelPack = true
                            isShowingModelSetup = true
                        }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
            .task { await model.start() }
            .sheet(isPresented: $isShowingModelSetup) {
                ModelPackSetupView()
                    .environment(model)
            }
        }
    }
}
