import Foundation
import Observation
import MultipeerConnectivity
import UIKit

// Games with people nearby, without internet: phones find each other and talk
// directly, over peer-to-peer Wi-Fi (MultipeerConnectivity) and over Bluetooth
// LE (`NearbyBluetooth`) at the same time, so it works with no network at all,
// in airplane mode with Wi-Fi or Bluetooth turned back on. A room seen both
// ways is joined over Wi-Fi first, then Bluetooth if that fails.
//
// The phone that opens the room is the host. It advertises the room, holds
// the lobby and, once the game starts, the one true table: players send it
// the table after their move together with the version they played on; the
// host accepts it only if that version is still current (as Firestore's
// transaction does online) and sends the new table to everyone.

/// A player in a nearby room. The id is kept on the phone, so it is the same
/// in every game.
struct NearbyPlayer: Codable, Equatable, Identifiable {
    let id: String
    let name: String
}

/// The room as the host shares it with everyone in it.
struct NearbyLobby: Codable, Equatable {
    var game: String
    var players: [NearbyPlayer]
    var maxPlayers: Int
    var options: DurakOptions
    var started = false

    var gameID: GameID { GameID(rawValue: game) ?? .durak }
    var canStart: Bool { players.count >= gameID.playerRange.lowerBound }
    var isFull: Bool { players.count >= maxPlayers }
}

/// How this phone reaches another one.
enum NearbyLink: Hashable {
    case multipeer(MCPeerID)
    case bluetooth(UUID)

    var isMultipeer: Bool { if case .multipeer = self { true } else { false } }
}

/// A room another phone nearby is advertising.
struct NearbyRoom: Identifiable, Equatable {
    /// The host's player id.
    let id: String
    /// Ways to reach the host, the one to try first first.
    var links: [NearbyLink]
    let game: GameID
    let hostName: String
    let players: Int
    let maxPlayers: Int
}

/// A started nearby game, for the root view to present.
struct NearbyMatchRef: Identifiable, Hashable {
    let id: String
    let game: GameID
}

private enum NearbyMessage: Codable {
    case lobby(NearbyLobby)
    case start(state: String)
    case state(String, version: Int)
    case move(String, base: Int)
    case forfeit(String)
    /// A player closes the game without conceding (they were already out, or it ended).
    case bye(String)
    case closed
}

@MainActor
@Observable
final class NearbyStore: NSObject {
    enum Role { case host, guest }

    static let serviceType = "pbx-room"
    private static let playerIDKey = "nearby.playerID"

    private(set) var role: Role?
    private(set) var lobby: NearbyLobby?
    /// Rooms found nearby while looking.
    private(set) var rooms: [NearbyRoom] = []
    /// The room being joined, until the host lets this player in.
    private(set) var joining: NearbyRoom?
    /// Set when a game starts; the root view presents it and clears it.
    var pendingMatch: NearbyMatchRef?
    /// Something to tell the player, e.g. that the host closed the room.
    var notice: String?

    // The match in progress.
    private(set) var matchState: String?
    private(set) var matchVersion = 0
    private(set) var matchPlayers: [NearbyPlayer] = []
    private(set) var forfeitedBy: String?

    @ObservationIgnored private let peerID: MCPeerID
    @ObservationIgnored private var session: MCSession?
    @ObservationIgnored private var advertiser: MCNearbyServiceAdvertiser?
    @ObservationIgnored private var browser: MCNearbyServiceBrowser?
    /// The nearby screen is up, listing rooms.
    @ObservationIgnored private var looking = false
    @ObservationIgnored private let bluetooth = NearbyBluetooth()
    /// Rooms as each link sees them; `rooms` merges them by host.
    @ObservationIgnored private var sightings: [NearbyLink: NearbyRoom] = [:]
    /// Links of the room being joined still to try.
    @ObservationIgnored private var joinLinks: [NearbyLink] = []
    /// Host only: which peer is which player.
    @ObservationIgnored private var players: [NearbyLink: NearbyPlayer] = [:]
    @ObservationIgnored private var hostLink: NearbyLink?
    /// Host only: players who said goodbye, so their disconnect isn't a forfeit.
    @ObservationIgnored private var departed: Set<String> = []

    let me: NearbyPlayer

    override init() {
        let defaults = UserDefaults.standard
        let id = defaults.string(forKey: Self.playerIDKey) ?? UUID().uuidString
        defaults.set(id, forKey: Self.playerIDKey)
        let name = defaults.string(forKey: FriendsStore.nameKey) ?? UIDevice.current.name
        me = NearbyPlayer(id: id, name: name)
        // Peer names are limited to 63 bytes.
        peerID = MCPeerID(displayName: String(name.prefix(20)))
        super.init()
        bluetooth.delegate = self
    }

