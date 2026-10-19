import SwiftUI
import UIKit
import FirebaseCore

@main
struct PuzzleBoxAppApp: App {
    @UIApplicationDelegateAdaptor(FirebaseAppDelegate.self) private var appDelegate
    @State private var stats = StatsStore()
    @State private var friends = FriendsStore()
    @State private var nearby = NearbyStore()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(stats)
                .environment(friends)
                .environment(nearby)
        }
    }
}

/// Configure Firebase before the first SwiftUI screen sends any events.
final class FirebaseAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        AppAnalytics.updateLanguageProperty()
        return true
    }
}
