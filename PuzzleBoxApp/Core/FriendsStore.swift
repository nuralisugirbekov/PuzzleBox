import Foundation
import Observation
import OSLog
import FirebaseAuth
import FirebaseFirestore

// Friends, presence and game invites, backed by Firestore with anonymous
// Firebase Auth. Layout (see firestore.rules and docs/friends.md):
//
//   users/{uid}                  name, code, online, lastSeen
//   users/{uid}/friends/{uid}    since            (written on both sides)
//   rooms/{id}                   game, session, host, code, players, names, maxPlayers, invited, status,
//                                matchID, matchPlayers
//   invites/{id}                 from, fromName, to, game, roomID, status, createdAt
//   matches/{id}                 game, players, names, state, version, forfeit

/// What a player lets others see. Hidden things are not just hidden in the
/// app: they are never written to the shared profile.
struct ProfilePrivacy: Equatable {
    var showOnline = true
    var showLastSeen = true
    var showStats = true
    /// Off by default: who your friends are is more personal than the rest.
    var showFriends = false
    var allowInvites = true

    init() {}

    init(data: [String: Any]?) {
        let data = data ?? [:]
        showOnline = data["showOnline"] as? Bool ?? true
        showLastSeen = data["showLastSeen"] as? Bool ?? true
        showStats = data["showStats"] as? Bool ?? true
        showFriends = data["showFriends"] as? Bool ?? false
        allowInvites = data["allowInvites"] as? Bool ?? true
    }

    var data: [String: Bool] {
        ["showOnline": showOnline, "showLastSeen": showLastSeen, "showStats": showStats,
         "showFriends": showFriends, "allowInvites": allowInvites]
    }
}

/// The game stats a player shares on their profile.
struct PublicStats: Equatable {
    var played = 0
    var tried = 0
    var favorites = 0
    /// Most played games, most first.
    var top: [GameID] = []

    init(played: Int, tried: Int, favorites: Int, top: [GameID]) {
        self.played = played
        self.tried = tried
        self.favorites = favorites
        self.top = top
    }

    init?(data: [String: Any]?) {
        guard let data else { return nil }
        played = data["played"] as? Int ?? 0
        tried = data["tried"] as? Int ?? 0
        favorites = data["favorites"] as? Int ?? 0
        top = (data["top"] as? [String] ?? []).compactMap(GameID.init(rawValue:))
    }

    @MainActor
    init(stats: StatsStore) {
        let played = GameID.allCases.filter { stats.gamesPlayed(for: $0) > 0 }
        self.init(played: stats.totalPlayed, tried: played.count, favorites: stats.favoriteGames.count,
                  top: Array(played.sorted { stats.gamesPlayed(for: $0) > stats.gamesPlayed(for: $1) }.prefix(3)))
    }

    var data: [String: Any] {
        ["played": played, "tried": tried, "favorites": favorites, "top": top.map(\.rawValue)]
    }
}

struct FriendProfile: Identifiable, Equatable {
    let id: String
    var name: String
    var code: String
    var online: Bool
    var lastSeen: Date?
    /// A short line about the player.
    var bio: String
    /// The avatar: an emoji on one of `FriendAvatar.palette`'s colours. Nil shows the initial.
    var emoji: String?
    var color: Int?
    var memberSince: Date?
    var privacy: ProfilePrivacy
    /// Nil when the player hides their stats.
    var stats: PublicStats?

    /// The app reports presence every `FriendsStore.heartbeat`; a missed
    /// couple of beats means the app was killed without going offline.
    var isOnline: Bool {
        guard online, let lastSeen else { return false }
        return Date().timeIntervalSince(lastSeen) < FriendsStore.heartbeat * 2.5
    }

    var initial: String { name.first.map { String($0).uppercased() } ?? "?" }

    /// "Online", "Last seen …", or what the player's privacy leaves to show.
    var presenceText: String {
        if privacy.showOnline && isOnline { return L10n.text("Online") }
        if privacy.showLastSeen, let lastSeen {
            let relative = lastSeen.formatted(.relative(presentation: .named)
                .locale(Locale(identifier: L10n.language.rawValue)))
            return L10n.format("Last seen %@", relative)
        }
        return privacy.showOnline ? L10n.text("Offline") : L10n.text("Status hidden")
    }