    var isHost: Bool { role == .host }
    var inRoom: Bool { lobby != nil || joining != nil }

    private func makeSession() -> MCSession {
        let session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session
        return session
    }

    // MARK: Hosting

    /// Opens a room for `game` and starts advertising it nearby.
    func host(_ game: GameID) {
        leave()
        role = .host
        _ = makeSession()
        lobby = NearbyLobby(game: game.rawValue, players: [me], maxPlayers: game.playerRange.upperBound,
                            options: .saved)
        advertise()
        AppAnalytics.log("nearby_room_created", parameters: ["game_id": game.rawValue])
    }

    /// (Re)starts advertising with the current player count; discovery info
    /// can't change while advertising. A full or started room keeps
    /// advertising, marked closed, until it's left: with no Wi-Fi network,
    /// peer-to-peer Wi-Fi stays up only while this phone advertises or
    /// browses, and the session drops with it. So the new advertiser starts
    /// before the old one stops, and never none at all.
    private func advertise() {
        guard let lobby else { return }
        let open = !lobby.started && !lobby.isFull
        var info = ["game": lobby.game, "host": me.name, "n": "\(lobby.players.count)", "max": "\(lobby.maxPlayers)",
                    "id": me.id]
        if !open { info["open"] = "0" }
        bluetooth.host(open ? info : nil)
        let advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: info, serviceType: Self.serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser?.stopAdvertisingPeer()
        self.advertiser = advertiser
    }

    /// Host only: the optional rules everyone will play by.
    func setOptions(_ options: DurakOptions) {
        guard isHost, lobby?.started == false else { return }
        lobby?.options = options
        broadcastLobby()
    }

    /// Host only: deals for everyone in the room and starts the game.
    func start() {
        guard isHost, var lobby, lobby.canStart, !lobby.started else { return }
        let state = onlineInitialState(for: lobby.gameID, players: lobby.players.count, options: lobby.options)
        lobby.started = true
        self.lobby = lobby
        advertise()
        beginMatch(players: lobby.players, state: state)
        send(.start(state: state))
        broadcastLobby()
        AppAnalytics.log("nearby_room_started", parameters: ["game_id": lobby.game, "players": lobby.players.count])
    }

    private func broadcastLobby() {
        guard let lobby else { return }
        send(.lobby(lobby))
    }

    // MARK: Joining

