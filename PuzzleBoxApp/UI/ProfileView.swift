import SwiftUI

// MARK: - My profile

/// The player's own profile: how friends see them, their stats, and what
/// they share.
struct MyProfileView: View {
    @Environment(FriendsStore.self) private var friends
    @Environment(StatsStore.self) private var stats
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var deleting = false
    @State private var deleteResult: String?

    var body: some View {
        List {
            if let me = friends.me {
                Section {
                    ProfileHeader(profile: me, presence: nil)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }

                Section(L10n.text("Friend code")) {
                    HStack(spacing: 12) {
                        Text(me.code)
                            .font(.title3.monospaced().weight(.semibold))
                            .textSelection(.enabled)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = me.code
                            Haptics.success()
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .accessibilityLabel(L10n.text("Copy"))
                        ShareLink(item: L10n.format("Add me in Oina Games! My friend code: %@", me.code)) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .accessibilityLabel(L10n.text("Share"))
                    }
                    .buttonStyle(.borderless)
                }

                Section {
                    ProfileStatsView(stats: PublicStats(stats: stats))
                    NavigationLink {
                        RatingContent()
                    } label: {
                        Label(L10n.text("Your Records"), systemImage: "trophy")
                    }
                } header: {
                    Text(L10n.text("Statistics"))
                } footer: {
                    if !me.privacy.showStats { Text(L10n.text("Only you can see your statistics.")) }
                }

                PrivacySection(privacy: me.privacy) { privacy in
                    friends.setPrivacy(privacy, stats: PublicStats(stats: stats))
                }

                Section {
                    NavigationLink {
                        BlockedPlayersView()
                    } label: {
                        Label(L10n.text("Blocked players"), systemImage: "hand.raised")
                            .badge(friends.blocked.count)
                    }
                    Link(destination: URL(string: "mailto:taimanovb@gmail.com")!) {
                        Label(L10n.text("Contact us"), systemImage: "envelope")
                    }
                } header: {
                    Text(L10n.text("Safety"))
                } footer: {
                    Text(L10n.text("Report a player from their profile or from a room's player list."))
                }

                Section {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        if deleting { ProgressView() } else { Label(L10n.text("Delete account"), systemImage: "trash") }
                    }
                    .disabled(deleting)
                } header: {
                    Text(L10n.text("Account"))
                } footer: {
                    Text(L10n.text("Removes your profile, friends and online data from our servers. Progress on this phone stays."))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.text("Profile"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(L10n.text("Edit")) { editing = true }
            }
        }
        .sheet(isPresented: $editing) { EditProfileView() }
        .alert(L10n.text("Delete account and data?"), isPresented: $confirmingDelete) {
            Button(L10n.text("Delete"), role: .destructive) {
                deleting = true
                Task {
                    do {
                        try await friends.deleteAccount()
                        deleteResult = L10n.text("Account deleted.")
                    } catch {
                        deleteResult = L10n.text("Couldn't delete the account. Check your connection and try again.")
                    }
                    deleting = false
                }
            }
            Button(L10n.text("Cancel"), role: .cancel) {}
        } message: {
            Text(L10n.text("Your profile, friends and online data are removed. This can't be undone."))
        }
        .alert(deleteResult ?? "", isPresented: Binding(get: { deleteResult != nil }, set: { if !$0 { deleteResult = nil } })) {
            Button(L10n.text("OK"), role: .cancel) {}
        }
        .onAppear { AppAnalytics.screen("profile") }
    }
}

// MARK: - Header

/// Big avatar, name, the line about the player and how long they've played.
struct ProfileHeader: View {
    let profile: FriendProfile
    /// The presence line, or nil on the player's own profile.
    let presence: String?

