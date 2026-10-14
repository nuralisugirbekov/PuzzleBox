import Foundation
import SwiftUI

// MARK: - Resumable games

/// A game engine that can write its round to disk and pick it up again, so a
/// player who leaves mid-game is offered to continue (Figma "Rejoined").
///
/// Turn-based games save their exact board. Real-time games save what can be
/// resumed meaningfully — level, score, lives — and continue from the start of
/// that level.
@MainActor
protocol ResumableGame: AnyObject {
    /// The round's progress, or nil when there is nothing worth resuming
    /// (a fresh board, or a finished game).
    func saveSession() -> Data?
    /// Restores a round written by `saveSession()`. Returns false, leaving the
    /// engine untouched, when the data can't be used (e.g. an older format).
    func restoreSession(_ data: Data) -> Bool
}

extension ResumableGame {
    func encodeSession<Snapshot: Encodable>(_ snapshot: Snapshot) -> Data? {
        try? JSONEncoder().encode(snapshot)
    }

    func decodeSession<Snapshot: Decodable>(_ type: Snapshot.Type, from data: Data) -> Snapshot? {
        try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Store

/// One saved round per game, as a JSON file in Application Support.
enum GameSessionStore {
    /// Bump when a change makes every saved round unreadable.
    private static let formatVersion = 1

    struct Session: Codable {
        let version: Int
        let savedAt: Date
        /// Active play time for games with a round clock (the card games).
        let elapsed: TimeInterval
        let payload: Data
    }

    private static var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let url = base.appendingPathComponent("GameSessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func fileURL(for id: GameID) -> URL? {
        directory?.appendingPathComponent("\(id.rawValue).json")
    }

    static func save(_ payload: Data, for id: GameID, elapsed: TimeInterval = 0) {
        guard let url = fileURL(for: id) else { return }
        let session = Session(version: formatVersion, savedAt: Date(), elapsed: elapsed, payload: payload)
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load(_ id: GameID) -> Session? {
        guard let url = fileURL(for: id), let data = try? Data(contentsOf: url) else { return nil }
        guard let session = try? JSONDecoder().decode(Session.self, from: data),
              session.version == formatVersion else {
            delete(id)
            return nil
        }
        return session
    }

    static func delete(_ id: GameID) {
        guard let url = fileURL(for: id) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func hasSession(_ id: GameID) -> Bool {
        guard let url = fileURL(for: id) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

// MARK: - One offer per opening

/// Games opened from the catalog may offer to continue a saved round once.
/// Containers rebuilt inside the same session (a new level) must not ask again,
/// but keep showing the offer while it is still unanswered.
@MainActor
@Observable
final class ResumeOffer {
    @ObservationIgnored private var pending: Set<GameID> = []
    /// Games whose restored round is waiting for Continue / Start over.
    private(set) var awaiting: Set<GameID> = []

    func open(_ id: GameID) { pending.insert(id) }

    /// True the first time it is asked for `id` after `open(_:)`.
    func claim(_ id: GameID) -> Bool { pending.remove(id) != nil }

    func markAwaiting(_ id: GameID) { awaiting.insert(id) }
    func answer(_ id: GameID) { awaiting.remove(id) }
}

extension EnvironmentValues {
    @Entry var resumeOffer = ResumeOffer()
}