    /// Looks for rooms nearby until `stopLooking()`.
    func look() {
        looking = true
        bluetooth.look()
        guard browser == nil else { return }
        let browser = MCNearbyServiceBrowser(peer: peerID, serviceType: Self.serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
    }

    func stopLooking() {
        looking = false
        bluetooth.stopLooking()
        sightings = [:]
        rooms = []
        // In a room the browser keeps peer-to-peer Wi-Fi up (see `advertise()`); it stops on leaving.
        guard role == nil else { return }
        browser?.stopBrowsingForPeers()
        browser = nil
    }

    /// Asks the host of `room` to let this player in.
    func join(_ room: NearbyRoom) {
        guard joining == nil, lobby == nil else { return }
        role = .guest
        joining = room
        joinLinks = room.links
        tryNextLink()
    }

    /// Knocks on the joining room over its next link. Returns false when none is left.
    @discardableResult
    private func tryNextLink() -> Bool {
        let context = (try? JSONEncoder().encode(me)) ?? Data()
        while !joinLinks.isEmpty {
            let link = joinLinks.removeFirst()
            session?.disconnect()
            session = nil
            switch link {
            case .multipeer(let peer):
                guard let browser else { continue }
                hostLink = link
                browser.invitePeer(peer, to: makeSession(), withContext: context, timeout: 15)
            case .bluetooth(let id):
                hostLink = link
                bluetooth.join(id, context: context)
            }
            return true
        }
        return false
    }

    // MARK: Leaving

    /// Leaves the room or game. A host leaving closes it for everyone.
    func leave() {
        if isHost {
            send(.closed)
        } else if matchState != nil {
            send(.bye(me.id), to: hostLink.map { [$0] })
        }
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        if !looking {
            browser?.stopBrowsingForPeers()
            browser = nil
        }
        session?.disconnect()
        session = nil
        bluetooth.disconnect()
        players = [:]
        departed = []
        hostLink = nil
        joinLinks = []
        role = nil
        lobby = nil
        joining = nil
        matchState = nil
        matchVersion = 0
        matchPlayers = []
        forfeitedBy = nil
    }

    // MARK: The match

    private func beginMatch(players: [NearbyPlayer], state: String) {
        matchPlayers = players
        matchState = state
        matchVersion = 0
        forfeitedBy = nil
        pendingMatch = NearbyMatchRef(id: UUID().uuidString, game: lobby?.gameID ?? .durak)
    }

    /// Plays this player's move. The host applies it at once; a guest shows
    /// it at once and the host confirms it, or sends back the real table.
    func play(_ encoded: String) {
        if isHost {
            commit(encoded)
        } else {
            matchState = encoded
            send(.move(encoded, base: matchVersion), to: hostLink.map { [$0] })
        }
    }

    private func commit(_ encoded: String) {
        matchVersion += 1
        matchState = encoded
        send(.state(encoded, version: matchVersion))
    }

    func forfeit() {
        if isHost {
            forfeitedBy = me.id
            send(.forfeit(me.id))
        } else {
            send(.forfeit(me.id), to: hostLink.map { [$0] })
        }
    }

    // MARK: Messages

    /// Sends to `links`, or to everyone connected.
    private func send(_ message: NearbyMessage, to links: [NearbyLink]? = nil) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        var peers: [MCPeerID] = []
        var bluetoothIDs: [UUID] = []
        for link in links ?? ((session?.connectedPeers ?? []).map { .multipeer($0) }
                              + bluetooth.connectedIDs.map { .bluetooth($0) }) {
            switch link {
            case .multipeer(let peer): peers.append(peer)
            case .bluetooth(let id): bluetoothIDs.append(id)
            }
        }
        if let session, !peers.isEmpty { try? session.send(data, toPeers: peers, with: .reliable) }
        if !bluetoothIDs.isEmpty { bluetooth.send(data, to: bluetoothIDs) }
    }

    private func receive(_ data: Data, from peer: NearbyLink) {
        guard let message = try? JSONDecoder().decode(NearbyMessage.self, from: data) else { return }
        switch message {
        case .lobby(let lobby):
            guard !isHost else { return }
            joining = nil
            self.lobby = lobby
        case .start(let state):
            guard !isHost, let lobby else { return }
            beginMatch(players: lobby.players, state: state)
        case .state(let state, let version):
            guard !isHost else { return }
            matchState = state
            matchVersion = version
        case .move(let state, let base):
            guard isHost else { return }
            if base == matchVersion {
                commit(state)
            } else if let matchState {
                // Played on an old table: put the real one back.
                send(.state(matchState, version: matchVersion), to: [peer])
            }
        case .forfeit(let id):
            forfeitedBy = id
            if isHost { send(.forfeit(id)) }
        case .bye(let id):
            departed.insert(id)
        case .closed:
            hostLeft()
        }
    }

    /// The host closed the room or lost the connection.
    private func hostLeft() {
        guard !isHost else { return }
        if matchState != nil, forfeitedBy == nil {
            // Mid-game: the game ends as if the host left it.
            forfeitedBy = lobby?.players.first?.id
        } else if matchState == nil {
            leave()
            notice = L10n.text("The room was closed.")
        }
    }

    /// Host only: a player connected or dropped out.
    private func peerChanged(_ peer: NearbyLink, connected: Bool) {
        if isHost {
            guard let player = players[peer] else { return }
            if connected {
                guard var lobby, !lobby.started else { return }
                if !lobby.players.contains(player) { lobby.players.append(player) }
                self.lobby = lobby
                broadcastLobby()
                // Late joiners of a started game never get here: the room stops advertising.
                advertise()
            } else {
                players[peer] = nil
                if lobby?.started == true {
                    // Someone still playing dropped out: the game can't go on.
                    if forfeitedBy == nil, matchPlayers.contains(player), !departed.contains(player.id) {
                        forfeitedBy = player.id
                        send(.forfeit(player.id))
                    }
                } else {
                    lobby?.players.removeAll { $0 == player }
                    broadcastLobby()
                    advertise()
                }
            }
        } else if peer == hostLink, !connected {
            if joining != nil {
                // Try the room's other link, if it has one, before giving up.
                guard !tryNextLink() else { return }
                leave()
                notice = L10n.text("Couldn't join the room.")
            } else {
                hostLeft()
            }
        }
    }

