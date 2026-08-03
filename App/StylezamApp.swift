import SwiftUI

@main
struct StylezamApp: App {
    @UIApplicationDelegateAdaptor(StylezamAppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.start() }
        }
    }
}
