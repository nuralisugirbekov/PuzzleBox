import Foundation

/// Asks for an App Store rating once: the first time a round ends, and never again after that.
enum ReviewPrompt {
    private static let askedKey = "puzzlebox.review.asked"

    static var shouldAsk: Bool { !UserDefaults.standard.bool(forKey: askedKey) }

    static func markAsked() { UserDefaults.standard.set(true, forKey: askedKey) }
}
