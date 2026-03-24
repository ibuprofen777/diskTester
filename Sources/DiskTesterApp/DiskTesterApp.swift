import SwiftUI

@main
struct DiskTesterApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1180, minHeight: 780)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1260, height: 840)
    }
}
