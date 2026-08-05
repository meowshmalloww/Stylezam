import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastContentTab: AppTab = .home

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            NavigationStack {
                HomeView()
            }
            .tag(AppTab.home)
            .tabItem { Label("Home", systemImage: "house") }

            NavigationStack {
                SearchView()
            }
            .tag(AppTab.search)
            .tabItem { Label("Search", systemImage: "magnifyingglass") }

            Color.clear
                .tag(AppTab.camera)
                .tabItem { Label("Camera", systemImage: "camera.fill") }

            NavigationStack {
                LibraryView()
            }
            .tag(AppTab.library)
            .tabItem { Label("Library", systemImage: "square.stack") }

            NavigationStack {
                SettingsView()
            }
            .tag(AppTab.settings)
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(StylezamDesign.cobalt)
        .stylezamTabBarBehavior()
        .sensoryFeedback(.selection, trigger: model.selectedTab)
        .fullScreenCover(isPresented: $model.isCapturePresented) {
            CaptureSheet()
                .environment(model)
        }
        .fullScreenCover(isPresented: $model.isTryOnPresented) {
            NavigationStack {
                TryOnView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") { model.isTryOnPresented = false }
                        }
                    }
            }
            .environment(model)
        }
        .alert(
            "Live Screen",
            isPresented: Binding(
                get: { model.liveScreenNotice != nil },
                set: { if !$0 { model.liveScreenNotice = nil } }
            )
        ) {
            Button("OK") { model.liveScreenNotice = nil }
        } message: {
            Text(model.liveScreenNotice ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .stylezamOpenScan)) { note in
            model.handlePendingScanNotification(scanID: note.object as? String)
        }
        .onReceive(NotificationCenter.default.publisher(for: StylezamShared.externalRequestNotification)) { _ in
            model.handleExternalCaptureRequest()
        }
        .onAppear {
            model.handleExternalCaptureRequest()
        }
        .onChange(of: model.selectedTab) { oldValue, newValue in
            if newValue == .camera {
                model.selectedTab = oldValue == .camera ? lastContentTab : oldValue
                model.presentCamera()
            } else {
                lastContentTab = newValue
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.handleExternalCaptureRequest()
                model.activatePendingLiveScreenPicker()
            }
        }
    }
}
