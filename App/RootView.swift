import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            NavigationStack {
                HomeView()
            }
            .tag(AppTab.home)
            .tabItem { Label("Discover", systemImage: "house") }

            NavigationStack {
                SearchView()
            }
            .tag(AppTab.search)
            .tabItem { Label("Search", systemImage: "magnifyingglass") }

            NavigationStack {
                LibraryView()
            }
            .tag(AppTab.looks)
            .tabItem { Label("Saved", systemImage: "bookmark") }

            NavigationStack {
                SettingsView()
            }
            .tag(AppTab.you)
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(StylezamDesign.cobalt)
        .tabBarMinimizeBehavior(.onScrollDown)
        .sensoryFeedback(.selection, trigger: model.selectedTab)
        .sheet(isPresented: $model.isCapturePresented) {
            CaptureSheet()
                .environment(model)
        }
        .onOpenURL { model.handleURL($0) }
        .onReceive(NotificationCenter.default.publisher(for: .stylezamOpenSearch)) { note in
            model.handlePendingNotification(searchID: note.object as? String)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.handleExternalCaptureRequest()
            }
        }
    }
}