    init(id: String, data: [String: Any]) {
        self.id = id
        name = data["name"] as? String ?? ""
        code = data["code"] as? String ?? ""
        online = data["online"] as? Bool ?? false
        lastSeen = (data["lastSeen"] as? Timestamp)?.dateValue()
        bio = data["bio"] as? String ?? ""
        let avatar = data["avatar"] as? [String: Any]
        emoji = avatar?["emoji"] as? String
        color = avatar?["color"] as? Int
        memberSince = (data["createdAt"] as? Timestamp)?.dateValue()
        privacy = ProfilePrivacy(data: data["privacy"] as? [String: Any])
        stats = PublicStats(data: data["stats"] as? [String: Any])
    }
}

struct GameInvite: Identifiable, Equatable {
    enum Status: String { case pending, accepted, declined, cancelled }

    let id: String
    let from: String
    let fromName: String
    let to: String
    /// Nil for a game room whose game isn't picked yet.
    let game: GameID?
    var status: Status
    /// The room the invite is for.
    var roomID: String?
    let createdAt: Date

    /// Invites expire so a stale one doesn't pop up hours later.
    var isFresh: Bool { Date().timeIntervalSince(createdAt) < 300 }

    init?(id: String, data: [String: Any]) {
        guard let from = data["from"] as? String, let to = data["to"] as? String,
              let status = (data["status"] as? String).flatMap(Status.init(rawValue:)) else { return nil }
        self.id = id
        self.from = from
        self.to = to
        game = (data["game"] as? String).flatMap(GameID.init(rawValue:))
        self.status = status
        fromName = data["fromName"] as? String ?? ""
        roomID = data["roomID"] as? String
        createdAt = (data["createdAt"] as? Timestamp)?.dateValue() ?? .distantPast
    }
}

/// An online match both players open once an invite is accepted.
struct MatchRef: Identifiable, Hashable {
    let id: String
    let game: GameID
    let opponentName: String
}

/// A lobby for multiplayer games: the host invites friends or shares the
/// code, and deals once enough players are in. A game room (`isSession`) is
/// opened without a game: the host picks one in the lobby, and after each
/// match everyone comes back to the same room for the next one.
struct GameRoom: Identifiable, Equatable {
    enum Status: String { case open, started, closed }

    let id: String
    /// The game to deal; a game room has none until the host picks one.
    var game: GameID?
    let isSession: Bool
    let host: String
    let code: String
    /// Seated players' uids and names, in seat order; the host is first.
    var players: [String]
    var names: [String]
    let maxPlayers: Int
    /// Friends the host has invited.
    var invited: [String]
    var status: Status
    var matchID: String?
    /// Who was dealt into `matchID`; a game room stays open, so players who
    /// joined since then wait for the next match.
    var matchPlayers: [String]
    /// Optional rules the host picked (Durak).
    var options: DurakOptions

    init?(id: String, data: [String: Any]) {
        let game = (data["game"] as? String).flatMap(GameID.init(rawValue:))
        let isSession = data["session"] as? Bool ?? false
        guard game != nil || isSession,
              let host = data["host"] as? String,
              let status = (data["status"] as? String).flatMap(Status.init(rawValue:)) else { return nil }
        self.id = id
        self.game = game
        self.isSession = isSession
        self.host = host
        self.status = status
        code = data["code"] as? String ?? ""
        players = data["players"] as? [String] ?? []
        names = data["names"] as? [String] ?? []
        maxPlayers = data["maxPlayers"] as? Int ?? (game?.playerRange ?? GameID.sessionPlayerRange).upperBound
        invited = data["invited"] as? [String] ?? []
        matchID = data["matchID"] as? String
        matchPlayers = data["matchPlayers"] as? [String] ?? []
        let rules = data["options"] as? [String: Bool] ?? [:]
        options = DurakOptions(transfer: rules["transfer"] ?? false, bluff: rules["bluff"] ?? false)
    }

    var isFull: Bool { players.count >= maxPlayers }
    var canStart: Bool { game?.playerRange.contains(players.count) ?? false }
}

