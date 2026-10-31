import SwiftUI

// MARK: - Lobby

/// The room this player is in, between matches. The host is led through
/// three steps: invite friends, wait for them, start. Everyone sees who is
/// here, can invite their own friends and share a link with the code.
struct RoomLobbyView: View {
    let room: GameRoom

    @Environment(FriendsStore.self) private var friends
    @State private var starting = false
    @State private var error: String?
    @State private var confirmingLeave = false

    private var isHost: Bool { room.host == friends.uid }
    private var hostName: String { room.names.first ?? "" }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 14) {
                        if isHost { LobbyStepBar(step: step) }
                        seats
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))

                inviteSection
                gameSection
                if room.game == .durak { rulesSection }
                codeSection
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .bottom) { footer }
            .navigationTitle(L10n.text("Game room"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("Leave")) {
                        if isHost && room.players.count > 1 { confirmingLeave = true } else { friends.leaveRoom() }
                    }
                }
            }
            .alert(L10n.text("Close the room?"), isPresented: $confirmingLeave) {
                Button(L10n.text("Close room"), role: .destructive) { friends.leaveRoom() }
                Button(L10n.text("Cancel"), role: .cancel) {}
            } message: {
                Text(L10n.text("Everyone in it will be sent back."))
            }
        }
        .animation(.snappy, value: room)
        .animation(.snappy, value: friends.sentInvites)
    }

    // MARK: Steps

    private var step: LobbyStepBar.Step {
        if room.canStart { return .start }
        let waiting = friends.sentInvites.values.contains { $0.status == .pending && $0.isFresh(at: friends.clock) }
        return room.players.count > 1 || waiting ? .wait : .invite
    }

    // MARK: Seats

    /// Seats for the game picked, or for the room before a game is picked.
    private var seatCount: Int {
        min(room.maxPlayers, max(room.players.count, room.game?.playerRange.upperBound ?? room.maxPlayers))
    }

    private var seats: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Array(zip(room.players, room.names)), id: \.0) { uid, name in
                seat(uid: uid, name: name)
                    .transition(.scale.combined(with: .opacity))
            }
            ForEach(0..<max(0, seatCount - room.players.count), id: \.self) { _ in
                VStack(spacing: 4) {
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .overlay { Image(systemName: "plus").foregroundStyle(.secondary) }
                    // Keeps the row aligned with the names under taken seats.
                    Text(" ").font(.caption2)
                }
                .frame(width: 52)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.text("Free seat"))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func seat(uid: String, name: String) -> some View {
        let isMe = uid == friends.uid
        let profile = isMe ? friends.me : friends.friends.first { $0.id == uid }
        return VStack(spacing: 4) {
            Group {
                if let profile {
                    FriendAvatar(profile: profile, online: nil, size: 44)
                } else {
                    Text(name.first.map { String($0).uppercased() } ?? "?")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(GameTheme.accent.gradient, in: Circle())
                }
            }
            .overlay(alignment: .topTrailing) {
                if uid == room.host {
                    Image(systemName: "crown.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .offset(x: 4, y: -4)
                }
            }
            Text(isMe ? L10n.text("You") : name)
                .font(.caption2.weight(isMe ? .semibold : .regular))
                .lineLimit(1)
        }
        .frame(width: 52)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(uid == room.host ? L10n.format("%@, host", name) : name)
    }

    // MARK: Invites

    @ViewBuilder
    private var inviteSection: some View {
        Section {
            if friends.friends.isEmpty {
                Text(L10n.text("Add friends on the Friends tab, or share the code."))
                    .foregroundStyle(.secondary)
            }
            ForEach(friends.friends) { friend in
                inviteRow(friend)
            }
        } header: {
            Text(L10n.text("Invite friends"))
        } footer: {
            if !friends.friends.isEmpty {
                Text(L10n.text("Friends get an invite at the top of their screen."))
            }
        }
    }

    private enum InviteStatus {
        case inRoom, invitesOff, open, waiting(GameInvite), noAnswer, declined, invitedByOther
    }

    private func status(of friend: FriendProfile) -> InviteStatus {
        if room.players.contains(friend.id) { return .inRoom }
        if !friend.privacy.allowInvites { return .invitesOff }
        if let sent = friends.sentInvites[friend.id] {
            switch sent.status {
            case .pending: return sent.isFresh(at: friends.clock) ? .waiting(sent) : .noAnswer
            case .declined: return .declined
            default: return .noAnswer
            }
        }
        return room.invited.contains(friend.id) ? .invitedByOther : .open
    }

    private func inviteRow(_ friend: FriendProfile) -> some View {
        let status = status(of: friend)
        return HStack(spacing: 12) {
            FriendAvatar(profile: friend, online: friend.privacy.showOnline ? friend.isOnline : nil, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.name).font(.body.weight(.medium)).lineLimit(1)
                statusLine(status, friend: friend)
                    .font(.subheadline)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            inviteControl(status, friend: friend)
        }
    }

    @ViewBuilder
    private func statusLine(_ status: InviteStatus, friend: FriendProfile) -> some View {
        switch status {
        case .inRoom: Text(L10n.text("In the room")).foregroundStyle(.green)
        case .waiting(let invite):
            Text(L10n.format("Invited · %@", inviteTimeLeft(invite, now: friends.clock))).foregroundStyle(.secondary)
        case .noAnswer: Text(L10n.text("Didn't answer")).foregroundStyle(.orange)
        case .declined: Text(L10n.text("Can't play right now")).foregroundStyle(.orange)
        case .invitedByOther: Text(L10n.text("Already invited")).foregroundStyle(.secondary)
        case .invitesOff, .open:
            Text(friend.presenceText)
                .foregroundStyle(friend.privacy.showOnline && friend.isOnline ? .green : .secondary)
        }
    }

    @ViewBuilder
    private func inviteControl(_ status: InviteStatus, friend: FriendProfile) -> some View {
        switch status {
        case .inRoom:
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.green)
                .accessibilityLabel(L10n.text("In the room"))
        case .invitesOff:
            Text(L10n.text("No invites"))
                .font(.caption)
                .foregroundStyle(.secondary)
        case .waiting:
            Text(L10n.text("Waiting…"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: Capsule())
        case .open:
            inviteButton(L10n.text("Invite"), friend: friend, prominent: true)
        case .noAnswer, .declined, .invitedByOther:
            inviteButton(L10n.text("Invite again"), friend: friend, prominent: false)
        }
    }

    private func inviteButton(_ title: String, friend: FriendProfile, prominent: Bool) -> some View {
        Button {
            Haptics.tap()
            friends.inviteToRoom(friend)
        } label: {
            Text(title).font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(prominent ? GameTheme.accent : GameTheme.accent.opacity(0.15))
        .foregroundStyle(prominent ? Color.white : GameTheme.accent)
        .controlSize(.small)
        .disabled(room.isFull)
    }

    // MARK: Game

    /// The host picks the next game; the others see the pick.
    @ViewBuilder
    private var gameSection: some View {
        Section {
            if isHost {
                ForEach(GameID.multiplayer) { game in
                    Button {
                        Haptics.tap()
                        friends.setRoomGame(game)
                    } label: {
                        gameRow(game)
                    }
                    .buttonStyle(.plain)
                }
            } else if let game = room.game {
                gameRow(game)
            } else {
                Text(L10n.format("%@ hasn't picked a game yet.", hostName))
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(L10n.text("Game"))
        } footer: {
            Text(L10n.text(isHost ? "Pick a game. After the match everyone comes back here for the next one."
                                  : "The host picks the game."))
        }
    }

    private func gameRow(_ game: GameID) -> some View {
        let selected = room.game == game
        let fits = game.playerRange.contains(room.players.count)
        return HStack(spacing: 12) {
            GamePreviewArt(gameID: game, fade: false)
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(game.info.title).font(.body.weight(.medium))
                Text(game.playerCountText)
                    .font(.subheadline)
                    .foregroundStyle(fits || room.players.count < game.playerRange.lowerBound ? Color.secondary : Color.orange)
            }
            Spacer()
            if isHost {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? GameTheme.accent : Color.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Rules

    /// The host sets the optional rules; everyone else sees what they'll play by.
    private var rulesSection: some View {
        Section {
            DurakRuleToggles(transfer: binding(\.transfer), bluff: binding(\.bluff), editable: isHost)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        } header: {
            Text(L10n.text("Rules"))
        } footer: {
            if !isHost { Text(L10n.text("The host chooses the rules.")) }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<DurakOptions, Bool>) -> Binding<Bool> {
        Binding(get: { room.options[keyPath: keyPath] },
                set: { value in
                    var options = room.options
                    options[keyPath: keyPath] = value
                    friends.setRoomOptions(options)
                })
    }

    // MARK: Code

    /// The fallback for anyone who isn't a friend yet: a link, or the code to type.
    private var codeSection: some View {
        Section {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text("Room code"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(room.code)
                        .font(.title2.monospaced().weight(.bold))
                        .tracking(3)
                        .textSelection(.enabled)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = room.code
                    Haptics.success()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .accessibilityLabel(L10n.text("Copy"))
                ShareLink(item: shareText) {
                    Label(L10n.text("Share"), systemImage: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
            }
        } header: {
            Text(L10n.text("Or send a link"))
        } footer: {
            Text(L10n.text("Anyone with the code can join from “Join by code”."))
        }
    }

    private var shareText: String {
        L10n.format("Join my game room in PuzzleBox! Code: %@", room.code) + "\n" + RoomLink.url(code: room.code).absoluteString
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 8) {
            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            if isHost {
                Text(startHint)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button(action: start) {
                    Group {
                        if starting { ProgressView().tint(.white) }
                        else if let game = room.game {
                            Text(L10n.format("Play %@ (%d)", game.info.title, room.players.count))
                        } else { Text(L10n.format("Start game (%d)", room.players.count)) }
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(room.canStart ? GameTheme.accent : Color.gray, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!room.canStart || starting)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(L10n.format("Waiting for %@ to start…", hostName))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .background(.bar)
    }

    private var startHint: String {
        guard let game = room.game else { return L10n.text("Pick a game to play.") }
        if room.players.count > game.playerRange.upperBound {
            return L10n.format("%@ is for up to %d players.", game.info.title, game.playerRange.upperBound)
        }
        if room.players.count < game.playerRange.lowerBound { return L10n.text("Invite a friend to start.") }
        if room.isFull || room.players.count == game.playerRange.upperBound { return L10n.text("Everyone's here.") }
        return L10n.text("Wait for everyone, or start with the players already here.")
    }

    private func start() {
        starting = true
        error = nil
        Task {
            do {
                try await friends.startRoom()
                Haptics.success()
            } catch {
                self.error = error.localizedDescription
            }
            starting = false
        }
    }
}

/// Invite → Wait → Start, with the current step lit.
struct LobbyStepBar: View {
    enum Step: Int, CaseIterable {
        case invite, wait, start

        var title: String {
            switch self {
            case .invite: L10n.text("Invite")
            case .wait: L10n.text("Wait")
            case .start: L10n.text("Start")
            }
        }
    }

    let step: Step

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { item in
                let done = item.rawValue < step.rawValue
                let color: Color = done ? .green : item == step ? GameTheme.accent : Color(.systemGray4)
                VStack(alignment: .leading, spacing: 5) {
                    Capsule().fill(color).frame(height: 4)
                    HStack(spacing: 4) {
                        if done { Image(systemName: "checkmark") }
                        Text("\(item.rawValue + 1). \(item.title)")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.rawValue > step.rawValue ? Color.secondary : color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.format("Step %d of 3: %@", step.rawValue + 1, step.title))
    }
}

/// `oina://room/K7PX2Q`: a link that opens the app and joins the room.
enum RoomLink {
    static let scheme = "oina"

    static func url(code: String) -> URL {
        URL(string: "\(scheme)://room/\(code)")!
    }

    static func code(in url: URL) -> String? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == "room",
              let code = url.pathComponents.last(where: { $0 != "/" }), code.count >= 4 else { return nil }
        return code
    }
}

// MARK: - Presentation

extension View {
    /// Shows the lobby over this view while the player is in a room. Attached
    /// to the tabs and to the game cover, like the invite banner, so it shows
    /// whatever is on screen.
    func roomLobby() -> some View {
        modifier(RoomLobbyPresenter())
    }
}

private struct RoomLobbyPresenter: ViewModifier {
    @Environment(FriendsStore.self) private var friends

    func body(content: Content) -> some View {
        @Bindable var friends = friends
        content
            .overlay {
                // A game room waits behind its match until the match is closed.
                if let room = friends.room, !friends.inRoomMatch {
                    RoomLobbyView(room: room)
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(.spring(duration: 0.4), value: friends.inRoomMatch ? nil : friends.room?.id)
            .alert(L10n.text("Room"), isPresented: Binding(get: { friends.roomNotice != nil },
                                                           set: { if !$0 { friends.roomNotice = nil } })) {
                Button(L10n.text("OK"), role: .cancel) {}
            } message: {
                Text(friends.roomNotice ?? "")
            }
    }
}
