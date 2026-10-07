import Foundation
import Observation

/// Local player statistics, persisted to UserDefaults.
@Observable
final class StatsStore {
    private static let highScoresKey = "puzzlebox.highScores"
    private static let playedKey = "puzzlebox.gamesPlayed"

    private var highScores: [String: Int]
    private var played: [String: Int]

    init() {
        let defaults = UserDefaults.standard
        highScores = defaults.dictionary(forKey: Self.highScoresKey) as? [String: Int] ?? [:]
        played = defaults.dictionary(forKey: Self.playedKey) as? [String: Int] ?? [:]
    }

    func highScore(for id: GameID) -> Int { highScores[id.rawValue] ?? 0 }
    func gamesPlayed(for id: GameID) -> Int { played[id.rawValue] ?? 0 }

    var totalPlayed: Int {
        GameID.allCases.reduce(0) { $0 + gamesPlayed(for: $1) }
    }

    /// Records a finished round. Returns true when `score` set a new high score.
    @discardableResult
    func record(_ id: GameID, score: Int) -> Bool {
        played[id.rawValue] = gamesPlayed(for: id) + 1
        var isNewHigh = false
        if score > highScore(for: id) {
            highScores[id.rawValue] = score
            isNewHigh = true
        }
        persist()
        return isNewHigh
    }

    private func persist() {
        let defaults = UserDefaults.standard
        defaults.set(highScores, forKey: Self.highScoresKey)
        defaults.set(played, forKey: Self.playedKey)
    }
}
