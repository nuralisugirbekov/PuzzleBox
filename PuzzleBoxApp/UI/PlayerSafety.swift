import SwiftUI

// Reporting and blocking other players, and managing blocked players.

private struct PlayerSafetyModifier: ViewModifier {
    let id: String
    let name: String
    let context: String
    @Binding var reporting: Bool
    @Binding var blocking: Bool
    let onBlocked: () -> Void

    @Environment(FriendsStore.self) private var friends
    @State private var thanks = false

    func body(content: Content) -> some View {
        content
            .confirmationDialog(L10n.format("Why are you reporting %@?", name), isPresented: $reporting, titleVisibility: .visible) {
                ForEach(ReportReason.allCases) { reason in
                    Button(reason.title) {
                        friends.report(id, name: name, reason: reason, context: context)
                        thanks = true
                    }
                }
                Button(L10n.text("Cancel"), role: .cancel) {}
            }
            .alert(L10n.format("Block %@?", name), isPresented: $blocking) {
                Button(L10n.text("Block"), role: .destructive) {
                    friends.block(id, name: name)
                    Haptics.success()
                    onBlocked()
                }
                Button(L10n.text("Cancel"), role: .cancel) {}
            } message: {
                Text(L10n.text("They are removed from your friends and can't send you invites. You can unblock them in your profile."))
            }
            .alert(L10n.text("Thanks, we'll review it."), isPresented: $thanks) {
                Button(L10n.text("OK"), role: .cancel) {}
            }
    }
}

extension View {
    /// Report and block dialogs for another player, driven by the two bindings.
    func playerSafety(id: String, name: String, context: String, reporting: Binding<Bool>,
                      blocking: Binding<Bool>, onBlocked: @escaping () -> Void = {}) -> some View {
        modifier(PlayerSafetyModifier(id: id, name: name, context: context, reporting: reporting,
                                      blocking: blocking, onBlocked: onBlocked))
    }
}

/// A player in a lobby, with a menu to report or block them.
struct LobbyPlayerRow: View {
    let id: String
    let name: String
    let isHost: Bool
    let isMe: Bool

    @State private var reporting = false
    @State private var blocking = false

    var body: some View {
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
            if !isMe {
                Menu {
                    Button(L10n.text("Report"), systemImage: "exclamationmark.bubble") { reporting = true }
                    Button(L10n.text("Block"), systemImage: "hand.raised", role: .destructive) { blocking = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel(L10n.text("Report or block"))
            }
        }
        .transition(.move(edge: .leading).combined(with: .opacity))
        .playerSafety(id: id, name: name, context: "room", reporting: $reporting, blocking: $blocking)
    }
}

/// Blocked players, each with a way to unblock.
struct BlockedPlayersView: View {
    @Environment(FriendsStore.self) private var friends

    var body: some View {
        List {
            if friends.blocked.isEmpty {
                ContentUnavailableView(L10n.text("No blocked players"), systemImage: "hand.raised")
                    .listRowBackground(Color.clear)
            }
            ForEach(friends.blocked) { player in
                HStack {
                    Text(player.name.isEmpty ? L10n.text("Player") : player.name)
                    Spacer()
                    Button(L10n.text("Unblock")) { friends.unblock(player.id) }
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L10n.text("Blocked players"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
