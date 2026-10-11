import Foundation
import Observation

/// Local player statistics, persisted to UserDefaults.
@Observable
final class StatsStore {
    private static let highScoresKey = "puzzlebox.highScores"
    private static let playedKey = "puzzlebox.gamesPlayed"
    private static let favoritesKey = "puzzlebox.favorites"
    private static let lastOpenedKey = "puzzlebox.lastOpened"

    private var highScores: [String: Int]
    private var played: [String: Int]
    private var favorites: Set<String>
    private var lastOpened: [String: Double]

    init() {
        let defaults = UserDefaults.standard
        highScores = defaults.dictionary(forKey: Self.highScoresKey) as? [String: Int] ?? [:]
        played = defaults.dictionary(forKey: Self.playedKey) as? [String: Int] ?? [:]
        favorites = Set(defaults.stringArray(forKey: Self.favoritesKey) ?? [])
        lastOpened = defaults.dictionary(forKey: Self.lastOpenedKey) as? [String: Double] ?? [:]

        let installed = Set(GameID.allCases.map(\.rawValue))
        highScores = highScores.filter { installed.contains($0.key) }
        played = played.filter { installed.contains($0.key) }
        favorites.formIntersection(installed)
        lastOpened = lastOpened.filter { installed.contains($0.key) }
        persist()
        // Remove tutorial flags and the daily pick left behind by deleted games.
        let tutorialPrefix = "gameTutorial.v1."
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(tutorialPrefix) {
            if !installed.contains(String(key.dropFirst(tutorialPrefix.count))) {
                defaults.removeObject(forKey: key)
            }
        }
        if let daily = defaults.string(forKey: "dailyGame.id"), !installed.contains(daily) {
            defaults.removeObject(forKey: "dailyGame.id")
            defaults.removeObject(forKey: "dailyGame.date")
        }
    }

    func highScore(for id: GameID) -> Int { highScores[id.rawValue] ?? 0 }
    func gamesPlayed(for id: GameID) -> Int { played[id.rawValue] ?? 0 }

    var totalPlayed: Int {
        GameID.allCases.reduce(0) { $0 + gamesPlayed(for: $1) }
    }

    // MARK: Favorites

    func isFavorite(_ id: GameID) -> Bool { favorites.contains(id.rawValue) }

    var favoriteGames: [GameID] { GameID.allCases.filter(isFavorite) }

    func toggleFavorite(_ id: GameID) {
        if favorites.remove(id.rawValue) == nil {
            favorites.insert(id.rawValue)
        }
        persist()
    }

    // MARK: Recently opened

    /// Games the player has opened, most recent first.
    var recentGames: [GameID] {
        GameID.allCases
            .filter { lastOpened[$0.rawValue] != nil }
            .sorted { lastOpened[$0.rawValue, default: 0] > lastOpened[$1.rawValue, default: 0] }
    }

    func markOpened(_ id: GameID) {
        lastOpened[id.rawValue] = Date().timeIntervalSince1970
        persist()
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
        defaults.set(Array(favorites).sorted(), forKey: Self.favoritesKey)
        defaults.set(lastOpened, forKey: Self.lastOpenedKey)
    }
}
