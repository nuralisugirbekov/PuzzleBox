import SwiftUI

@main
struct PuzzleBoxAppApp: App {
    @State private var stats = StatsStore()

    var body: some Scene {
        WindowGroup {
            MainMenuView()
                .environment(stats)
        }
    }
}
