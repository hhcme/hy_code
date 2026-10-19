import SwiftUI

@main
struct HcFileViewerApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }
        .defaultSize(width: 720, height: 480)
    }
}