enum FriendsError: LocalizedError {
    case notReady, codeNotFound, ownCode, alreadyFriends
    case roomNotFound, roomFull, roomStarted, notEnoughPlayers
    case tooManyPlayers(GameID)
    /// Firestore refused the write: the published rules predate rooms.
    case rulesOutdated

    var errorDescription: String? {
        switch self {
        case .notReady: L10n.text("Friends are not available right now. Check your connection and try again.")
        case .codeNotFound: L10n.text("No player has this code.")
        case .ownCode: L10n.text("That's your own code.")
        case .alreadyFriends: L10n.text("You're already friends.")
        case .roomNotFound: L10n.text("No open room has this code.")
        case .roomFull: L10n.text("This room is full.")
        case .roomStarted: L10n.text("This game has already started.")
        case .notEnoughPlayers: L10n.text("Wait for at least one more player.")
        case .tooManyPlayers(let game):
            L10n.format("%@ is for up to %d players.", game.info.title, game.playerRange.upperBound)
        case .rulesOutdated: L10n.text("The friends database isn't set up yet. Create Firestore and publish firestore.rules.")
        }
    }
}

@MainActor
@Observable
final class FriendsStore {
    enum Status: Equatable {
        case idle, connecting, ready
        case unavailable(String)
    }

    static let heartbeat: TimeInterval = 30
    /// The player's name, kept on the phone too so nearby games know it offline.
    static let nameKey = "friends.displayName"

    private(set) var status: Status = .idle
    private(set) var me: FriendProfile?
    private(set) var friends: [FriendProfile] = []
    /// The newest pending invite addressed to this player.
    private(set) var incomingInvite: GameInvite?
    /// The room this player is in, until its game starts.
    private(set) var room: GameRoom?
    /// A message about the room for the lobby to show, e.g. that it was closed.
    var roomNotice: String?
    /// A match dealt in the game room is on screen; the lobby waits behind it.
    private(set) var inRoomMatch = false
    /// Set when a match is ready to open; the root view presents it and clears it.
    var pendingMatch: MatchRef?

    var uid: String? { Auth.auth().currentUser?.uid }

    @ObservationIgnored private lazy var db = Firestore.firestore()
    @ObservationIgnored private var listeners: [ListenerRegistration] = []
    @ObservationIgnored private var friendListeners: [String: ListenerRegistration] = [:]
    @ObservationIgnored private var roomListener: ListenerRegistration?
    /// The game room's latest match this player has seen, so each opens once.
    @ObservationIgnored private var seenRoomMatch: String?
    /// Said once the match on screen is over, not in the middle of it.
    @ObservationIgnored private var deferredNotice: String?
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored private var dismissedInvites: Set<String> = []
    @ObservationIgnored private var isActive = true
    @ObservationIgnored private var lastPublishedStats: PublicStats?

    // MARK: Lifecycle

    /// Signs in anonymously, creates the profile on first launch and starts
    /// listening for friends and invites. Safe to call repeatedly.
    func start() async {
        guard status == .idle || isUnavailable else { return }
        status = .connecting
        do {
            let user: User
            if let current = Auth.auth().currentUser { user = current }
            else { user = try await Auth.auth().signInAnonymously().user }
            try await ensureProfile(uid: user.uid)
            listen(uid: user.uid)
            status = .ready
            startHeartbeat()
        } catch {
            Logger(subsystem: "PuzzleBox", category: "Friends").error("Friends unavailable: \(String(describing: error), privacy: .public)")
            status = .unavailable(Self.describe(error))
        }
    }