    /// Host only: lets a player in while there is room.
    private func shouldAdmit(_ peer: NearbyLink, context: Data?) -> Bool {
        guard isHost, let lobby, !lobby.started, !lobby.isFull,
              let context, let player = try? JSONDecoder().decode(NearbyPlayer.self, from: context) else { return false }
        players[peer] = player
        return true
    }

    private func found(_ link: NearbyLink, info: [String: String]?) {
        guard looking else { return }
        guard info?["open"] != "0" else { return lost(link) }
        guard let info, let game = info["game"].flatMap(GameID.init(rawValue:)) else { return }
        let fallbackName: String
        switch link {
        case .multipeer(let peer): fallbackName = peer.displayName
        case .bluetooth: fallbackName = ""
        }
        sightings[link] = NearbyRoom(id: info["id"] ?? "\(link)", links: [link], game: game,
                                     hostName: info["host"] ?? fallbackName,
                                     players: Int(info["n"] ?? "") ?? 1, maxPlayers: Int(info["max"] ?? "") ?? 2)
        mergeRooms()
    }

    private func lost(_ link: NearbyLink) {
        guard sightings.removeValue(forKey: link) != nil else { return }
        mergeRooms()
    }

    /// One room per host, keeping the order rooms were first seen in.
    private func mergeRooms() {
        let byHost = Dictionary(grouping: sightings.values, by: \.id)
        var merged: [NearbyRoom] = rooms.compactMap { room in byHost[room.id].map(Self.merge) }
        for (id, seen) in byHost where !merged.contains(where: { $0.id == id }) {
            merged.append(Self.merge(seen))
        }
        rooms = merged
    }

    /// Wi-Fi first: it's faster, and the room info it brings is the same.
    private static func merge(_ seen: [NearbyRoom]) -> NearbyRoom {
        let ordered = seen.sorted { $0.links[0].isMultipeer && !$1.links[0].isMultipeer }
        var room = ordered[0]
        room.links = ordered.map { $0.links[0] }
        return room
    }
}

// MARK: - MultipeerConnectivity callbacks

// The framework calls these on its own queues; everything moves to the main actor.

extension NearbyStore: MCSessionDelegate {
    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        guard state != .connecting else { return }
        let connected = state == .connected
        Task { @MainActor in self.peerChanged(.multipeer(peerID), connected: connected) }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Decoded on the main actor, where the message types live.
        Task { @MainActor in self.receive(data, from: .multipeer(peerID)) }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String,
                             fromPeer peerID: MCPeerID) {}
    nonisolated func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, with progress: Progress) {}
    nonisolated func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension NearbyStore: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            let admit = self.shouldAdmit(.multipeer(peerID), context: context)
            invitationHandler(admit, admit ? self.session : nil)
        }
    }
}

extension NearbyStore: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in self.found(.multipeer(peerID), info: info) }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in self.lost(.multipeer(peerID)) }
    }
}

extension NearbyStore: NearbyBluetoothDelegate {
    func bluetoothFound(_ id: UUID, info: [String: String]) { found(.bluetooth(id), info: info) }
    func bluetoothLost(_ id: UUID) { lost(.bluetooth(id)) }
    func bluetoothShouldAdmit(_ id: UUID, context: Data) -> Bool { shouldAdmit(.bluetooth(id), context: context) }
    func bluetoothLink(_ id: UUID, connected: Bool) { peerChanged(.bluetooth(id), connected: connected) }
    func bluetoothReceived(_ data: Data, from id: UUID) { receive(data, from: .bluetooth(id)) }
}

// MARK: - Match transport

/// A nearby game, seen through the same interface as an online one.
@MainActor
@Observable
final class NearbyMatchSession: MatchTransport {
    private let store: NearbyStore
    let game: GameID

    init(store: NearbyStore, game: GameID) {
        self.store = store
        self.game = game
    }

    var stateJSON: String? { store.matchState }
    var seat: Int? { store.matchPlayers.firstIndex { $0.id == store.me.id } }
    var names: [String] { store.matchPlayers.map(\.name) }
    var fallbackOpponents: String { names.filter { $0 != store.me.name }.joined(separator: ", ") }
    var isSending: Bool { false }

    var leaverName: String? {
        guard let id = store.forfeitedBy, id != store.me.id else { return nil }
        return store.matchPlayers.first { $0.id == id }?.name ?? ""
    }

    func start() {}
    /// The room is left when the game screen is closed for good (see `RootTabView`),
    /// not whenever the screen disappears.
    func stop() {}
    func send(_ encoded: String) { store.play(encoded) }
    func forfeit() { store.forfeit() }
}