    var body: some View {
        VStack(spacing: 8) {
            FriendAvatar(profile: profile,
                         online: presence == nil ? nil : (profile.privacy.showOnline ? profile.isOnline : nil),
                         size: 96)
            Text(profile.name)
                .font(.title2.weight(.bold))
            if !profile.bio.isEmpty {
                Text(profile.bio)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let presence {
                Text(presence)
                    .font(.subheadline)
                    .foregroundStyle(profile.privacy.showOnline && profile.isOnline ? .green : .secondary)
            }
            if let since = profile.memberSince {
                Text(L10n.format("Playing since %@", since.formatted(
                    .dateTime.month(.wide).year().locale(Locale(identifier: L10n.language.rawValue)))))
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

// MARK: - Stats

/// Games played, tried and liked, and the most played games.
struct ProfileStatsView: View {
    let stats: PublicStats

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                tile(stats.played, L10n.text("Games played"), symbol: "play.fill", tint: .blue)
                tile(stats.tried, L10n.text("Games tried"), symbol: "checkmark.seal.fill", tint: .green)
                tile(stats.favorites, L10n.text("Favorites"), symbol: "heart.fill", tint: .pink)
            }
            if !stats.top.isEmpty {
                Text(L10n.text("Most played"))
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 10) {
                    ForEach(stats.top) { game in
                        VStack(spacing: 4) {
                            GamePreviewArt(gameID: game, fade: false)
                                .frame(width: 56, height: 56)
                                .clipShape(.rect(cornerRadius: 12))
                            Text(game.info.title)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func tile(_ value: Int, _ title: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text("\(value)").font(.title3.weight(.bold)).monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Privacy

/// One switch per thing the player can keep to themselves.
private struct PrivacySection: View {
    let privacy: ProfilePrivacy
    let change: (ProfilePrivacy) -> Void

    var body: some View {
        Section {
            toggle(L10n.text("Online status"), symbol: "circle.fill", \.showOnline)
            toggle(L10n.text("Last seen"), symbol: "clock", \.showLastSeen)
            toggle(L10n.text("Game statistics"), symbol: "chart.bar.fill", \.showStats)
            toggle(L10n.text("Friends list"), symbol: "person.2.fill", \.showFriends)
            toggle(L10n.text("Game invites"), symbol: "envelope.fill", \.allowInvites)
        } header: {
            Text(L10n.text("Privacy"))
        } footer: {
            Text(L10n.text("What you turn off isn't hidden in the app: it is never shared at all. Without invites, friends can still join your rooms by code."))
        }
    }

    private func toggle(_ title: String, symbol: String, _ keyPath: WritableKeyPath<ProfilePrivacy, Bool>) -> some View {
        Toggle(isOn: Binding(get: { privacy[keyPath: keyPath] },
                             set: { value in
                                 var next = privacy
                                 next[keyPath: keyPath] = value
                                 change(next)
                             })) {
            Label(title, systemImage: symbol)
        }
        .tint(GameTheme.accent)
    }
}

// MARK: - Edit profile

/// Name, a line about yourself, and an emoji avatar on a colour.
struct EditProfileView: View {
    @Environment(FriendsStore.self) private var friends
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var bio = ""
    @State private var emoji: String?
    @State private var color = 0
    @State private var loaded = false

    static let emojis = ["😀", "😎", "🤓", "🥳", "😺", "🐶", "🦊", "🐼", "🐸", "🦁", "🐯", "🐙",
                         "🦄", "🐲", "👾", "🤖", "👻", "🎃", "⭐️", "🔥", "⚡️", "🍀", "🍕", "🎲",
                         "♠️", "♥️", "🧩", "🎯", "🚀", "👑"]

    private var preview: FriendProfile? {
        guard var me = friends.me else { return nil }
        me.name = name.isEmpty ? me.name : name
        me.emoji = emoji
        me.color = color
        return me
    }

    var body: some View {
        NavigationStack {
            Form {
                if let preview {
                    Section {
                        FriendAvatar(profile: preview, online: nil, size: 88)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                }
                Section(L10n.text("Name")) {
                    TextField(L10n.text("Name"), text: $name)
                        .onChange(of: name) { name = String(name.prefix(24)) }
                }
                Section {
                    TextField(L10n.text("A few words about you"), text: $bio, axis: .vertical)
                        .lineLimit(2...3)
                        .onChange(of: bio) { bio = String(bio.prefix(FriendsStore.bioLimit)) }
                } header: {
                    Text(L10n.text("About me"))
                } footer: {
                    Text("\(bio.count)/\(FriendsStore.bioLimit)").monospacedDigit()
                }
                Section(L10n.text("Avatar")) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                        emojiCell(nil)
                        ForEach(Self.emojis, id: \.self) { emojiCell($0) }
                    }
                    .padding(.vertical, 4)
                    HStack(spacing: 10) {
                        ForEach(FriendAvatar.palette.indices, id: \.self) { index in
                            Button {
                                color = index
                            } label: {
                                Circle()
                                    .fill(FriendAvatar.palette[index].gradient)
                                    .frame(width: 30, height: 30)
                                    .overlay {
                                        if color == index {
                                            Circle().strokeBorder(Color.primary, lineWidth: 3).padding(-4)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L10n.format("Colour %d", index + 1))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle(L10n.text("Edit profile"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text("Cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text("Save")) {
                        friends.updateProfile(name: name, bio: bio, emoji: emoji, color: color)
                        Haptics.success()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard !loaded, let me = friends.me else { return }
                loaded = true
                name = me.name
                bio = me.bio
                emoji = me.emoji
                color = me.color ?? FriendAvatar.palette.firstIndex(of: FriendAvatar.tint(for: me)) ?? 0
            }
        }
    }

    /// An emoji choice; nil stands for the plain initial.
    private func emojiCell(_ choice: String?) -> some View {
        Button {
            emoji = choice
        } label: {
            Group {
                if let choice {
                    Text(choice).font(.title2)
                } else {
                    Text(friends.me?.initial ?? "A").font(.title3.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(emoji == choice ? GameTheme.accent.opacity(0.25) : Color(.tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - A friend's profile

/// A friend's profile, showing only what they share.
struct FriendProfileView: View {
    let friendID: String

    @Environment(FriendsStore.self) private var friends
    @Environment(\.dismiss) private var dismiss
    @State private var theirFriends: [FriendProfile]?
    @State private var loadFailed = false
    @State private var confirmingRemove = false
    @State private var reporting = false
    @State private var blocking = false

    private var friend: FriendProfile? { friends.friends.first { $0.id == friendID } }

    var body: some View {
        List {
            if let friend {
                Section {
                    TimelineView(.periodic(from: .now, by: 30)) { _ in
                        ProfileHeader(profile: friend, presence: friend.presenceText)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section(L10n.text("Statistics")) {
                    if let stats = friend.stats, friend.privacy.showStats {
                        ProfileStatsView(stats: stats)
                    } else {
                        hidden(L10n.format("%@ keeps their statistics private.", friend.name))
                    }
                }

                Section(L10n.text("Friends")) {
                    if !friend.privacy.showFriends {
                        hidden(L10n.format("%@ keeps their friends list private.", friend.name))
                    } else if let theirFriends {
                        if theirFriends.isEmpty {
                            Text(L10n.text("No friends yet")).foregroundStyle(.secondary)
                        }
                        ForEach(theirFriends) { other in
                            HStack {
                                FriendAvatar(profile: other, online: nil, size: 36)
                                Text(other.id == friends.uid ? L10n.format("%@ (you)", other.name) : other.name)
                                Spacer()
                                if friends.friends.contains(where: { $0.id == other.id }) {
                                    Text(L10n.text("Mutual"))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else if loadFailed {
                        hidden(L10n.text("Couldn't load the list."))
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }

                if !friend.privacy.allowInvites {
                    Section {
                        Label(L10n.text("Not accepting game invites"), systemImage: "envelope.badge.shield.half.filled")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button(L10n.text("Remove friend"), role: .destructive) { confirmingRemove = true }
                    Button(L10n.text("Report"), systemImage: "exclamationmark.bubble") { reporting = true }
                    Button(L10n.text("Block"), systemImage: "hand.raised", role: .destructive) { blocking = true }
                }
            } else {
                ContentUnavailableView(L10n.text("Not friends any more"), systemImage: "person.crop.circle.badge.xmark")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(friend?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: friend?.privacy.showFriends) { await loadFriends() }
        .alert(L10n.text("Remove friend?"), isPresented: $confirmingRemove) {
            Button(L10n.text("Remove"), role: .destructive) {
                if let friend { friends.removeFriend(friend) }
                dismiss()
            }
            Button(L10n.text("Cancel"), role: .cancel) {}
        }
        .playerSafety(id: friendID, name: friend?.name ?? "", context: "profile", reporting: $reporting,
                      blocking: $blocking) { dismiss() }
        .onAppear { AppAnalytics.screen("friend_profile") }
    }

    private func hidden(_ text: String) -> some View {
        Label(text, systemImage: "lock.fill")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private func loadFriends() async {
        guard let friend, friend.privacy.showFriends else { return }
        do {
            theirFriends = try await friends.friends(of: friend)
        } catch {
            loadFailed = true
        }
    }
}
