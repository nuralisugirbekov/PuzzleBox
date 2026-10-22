import SwiftUI

// MARK: - Lobby

/// The room this player is in, until the host starts the game: the code to
/// share, who has joined, invites for friends, and Start for the host.
struct RoomLobbyView: View {
    let room: GameRoom

    @Environment(FriendsStore.self) private var friends
    @State private var starting = false
    @State private var error: String?
    @State private var confirmingLeave = false

    private var isHost: Bool { room.host == friends.uid }
    private var hostName: String { room.names.first ?? "" }

    private var title: String {
        room.isSession ? L10n.text("Game room") : room.game?.info.title ?? ""
    }

    var body: some View {
        NavigationStack {
            List {
                Section { codeCard }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                if room.isSession { gameSection }

                Section {
                    ForEach(Array(zip(room.players, room.names)), id: \.0) { uid, name in
                        playerRow(name: name, isHost: uid == room.host, isMe: uid == friends.uid)
                    }
                    ForEach(0..<max(0, room.maxPlayers - room.players.count), id: \.self) { _ in
                        emptySeat
                    }
                } header: {
                    Text(L10n.format("Players %d/%d", room.players.count, room.maxPlayers))
                }

                if room.game == .durak { rulesSection }

                if isHost { inviteSection }
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .bottom) { footer }
            .navigationTitle(title)
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
    }

    // MARK: Code

    private var codeCard: some View {
        VStack(spacing: 10) {
            Group {
                if let game = room.game {
                    GamePreviewArt(gameID: game, fade: false)
                } else {
                    Image(systemName: "person.3.fill")
                        .font(.title)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(GameTheme.accent.gradient)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(.rect(cornerRadius: 14))
            Text(L10n.text("Room code"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(room.code)
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .tracking(4)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                Button {
                    UIPasteboard.general.string = room.code
                    Haptics.success()
                } label: {
                    Label(L10n.text("Copy"), systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                ShareLink(item: shareText) {
                    Label(L10n.text("Share"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
            .buttonBorderShape(.capsule)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var shareText: String {
        if room.isSession || room.game == nil {
            return L10n.format("Join my game room in PuzzleBox! Code: %@", room.code)
        }
        return L10n.format("Join my %@ room in PuzzleBox! Code: %@", room.game?.info.title ?? "", room.code)
    }

    // MARK: Game

    /// A game room's games: the host picks the next one, the rest see the pick.
    private var gameSection: some View {
        Section {
            ForEach(GameID.multiplayer) { game in
                Button {
                    Haptics.tap()
                    friends.setRoomGame(game)
                } label: {
                    gameRow(game)
                }
                .buttonStyle(.plain)
                .disabled(!isHost)
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
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(selected ? GameTheme.accent : Color.secondary.opacity(isHost ? 1 : 0))
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Players

    private func playerRow(name: String, isHost: Bool, isMe: Bool) -> some View {
        HStack(spacing: 12) {
            Text(name.first.map { String($0).uppercased() } ?? "?")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(GameTheme.accent.gradient, in: Circle())
            Text(isMe ? L10n.format("%@ (you)", name) : name)
                .font(.body.weight(isMe ? .semibold : .regular))
            Spacer()
            if isHost {
                Label(L10n.text("Host"), systemImage: "crown.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.yellow)
                    .accessibilityLabel(L10n.text("Host"))
            }
        }
        .transition(.move(edge: .leading).combined(with: .opacity))
    }

    private var emptySeat: some View {
        HStack(spacing: 12) {
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
            Text(L10n.text("Free seat"))
                .foregroundStyle(.secondary)
        }
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

    // MARK: Invites

    @ViewBuilder
    private var inviteSection: some View {
        Section {
            if friends.friends.isEmpty {
                Text(L10n.text("Add friends on the Friends tab, or share the code."))
                    .foregroundStyle(.secondary)
            }
            ForEach(friends.friends) { friend in
                HStack {
                    FriendRow(profile: friend)
                    inviteButton(for: friend)
                }
            }
        } header: {
            Text(L10n.text("Invite friends"))
        } footer: {
            Text(L10n.text("Friends get an invite at the top of their screen."))
        }
    }

    @ViewBuilder
    private func inviteButton(for friend: FriendProfile) -> some View {
        if room.players.contains(friend.id) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityLabel(L10n.text("In the room"))
        } else if !friend.privacy.allowInvites {
            Text(L10n.text("No invites"))
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            let invited = room.invited.contains(friend.id)
            Button {
                Haptics.tap()
                friends.inviteToRoom(friend)
            } label: {
                Text(L10n.text(invited ? "Invite again" : "Invite"))
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(invited ? .secondary : GameTheme.accent)
            .disabled(room.isFull)
        }
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
                        else if room.isSession, let game = room.game {
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
                .frame(minHeight: 52)
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
        if !room.canStart { return L10n.text("Waiting for players to join…") }
        if room.isFull { return L10n.text("Everyone's here.") }
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