    /// Firebase reports a project without Anonymous sign-in or Firestore as
    /// a vague internal error; point at the setup step instead.
    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == AuthErrorDomain,
           let code = AuthErrorCode(rawValue: nsError.code),
           [AuthErrorCode.internalError, .operationNotAllowed, .adminRestrictedOperation].contains(code) {
            return L10n.text("Anonymous sign-in isn't enabled for this app yet. Turn it on in Firebase Console → Authentication.")
        }
        if nsError.domain == FirestoreErrorDomain,
           [FirestoreErrorCode.permissionDenied.rawValue, FirestoreErrorCode.notFound.rawValue].contains(nsError.code) {
            return L10n.text("The friends database isn't set up yet. Create Firestore and publish firestore.rules.")
        }
        #if DEBUG
        let underlying = (nsError.userInfo[NSUnderlyingErrorKey] as? NSError).map { " ← \($0.domain) \($0.code) \($0.userInfo)" } ?? ""
        return "\(error.localizedDescription) [\(nsError.domain) \(nsError.code)\(underlying)]"
        #else
        return error.localizedDescription
        #endif
    }

    private var isUnavailable: Bool {
        if case .unavailable = status { true } else { false }
    }

    /// Foreground/background: drives the online flag.
    func setActive(_ active: Bool) {
        isActive = active
        guard status == .ready, let uid else { return }
        db.collection("users").document(uid).setData(presence(active: active), merge: true)
        if active { startHeartbeat() } else { heartbeatTask?.cancel() }
    }

    private var privacy: ProfilePrivacy { me?.privacy ?? ProfilePrivacy() }

    /// The presence fields to write. A hidden online status is always
    /// "offline"; a hidden last-seen time is only stored while it is needed
    /// to tell that the player is online, and removed when they leave.
    private func presence(active: Bool) -> [String: Any] {
        let visible = active && privacy.showOnline
        let keepsLastSeen = visible || privacy.showLastSeen
        return ["online": visible,
                "lastSeen": keepsLastSeen ? FieldValue.serverTimestamp() : FieldValue.delete()]
    }

    /// Only a visible online status needs refreshing.
    private func startHeartbeat() {
        heartbeatTask?.cancel()
        guard privacy.showOnline else { return }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isActive, self.privacy.showOnline, let uid = self.uid else { return }
                try? await self.db.collection("users").document(uid).setData(self.presence(active: true), merge: true)
                try? await Task.sleep(for: .seconds(Self.heartbeat))
            }
        }
    }

    private func ensureProfile(uid: String) async throws {
        let ref = db.collection("users").document(uid)
        let snapshot = try await ref.getDocument()
        let saved = ProfilePrivacy(data: snapshot.data()?["privacy"] as? [String: Any])
        var data: [String: Any] = ["online": saved.showOnline,
                                   "lastSeen": saved.showOnline || saved.showLastSeen
                                       ? FieldValue.serverTimestamp() : FieldValue.delete()]
        if snapshot.data()?["createdAt"] == nil {
            data["createdAt"] = FieldValue.serverTimestamp()
        }
        if snapshot.data()?["code"] as? String == nil {
            data["code"] = try await uniqueCode()
        }
        if (snapshot.data()?["name"] as? String ?? "").isEmpty {
            let saved = UserDefaults.standard.string(forKey: Self.nameKey)
            // Plain digits: a locale-formatted number would read "Player 4,685".
            data["name"] = saved ?? L10n.text("Player %d").replacingOccurrences(of: "%d", with: String(Int.random(in: 1000...9999)))
        }
        try await ref.setData(data, merge: true)
    }

    /// A short code friends type in; unambiguous characters only.
    private func uniqueCode() async throws -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        for _ in 0..<5 {
            let code = String((0..<6).map { _ in alphabet.randomElement()! })
            let taken = try await db.collection("users").whereField("code", isEqualTo: code).limit(to: 1).getDocuments()
            if taken.isEmpty { return code }
        }
        return String(UUID().uuidString.prefix(8))
    }

    // MARK: Listening

    private func listen(uid: String) {
        listeners.forEach { $0.remove() }
        listeners = [
            db.collection("users").document(uid).addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot, let data = snapshot.data() else { return }
                MainActor.assumeIsolated {
                    let profile = FriendProfile(id: uid, data: data)
                    self.me = profile
                    if !profile.name.isEmpty { UserDefaults.standard.set(profile.name, forKey: Self.nameKey) }
                }
            },
            db.collection("users").document(uid).collection("friends").addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot else { return }
                let ids = snapshot.documents.map(\.documentID)
                MainActor.assumeIsolated { self.syncFriendListeners(ids) }
            },
            db.collection("invites")
                .whereField("to", isEqualTo: uid)
                .whereField("status", isEqualTo: GameInvite.Status.pending.rawValue)
                .addSnapshotListener { [weak self] snapshot, _ in
                    guard let self, let snapshot else { return }
                    let invites = snapshot.documents.compactMap { GameInvite(id: $0.documentID, data: $0.data()) }
                    MainActor.assumeIsolated {
                        self.incomingInvite = invites
                            .filter { $0.isFresh && !self.dismissedInvites.contains($0.id) }
                            .max { $0.createdAt < $1.createdAt }
                    }
                }
        ]
    }

    /// One document listener per friend keeps names and presence live.
    private func syncFriendListeners(_ ids: [String]) {
        let wanted = Set(ids)
        for (id, listener) in friendListeners where !wanted.contains(id) {
            listener.remove()
            friendListeners[id] = nil
        }
        friends.removeAll { !wanted.contains($0.id) }
        for id in wanted where friendListeners[id] == nil {
            friendListeners[id] = db.collection("users").document(id).addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let snapshot, let data = snapshot.data() else { return }
                MainActor.assumeIsolated { self.upsert(FriendProfile(id: id, data: data)) }
            }
        }
    }

    private func upsert(_ friend: FriendProfile) {
        if let index = friends.firstIndex(where: { $0.id == friend.id }) {
            friends[index] = friend
        } else {
            friends.append(friend)
        }
        friends.sort { lhs, rhs in
            lhs.isOnline != rhs.isOnline ? lhs.isOnline
                : lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: Profile and friends

    func rename(_ name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        guard !trimmed.isEmpty, let uid else { return }
        UserDefaults.standard.set(trimmed, forKey: Self.nameKey)
        db.collection("users").document(uid).setData(["name": trimmed], merge: true)
        AppAnalytics.log("friends_renamed")
    }

    static let bioLimit = 80

    /// Saves the name, the line about the player and the avatar.
    func updateProfile(name: String, bio: String, emoji: String?, color: Int) {
        guard let uid else { return }
        rename(name)
        var avatar: [String: Any] = ["color": color]
        if let emoji { avatar["emoji"] = emoji }
        db.collection("users").document(uid).setData([
            "bio": String(bio.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.bioLimit)),
            "avatar": avatar
        ], merge: true)
        AppAnalytics.log("profile_edited")
    }

    /// Applies new privacy choices: stores them, and rewrites or removes the
    /// presence and stats they cover.
    func setPrivacy(_ privacy: ProfilePrivacy, stats: PublicStats) {
        guard let uid else { return }
        me?.privacy = privacy
        var data = presence(active: isActive)
        data["privacy"] = privacy.data
        data["stats"] = privacy.showStats ? stats.data : FieldValue.delete()
        db.collection("users").document(uid).setData(data, merge: true)
        lastPublishedStats = privacy.showStats ? stats : nil
        startHeartbeat()
        AppAnalytics.log("privacy_changed")
    }

    /// Shares the latest game stats on the profile, unless they are hidden.
    func publish(_ stats: PublicStats) {
        guard status == .ready, let uid, privacy.showStats, stats != lastPublishedStats else { return }
        lastPublishedStats = stats
        db.collection("users").document(uid).setData(["stats": stats.data], merge: true)
    }

    /// Another player's friends, when they share the list.
    func friends(of profile: FriendProfile) async throws -> [FriendProfile] {
        let ids = try await db.collection("users").document(profile.id).collection("friends")
            .getDocuments().documents.map(\.documentID)
        var result: [FriendProfile] = []
        // Firestore's "in" queries take up to 30 values at a time.
        for start in stride(from: 0, to: ids.count, by: 30) {
            let chunk = Array(ids[start..<min(start + 30, ids.count)])
            let found = try await db.collection("users").whereField(FieldPath.documentID(), in: chunk).getDocuments()
            result += found.documents.map { FriendProfile(id: $0.documentID, data: $0.data()) }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Adds the player with `code` as a friend on both sides.
    func addFriend(code raw: String) async throws {
        guard status == .ready, let uid else { throw FriendsError.notReady }
        let code = raw.uppercased().filter { !$0.isWhitespace }
        guard code != me?.code else { throw FriendsError.ownCode }
        let found = try await db.collection("users").whereField("code", isEqualTo: code).limit(to: 1).getDocuments()
        guard let friend = found.documents.first else { throw FriendsError.codeNotFound }
        guard !friends.contains(where: { $0.id == friend.documentID }) else { throw FriendsError.alreadyFriends }
        let batch = db.batch()
        let since: [String: Any] = ["since": FieldValue.serverTimestamp()]
        batch.setData(since, forDocument: db.collection("users").document(uid).collection("friends").document(friend.documentID))
        batch.setData(since, forDocument: db.collection("users").document(friend.documentID).collection("friends").document(uid))
        try await batch.commit()
        AppAnalytics.log("friend_added")
    }

    func removeFriend(_ friend: FriendProfile) {
        guard let uid else { return }
        let batch = db.batch()
        batch.deleteDocument(db.collection("users").document(uid).collection("friends").document(friend.id))
        batch.deleteDocument(db.collection("users").document(friend.id).collection("friends").document(uid))
        batch.commit()
        AppAnalytics.log("friend_removed")
    }

    // MARK: Rooms

    /// "Permission denied" from Firestore means the console still has rules
    /// from before rooms; say so instead of the raw message.
    private static func roomError(_ error: Error) -> Error {
        let nsError = error as NSError
        if nsError.domain == FirestoreErrorDomain, nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
            return FriendsError.rulesOutdated
        }
        return error
    }

    /// Opens a new room for `game` with this player as host, and enters it.
    /// Without a game it is a game room: the host picks games in the lobby
    /// and the room stays open between matches.
    func createRoom(for game: GameID?) async throws {
        do { try await openRoom(for: game) } catch { throw Self.roomError(error) }
    }

    private func openRoom(for game: GameID?) async throws {
        guard status == .ready, let uid, let me else { throw FriendsError.notReady }
        leaveRoom()
        let ref = db.collection("rooms").document()
        var data: [String: Any] = [
            "host": uid,
            "code": try await uniqueRoomCode(),
            "players": [uid],
            "names": [me.name],
            "maxPlayers": (game?.playerRange ?? GameID.sessionPlayerRange).upperBound,
            "invited": [String](),
            "options": Self.encode(DurakOptions.saved),
            "status": GameRoom.Status.open.rawValue,
            "createdAt": FieldValue.serverTimestamp()
        ]
        if let game { data["game"] = game.rawValue } else { data["session"] = true }
        try await ref.setData(data)
        listenToRoom(ref.documentID)
        AppAnalytics.log("room_created", parameters: ["game_id": game?.rawValue ?? "session"])
    }

    /// Enters the open room with `code`.
    func joinRoom(code raw: String) async throws {
        do { try await findAndJoin(code: raw) } catch { throw Self.roomError(error) }
    }

    private func findAndJoin(code raw: String) async throws {
        guard status == .ready else { throw FriendsError.notReady }
        let code = raw.uppercased().filter { !$0.isWhitespace }
        let found = try await db.collection("rooms")
            .whereField("code", isEqualTo: code)
            .whereField("status", isEqualTo: GameRoom.Status.open.rawValue)
            .limit(to: 1).getDocuments()
        guard let room = found.documents.first else { throw FriendsError.roomNotFound }
        try await takeSeat(inRoom: room.documentID)
    }

    /// Takes a free seat in room `id`; a transaction keeps two players from
    /// taking the last seat at once.
    func joinRoom(id: String) async throws {
        do { try await takeSeat(inRoom: id) } catch { throw Self.roomError(error) }
    }

    private func takeSeat(inRoom id: String) async throws {
        guard status == .ready, let uid, let me else { throw FriendsError.notReady }
        if room?.id != id { leaveRoom() }
        let ref = db.collection("rooms").document(id)
        _ = try await db.runTransaction { transaction, errorPointer in
            do {
                let snapshot = try transaction.getDocument(ref)
                guard let data = snapshot.data(), let room = GameRoom(id: id, data: data) else {
                    throw FriendsError.roomNotFound
                }
                guard room.status == .open else { throw FriendsError.roomStarted }
                if room.players.contains(uid) { return nil }
                guard room.players.count < room.maxPlayers else { throw FriendsError.roomFull }
                transaction.updateData(["players": room.players + [uid], "names": room.names + [me.name]],
                                       forDocument: ref)
            } catch {
                errorPointer?.pointee = error as NSError
            }
            return nil
        }
        listenToRoom(id)
        AppAnalytics.log("room_joined")
    }

    /// Leaves the current room. A host leaving closes it for everyone.
    func leaveRoom() {
        guard let room, let uid else { return }
        roomListener?.remove()
        roomListener = nil
        self.room = nil
        seenRoomMatch = nil
        let ref = db.collection("rooms").document(room.id)
        if room.host == uid {
            ref.updateData(["status": GameRoom.Status.closed.rawValue])
        } else if room.status == .open {
            db.runTransaction({ transaction, _ in
                guard let snapshot = try? transaction.getDocument(ref), let data = snapshot.data(),
                      let latest = GameRoom(id: room.id, data: data),
                      let index = latest.players.firstIndex(of: uid) else { return nil }
                var players = latest.players, names = latest.names
                players.remove(at: index)
                if names.indices.contains(index) { names.remove(at: index) }
                transaction.updateData(["players": players, "names": names], forDocument: ref)
                return nil
            }, completion: { _, _ in })
        }
    }

    private static func encode(_ options: DurakOptions) -> [String: Bool] {
        ["transfer": options.transfer, "bluff": options.bluff]
    }

    /// Host only: changes the optional rules everyone in the room will play by.
    func setRoomOptions(_ options: DurakOptions) {
        guard let room, room.host == uid, room.status == .open else { return }
        self.room?.options = options
        db.collection("rooms").document(room.id).updateData(["options": Self.encode(options)])
    }

    /// Host only: picks the game a game room plays next.
    func setRoomGame(_ game: GameID) {
        guard let room, room.host == uid, room.isSession, room.status == .open, game.supportsFriends else { return }
        self.room?.game = game
        db.collection("rooms").document(room.id).updateData(["game": game.rawValue])
        AppAnalytics.log("room_game_selected", parameters: ["game_id": game.rawValue])
    }

    /// Sends `friend` an invite to the current room (again, if they missed it).
    func inviteToRoom(_ friend: FriendProfile) {
        guard let room, let uid, let me, room.host == uid, friend.privacy.allowInvites else { return }
        var invite: [String: Any] = [
            "from": uid,
            "fromName": me.name,
            "to": friend.id,
            "roomID": room.id,
            "status": GameInvite.Status.pending.rawValue,
            "createdAt": Timestamp(date: Date())
        ]
        // A game room's invite is to the room, whatever it plays next.
        if !room.isSession, let game = room.game { invite["game"] = game.rawValue }
        db.collection("invites").document().setData(invite)
        if !room.invited.contains(friend.id) {
            db.collection("rooms").document(room.id).updateData(["invited": FieldValue.arrayUnion([friend.id])])
        }
        AppAnalytics.log("invite_sent", parameters: ["game_id": room.game?.rawValue ?? "session"])
    }

    /// Host only: deals the game for everyone in the room, whoever has
    /// joined so far, and opens it on every phone in the room.
    func startRoom() async throws {
        guard let room, let uid, room.host == uid, let game = room.game else { return }
        guard room.players.count >= game.playerRange.lowerBound else { throw FriendsError.notEnoughPlayers }
        guard room.players.count <= game.playerRange.upperBound else { throw FriendsError.tooManyPlayers(game) }
        do { try await deal(room, game: game) } catch { throw Self.roomError(error) }
    }

    private func deal(_ room: GameRoom, game: GameID) async throws {
        let match = db.collection("matches").document()
        let batch = db.batch()
        batch.setData([
            "game": game.rawValue,
            "players": room.players,
            "names": room.names,
            "state": onlineInitialState(for: game, players: room.players.count, options: room.options),
            "version": 0,
            "createdAt": FieldValue.serverTimestamp()
        ], forDocument: match)
        // A game room stays open: players come back to it after the match,
        // and newcomers can join for the next one.
        let roomUpdate: [String: Any] = room.isSession
            ? ["matchID": match.documentID, "matchPlayers": room.players]
            : ["status": GameRoom.Status.started.rawValue, "matchID": match.documentID]
        batch.updateData(roomUpdate, forDocument: db.collection("rooms").document(room.id))
        try await batch.commit()
        AppAnalytics.log("room_started", parameters: ["game_id": game.rawValue, "players": room.players.count,
                                                      "session": room.isSession])
    }

    /// The game room's match was closed: back to the lobby, if the room is still there.
    func roomMatchFinished() {
        guard inRoomMatch else { return }
        inRoomMatch = false
        if let deferredNotice, room == nil { roomNotice = deferredNotice }
        deferredNotice = nil
    }

    private func listenToRoom(_ id: String) {
        roomListener?.remove()
        roomListener = db.collection("rooms").document(id).addSnapshotListener { [weak self] snapshot, _ in
            guard let self, let snapshot, let data = snapshot.data(),
                  let room = GameRoom(id: id, data: data) else { return }
            MainActor.assumeIsolated { self.update(room) }
        }
    }

    private func update(_ room: GameRoom) {
        guard let uid else { return }
        switch room.status {
        case .started where room.players.contains(uid):
            // The host dealt: everyone in the room opens the match.
            roomListener?.remove()
            roomListener = nil
            self.room = nil
            if let matchID = room.matchID, let game = room.game {
                let others = room.names.enumerated()
                    .filter { room.players.indices.contains($0.offset) && room.players[$0.offset] != uid }
                    .map(\.element)
                pendingMatch = MatchRef(id: matchID, game: game, opponentName: others.joined(separator: ", "))
            }
        case .open where room.players.contains(uid):
            // A game room's earlier match isn't reopened on (re)joining.
            if self.room?.id != room.id { seenRoomMatch = room.matchID }
            self.room = room
            if room.isSession, let matchID = room.matchID, matchID != seenRoomMatch {
                seenRoomMatch = matchID
                if room.matchPlayers.contains(uid), let game = room.game {
                    let others = zip(room.players, room.names)
                        .filter { $0.0 != uid && room.matchPlayers.contains($0.0) }.map(\.1)
                    inRoomMatch = true
                    pendingMatch = MatchRef(id: matchID, game: game, opponentName: others.joined(separator: ", "))
                }
            }
        default:
            // Closed by the host, or started without this player.
            roomListener?.remove()
            roomListener = nil
            if self.room != nil {
                let notice = L10n.text("The room was closed.")
                if inRoomMatch { deferredNotice = notice } else { roomNotice = notice }
            }
            self.room = nil
            seenRoomMatch = nil
        }
    }

    /// A short code friends type in; unambiguous characters only.
    private func uniqueRoomCode() async throws -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        for _ in 0..<5 {
            let code = String((0..<6).map { _ in alphabet.randomElement()! })
            let taken = try await db.collection("rooms")
                .whereField("code", isEqualTo: code)
                .whereField("status", isEqualTo: GameRoom.Status.open.rawValue)
                .limit(to: 1).getDocuments()
            if taken.isEmpty { return code }
        }
        return String(UUID().uuidString.prefix(6))
    }

    // MARK: Invites

    /// Accepting an invite takes a seat in the inviter's room.
    func accept(_ invite: GameInvite) async {
        dismissedInvites.insert(invite.id)
        incomingInvite = nil
        db.collection("invites").document(invite.id)
            .updateData(["status": GameInvite.Status.accepted.rawValue]) { _ in }
        guard let roomID = invite.roomID else { return }
        do {
            try await joinRoom(id: roomID)
            AppAnalytics.log("invite_accepted", parameters: ["game_id": invite.game?.rawValue ?? "session"])
        } catch {
            roomNotice = error.localizedDescription
            AppAnalytics.log("invite_accept_failed")
        }
    }

    func decline(_ invite: GameInvite) {
        dismissedInvites.insert(invite.id)
        incomingInvite = nil
        db.collection("invites").document(invite.id).updateData(["status": GameInvite.Status.declined.rawValue])
        AppAnalytics.log("invite_declined", parameters: ["game_id": invite.game?.rawValue ?? "session"])
    }
}
