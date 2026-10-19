import SwiftUI

/// Playing with people nearby, no internet: open a room on this phone, or
/// join one found nearby; then the same lobby as online rooms.
struct NearbyRoomView: View {
    let game: GameID

    @Environment(NearbyStore.self) private var nearby
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let lobby = nearby.lobby {
                    lobbySections(lobby)
                } else {
                    findSections
                }
            }
            .listStyle(.insetGrouped)
            .safeAreaInset(edge: .bottom) {
                if let lobby = nearby.lobby { footer(lobby) }
            }
            .navigationTitle(L10n.text("Nearby"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(nearby.lobby == nil ? "Close" : "Leave")) {
                        if nearby.lobby == nil { dismiss() } else { nearby.leave() }
                    }
                }
            }
            .alert(L10n.text("Nearby"), isPresented: Binding(get: { nearby.notice != nil },
                                                             set: { if !$0 { nearby.notice = nil } })) {
                Button(L10n.text("OK"), role: .cancel) {}
            } message: {
                Text(nearby.notice ?? "")
            }
            .animation(.snappy, value: nearby.lobby)
            .animation(.snappy, value: nearby.rooms)
        }
        .onAppear {
            nearby.look()
            AppAnalytics.screen("nearby")
        }
        .onDisappear {
            nearby.stopLooking()
            // Closed without starting: give the room up. A started game carries on.
            if nearby.matchState == nil && nearby.pendingMatch == nil { nearby.leave() }
        }
    }

    // MARK: Finding a room

    @ViewBuilder
    private var findSections: some View {
        Section {
            Button {
                Haptics.tap()
                nearby.host(game)
            } label: {
                Label(L10n.format("Open a %@ room", game.info.title), systemImage: "antenna.radiowaves.left.and.right")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        } footer: {
            Text(L10n.text("Phones connect directly over Bluetooth and Wi-Fi, no internet needed. In airplane mode, turn Bluetooth or Wi-Fi back on."))
        }

        Section(L10n.text("Rooms nearby")) {
            if nearby.rooms.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(L10n.text("Looking for rooms nearby…")).foregroundStyle(.secondary)
                }
            }
            ForEach(nearby.rooms) { room in
                Button {
                    Haptics.tap()
                    nearby.join(room)
                } label: {
                    HStack(spacing: 12) {
                        GamePreviewArt(gameID: room.game, fade: false)
                            .frame(width: 44, height: 44)
                            .clipShape(.rect(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(room.hostName).font(.body.weight(.semibold))
                            Text(L10n.format("%@ · %d/%d", room.game.info.title, room.players, room.maxPlayers))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if nearby.joining == room {
                            ProgressView()
                        } else {
                            Text(L10n.text("Join")).font(.subheadline.weight(.semibold)).foregroundStyle(GameTheme.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(nearby.joining != nil || room.players >= room.maxPlayers)
            }
        }
    }

    // MARK: Lobby

    @ViewBuilder
    private func lobbySections(_ lobby: NearbyLobby) -> some View {
        Section {
            ForEach(Array(lobby.players.enumerated()), id: \.element.id) { index, player in
                HStack(spacing: 12) {
                    Text(player.name.first.map { String($0).uppercased() } ?? "?")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(GameTheme.accent.gradient, in: Circle())
                    Text(player.id == nearby.me.id ? L10n.format("%@ (you)", player.name) : player.name)
                    Spacer()
                    if index == 0 {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(.yellow)
                            .accessibilityLabel(L10n.text("Host"))
                    }
                }
            }
            ForEach(0..<max(0, lobby.maxPlayers - lobby.players.count), id: \.self) { _ in
                HStack(spacing: 12) {
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                    Text(L10n.text("Free seat")).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(L10n.format("Players %d/%d", lobby.players.count, lobby.maxPlayers))
        } footer: {
            if nearby.isHost {
                Text(L10n.text("Others open the same game, tap “Nearby, no internet” and pick your room."))
            }
        }

        if lobby.gameID == .durak {
            Section {
                DurakRuleToggles(transfer: binding(\.transfer, in: lobby), bluff: binding(\.bluff, in: lobby),
                                 editable: nearby.isHost)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                Text(L10n.text("Rules"))
            } footer: {
                if !nearby.isHost { Text(L10n.text("The host chooses the rules.")) }
            }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<DurakOptions, Bool>, in lobby: NearbyLobby) -> Binding<Bool> {
        Binding(get: { lobby.options[keyPath: keyPath] },
                set: { value in
                    var options = lobby.options
                    options[keyPath: keyPath] = value
                    nearby.setOptions(options)
                })
    }

    private func footer(_ lobby: NearbyLobby) -> some View {
        VStack(spacing: 8) {
            if nearby.isHost {
                Text(lobby.canStart ? (lobby.isFull ? L10n.text("Everyone's here.")
                                                    : L10n.text("Wait for everyone, or start with the players already here."))
                                    : L10n.text("Waiting for players to join…"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    Haptics.success()
                    nearby.start()
                } label: {
                    Text(L10n.format("Start game (%d)", lobby.players.count))
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(lobby.canStart ? GameTheme.accent : Color.gray, in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!lobby.canStart)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(L10n.format("Waiting for %@ to start…", lobby.players.first?.name ?? ""))
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
}
