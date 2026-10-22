import SwiftUI

// MARK: - Friends tab

/// The player, their friend code and their friends with live online status.
struct FriendsView: View {
    @Environment(FriendsStore.self) private var friends
    @State private var addingFriend = false
    @State private var joiningRoom = false
    @State private var creatingRoom = false
    @State private var roomError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TabHeader(title: L10n.text("Friends")) {
                    HeaderCircleButton(symbol: "person.badge.plus", label: L10n.text("Add a friend")) {
                        addingFriend = true
                    }
                    .disabled(friends.status != .ready)
                }
                content
            }
            .background(Color(.systemGroupedBackground))
            .tabRoot(title: L10n.text("Friends"))
            .sheet(isPresented: $addingFriend) { AddFriendView() }
            .sheet(isPresented: $joiningRoom) { JoinRoomView() }
        }
        .task { await friends.start() }
    }

    @ViewBuilder
    private var content: some View {
        switch friends.status {
        case .idle, .connecting:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable(let message):
            ContentUnavailableView {
                Label(L10n.text("Friends unavailable"), systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button(L10n.text("Try Again")) { Task { await friends.start() } }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        case .ready:
            list
        }
    }

    private var list: some View {
        List {
            if let me = friends.me {
                Section(L10n.text("Me")) {
                    NavigationLink {
                        MyProfileView()
                    } label: {
                        FriendRow(profile: me, isMe: true)
                    }
                    LabeledContent(L10n.text("Friend code")) {
                        HStack(spacing: 12) {
                            Text(me.code)
                                .font(.body.monospaced().weight(.semibold))
                                .textSelection(.enabled)
                            ShareLink(item: L10n.format("Add me in PuzzleBox! My friend code: %@", me.code)) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .accessibilityLabel(L10n.text("Share"))
                        }
                    }
                    NavigationLink {
                        RatingContent()
                    } label: {
                        Label(L10n.text("Your Records"), systemImage: "trophy")
                    }
                }
            }

            gameRoomSection

            Section {
                if friends.friends.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.2")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text(L10n.text("No friends yet"))
                            .font(.headline)
                        Text(L10n.text("Share your code or add a friend by theirs to play together."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    ForEach(friends.friends) { friend in
                        NavigationLink {
                            FriendProfileView(friendID: friend.id)
                        } label: {
                            FriendRow(profile: friend)
                        }
                        .swipeActions {
                            Button(L10n.text("Remove"), role: .destructive) {
                                friends.removeFriend(friend)
                            }
                        }
                    }
                }
                Button { addingFriend = true } label: {
                    Label(L10n.text("Add a friend"), systemImage: "person.badge.plus")
                        .font(.headline)
                }
            } header: {
                Text(L10n.text("Friends"))
            }
        }
        .listStyle(.insetGrouped)
        .animation(.snappy, value: friends.friends.map(\.id))
    }

    /// A room to play several games with friends, the game picked inside it.
    private var gameRoomSection: some View {
        Section {
            Button(action: createGameRoom) {
                HStack(spacing: 12) {
                    Image(systemName: "person.3.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(GameTheme.accent.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text("Create a game room"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(GameID.multiplayer.map(\.info.title).joined(separator: ", "))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if creatingRoom { ProgressView() }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(creatingRoom)
            Button { joiningRoom = true } label: {
                Label(L10n.text("Join a room"), systemImage: "number")
            }
        } header: {
            Text(L10n.text("Play together"))
        } footer: {
            if let roomError {
                Text(roomError).foregroundStyle(.red)
            } else {
                Text(L10n.text("Invite friends, then pick a game. After each match you're back in the room."))
            }
        }
    }

    private func createGameRoom() {
        guard !creatingRoom else { return }
        Haptics.tap()
        creatingRoom = true
        roomError = nil
        Task {
            do {
                try await friends.createRoom(for: nil)
            } catch {
                roomError = error.localizedDescription
            }
            creatingRoom = false
        }
    }
}

/// Avatar with an online dot, the name and the presence line.
struct FriendRow: View {
    let profile: FriendProfile
    var isMe = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            HStack(spacing: 12) {
                FriendAvatar(profile: profile, online: isMe || profile.privacy.showOnline ? isMe || profile.isOnline : nil)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(!isMe && profile.privacy.showOnline && profile.isOnline ? .green : .secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)

            }
            .contentShape(.rect)
        }
    }

    private var subtitle: String {
        if isMe { return profile.bio.isEmpty ? L10n.text("My profile") : profile.bio }
        return profile.presenceText
    }
}

struct FriendAvatar: View {
    let profile: FriendProfile
    /// Nil hides the presence dot (a status the player keeps private).
    let online: Bool?
    var size: CGFloat = 44

    static let palette: [Color] = [.blue, .orange, .pink, .purple, .teal, .indigo, .green, .red]

    /// The colour the player picked, or one derived from their id.
    static func tint(for profile: FriendProfile) -> Color {
        if let color = profile.color, palette.indices.contains(color) { return palette[color] }
        let hash = profile.id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }

    var body: some View {
        Group {
            if let emoji = profile.emoji {
                Text(emoji).font(.system(size: size * 0.55))
            } else {
                Text(profile.initial)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .background(Self.tint(for: profile).gradient, in: Circle())
        .overlay(alignment: .bottomTrailing) {
            if let online {
                Circle()
                    .fill(online ? Color.green : Color(.systemGray3))
                    .frame(width: size * 0.3, height: size * 0.3)
                    .overlay { Circle().strokeBorder(Color(.systemBackground), lineWidth: 2) }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Add friend

struct AddFriendView: View {
    @Environment(FriendsStore.self) private var friends
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isAdding = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.text("Friend code"), text: $code)
                        .font(.title3.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .onSubmit(add)
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text(L10n.text("Ask your friend for the code on their Friends tab."))
                    }
                }
                if let me = friends.me {
                    Section(L10n.text("Your code")) {
                        HStack {
                            Text(me.code).font(.title3.monospaced().weight(.semibold))
                            Spacer()
                            ShareLink(item: L10n.format("Add me in PuzzleBox! My friend code: %@", me.code)) {
                                Label(L10n.text("Share"), systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }
            .navigationTitle(L10n.text("Add a friend"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isAdding {
                        ProgressView()
                    } else {
                        Button(L10n.text("Add"), action: add)
                            .disabled(code.trimmingCharacters(in: .whitespaces).count < 4)
                    }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private func add() {
        guard !isAdding else { return }
        isAdding = true
        error = nil
        Task {
            do {
                try await friends.addFriend(code: code)
                Haptics.success()
                dismiss()
            } catch {
                Haptics.error()
                self.error = error.localizedDescription
            }
            isAdding = false
        }
    }
}

// MARK: - Choosing an opponent

/// Shown when a multiplayer game is opened: play the bots right away, open a
/// room and invite friends, or join a friend's room by its code.
struct OpponentPickerView: View {
    let game: GameID
    let playBot: () -> Void

    @Environment(FriendsStore.self) private var friends
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DurakEngine.botCountKey) private var botCount = 1
    @AppStorage(DurakOptions.transferKey) private var transfer = false
    @AppStorage(DurakOptions.bluffKey) private var bluff = false
    @State private var joining = false
    @State private var nearbyShown = false
    @State private var creating = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    GamePreviewArt(gameID: game, fade: false)
                        .frame(width: 96, height: 96)
                        .clipShape(.rect(cornerRadius: 20))
                        .padding(.bottom, 8)
                    if game == .durak {
                        botPicker
                        DurakRuleToggles(transfer: $transfer, bluff: $bluff)
                    }
                    modeButton(game == .gemsBlitz ? L10n.text("Play solo") : L10n.text("vs Bot"),
                               symbol: game == .gemsBlitz ? "person.fill" : "cpu", prominent: true) {
                        AppAnalytics.log("opponent_selected", parameters: ["game_id": game.rawValue, "mode": "bot"])
                        playBot()
                    }
                    modeButton(L10n.text("Create a room"), symbol: "person.3.fill", prominent: false, busy: creating) {
                        AppAnalytics.log("opponent_selected", parameters: ["game_id": game.rawValue, "mode": "room"])
                        createRoom()
                    }
                    modeButton(L10n.text("Join by code"), symbol: "number", prominent: false) {
                        joining = true
                    }
                    modeButton(L10n.text("Nearby, no internet"), symbol: "antenna.radiowaves.left.and.right",
                               prominent: false) {
                        AppAnalytics.log("opponent_selected", parameters: ["game_id": game.rawValue, "mode": "nearby"])
                        nearbyShown = true
                    }
                    Text(game.playerRange.count == 1
                         ? L10n.format("%d players. Invite a friend or share the room code.", game.playerRange.lowerBound)
                         : L10n.format("%d–%d players. Invite friends or share the room code.",
                                       game.playerRange.lowerBound, game.playerRange.upperBound))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if let error {
                        Text(error).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                }
                .padding(24)
            }
            .navigationTitle(game.info.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("Close")) { dismiss() }
                }
            }
            .sheet(isPresented: $joining) { JoinRoomView() }
            .sheet(isPresented: $nearbyShown) { NearbyRoomView(game: game) }
        }
        .presentationDetents([.medium, .large])
        .task { await friends.start() }
        // Joining by code from here: the lobby takes over.
        .onChange(of: friends.room?.id) { _, id in if id != nil { dismiss() } }
    }

    private var botPicker: some View {
        VStack(spacing: 6) {
            Text(L10n.text("Bots at the table"))
                .font(.subheadline.weight(.semibold))
            Picker(L10n.text("Bots at the table"), selection: $botCount) {
                ForEach(1..<DurakState.playerRange.upperBound, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(.bottom, 4)
    }

    private func createRoom() {
        guard !creating else { return }
        creating = true
        error = nil
        Task {
            do {
                try await friends.createRoom(for: game)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            creating = false
        }
    }

    private func modeButton(_ title: String, symbol: String, prominent: Bool, busy: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if busy { ProgressView() } else { Label(title, systemImage: symbol) }
            }
            .font(.headline)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(prominent ? AnyShapeStyle(GameTheme.accent) : AnyShapeStyle(Color(.tertiarySystemFill)),
                        in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Durak rules

/// The optional Durak rules, one switch each, with what they mean.
struct DurakRuleToggles: View {
    @Binding var transfer: Bool
    @Binding var bluff: Bool
    var editable = true

    var body: some View {
        VStack(spacing: 0) {
            toggle(L10n.text("Card transfers"), symbol: "arrow.uturn.right",
                   detail: L10n.text("Before beating anything, the defender may add a card of the same rank and pass the attack on."),
                   isOn: $transfer)
            Divider().padding(.leading, 44)
            toggle(L10n.text("Bluffing"), symbol: "theatermasks",
                   detail: L10n.text("Cards may be played against the rules. Tap a card on the table to call a bluff: the bluffer takes the table, but a wrong call makes you take it."),
                   isOn: $bluff)
        }
        .padding(.vertical, 4)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func toggle(_ title: String, symbol: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(GameTheme.accent)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(GameTheme.accent)
        .disabled(!editable)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

// MARK: - Join a room

/// Type a room code a friend shared to take a seat in their room.
struct JoinRoomView: View {
    @Environment(FriendsStore.self) private var friends
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var isJoining = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L10n.text("Room code"), text: $code)
                        .font(.title3.monospaced())
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .onSubmit(join)
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    } else {
                        Text(L10n.text("Ask the host for the code shown in their room."))
                    }
                }
            }
            .navigationTitle(L10n.text("Join a room"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isJoining {
                        ProgressView()
                    } else {
                        Button(L10n.text("Join"), action: join)
                            .disabled(code.trimmingCharacters(in: .whitespaces).count < 4)
                    }
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
        .task { await friends.start() }
    }

    private func join() {
        guard !isJoining else { return }
        isJoining = true
        error = nil
        Task {
            do {
                try await friends.joinRoom(code: code)
                Haptics.success()
                dismiss()
            } catch {
                Haptics.error()
                self.error = error.localizedDescription
            }
            isJoining = false
        }
    }
}

// MARK: - Incoming invite banner

/// A friend's invite, pinned to the top of whatever screen is showing.
struct InviteBanner: View {
    let invite: GameInvite
    let accept: () -> Void
    let decline: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let game = invite.game {
                    GamePreviewArt(gameID: game, fade: false)
                } else {
                    Image(systemName: "person.3.fill")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(GameTheme.accent.gradient)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(.rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(invite.fromName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(invite.game.map { L10n.format("invites you to play %@", $0.info.title) }
                     ?? L10n.text("invites you to a game room"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button(action: decline) {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("Decline"))
            Button(action: accept) {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.green, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.text("Accept"))
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        .padding(.horizontal, 12)
        .accessibilityElement(children: .contain)
    }
}

extension View {
    /// Shows the newest incoming invite at the top of this view.
    func incomingInviteBanner() -> some View {
        modifier(IncomingInviteBanner())
    }
}

private struct IncomingInviteBanner: ViewModifier {
    @Environment(FriendsStore.self) private var friends

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let invite = friends.incomingInvite {
                InviteBanner(invite: invite,
                             accept: { Task { await friends.accept(invite) } },
                             decline: { friends.decline(invite) })
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        Haptics.success()
                        SoundFX.play(.coin)
                    }
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.25), value: friends.incomingInvite?.id)
    }
}
