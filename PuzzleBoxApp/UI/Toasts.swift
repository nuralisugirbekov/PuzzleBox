import SwiftUI
import UIKit

// MARK: - Toast window

/// Invites and room news, shown in a window of their own above the app, so
/// they show over sheets and games alike. The window is only as tall as the
/// toasts and hidden while there are none, so it never blocks the app.
@MainActor
final class ToastWindow {
    static let shared = ToastWindow()

    private var window: UIWindow?
    private var hideTask: Task<Void, Never>?
    private var contentHeight: CGFloat = 0
    private var visible = false

    func install(friends: FriendsStore) {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let host = UIHostingController(rootView: ToastStack { [weak self] height in self?.resize(to: height) }
            .environment(friends))
        host.view.backgroundColor = .clear
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .statusBar
        window.backgroundColor = .clear
        window.rootViewController = host
        let theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: AppTheme.storageKey) ?? "") ?? .system
        window.overrideUserInterfaceStyle = theme.interfaceStyle
        window.isHidden = true
        self.window = window
    }

    func setVisible(_ visible: Bool) {
        guard let window else { return }
        self.visible = visible
        hideTask?.cancel()
        if visible {
            // Room to lay the toasts out; trimmed to their height once measured.
            layout(height: max(contentHeight, 200))
            window.isHidden = false
        } else {
            // Let the toast slide away first.
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(0.5))
                guard !Task.isCancelled, let self, !self.visible else { return }
                self.window?.isHidden = true
            }
        }
    }

    private func resize(to height: CGFloat) {
        contentHeight = height
        if visible, height > 0 { layout(height: height) }
    }

    private func layout(height: CGFloat) {
        guard let window, let scene = window.windowScene else { return }
        let top = scene.windows.first { $0 !== window }?.safeAreaInsets.top ?? window.safeAreaInsets.top
        window.frame = CGRect(x: 0, y: 0, width: scene.screen.bounds.width, height: top + height + 16)
    }
}

extension View {
    /// Puts up the toast window and shows it whenever there is a toast.
    func toasts() -> some View {
        modifier(ToastPresenter())
    }

    /// Closes this sheet once the player enters a room, so the lobby shows.
    func closesWhenRoomOpens() -> some View {
        modifier(ClosesWhenRoomOpens())
    }
}

private struct ToastPresenter: ViewModifier {
    @Environment(FriendsStore.self) private var friends

    private struct Shown: Equatable {
        var invite: String?
        var event: UUID?
    }

    func body(content: Content) -> some View {
        content
            .onAppear { ToastWindow.shared.install(friends: friends) }
            .onChange(of: Shown(invite: friends.toastInvite?.id, event: friends.roomEvent?.id), initial: true) { old, new in
                ToastWindow.shared.setVisible(new.invite != nil || new.event != nil)
                if let invite = new.invite, invite != old.invite {
                    Haptics.success()
                    SoundFX.play(.coin)
                }
            }
    }
}

private struct ClosesWhenRoomOpens: ViewModifier {
    @Environment(FriendsStore.self) private var friends
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.onChange(of: friends.room?.id) { old, new in
            if new != nil, new != old { dismiss() }
        }
    }
}

// MARK: - Toasts

private struct ToastStack: View {
    let resize: (CGFloat) -> Void

    @Environment(FriendsStore.self) private var friends

    var body: some View {
        VStack(spacing: 8) {
            if let invite = friends.toastInvite {
                InviteToast(invite: invite)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let event = friends.roomEvent {
                RoomEventToast(event: event)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .frame(maxWidth: 520)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { resize(proxy.size.height) }
                    .onChange(of: proxy.size.height) { _, height in resize(height) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(duration: 0.4, bounce: 0.25), value: friends.toastInvite?.id)
        .animation(.spring(duration: 0.4, bounce: 0.25), value: friends.roomEvent?.id)
    }
}

/// A friend's invite: who, to what, how long it lasts, and the answer.
struct InviteToast: View {
    let invite: GameInvite

    @Environment(FriendsStore.self) private var friends

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                InviteArt(invite: invite, sender: friends.sender(of: invite))
                InviteText(invite: invite)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                Button(L10n.text("Not now")) { friends.snooze(invite) }
                    .buttonStyle(ToastButtonStyle(prominent: false))
                Button(L10n.text("Play")) { Task { await friends.accept(invite) } }
                    .buttonStyle(ToastButtonStyle(prominent: true))
            }
        }
        .padding(12)
        .overlay(alignment: .bottomLeading) { InviteTimeBar(invite: invite) }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
    }
}

/// A friend joined the room, or can't play now.
private struct RoomEventToast: View {
    let event: RoomEvent

    var body: some View {
        HStack(spacing: 10) {
            if let profile = event.profile {
                FriendAvatar(profile: profile, online: nil, size: 32)
            } else {
                Text(event.name.first.map { String($0).uppercased() } ?? "?")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(GameTheme.accent.gradient, in: Circle())
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(event.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(event.text).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Invite pieces

/// The game's artwork (or the room icon), with the sender's avatar on its corner.
struct InviteArt: View {
    let invite: GameInvite
    let sender: FriendProfile?
    var size: CGFloat = 44

    var body: some View {
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
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.23))
        .overlay(alignment: .bottomTrailing) {
            if let sender {
                FriendAvatar(profile: sender, online: nil, size: size * 0.5)
                    .overlay { Circle().strokeBorder(Color(.systemBackground), lineWidth: 2) }
                    .offset(x: 6, y: 6)
            }
        }
        .padding(.trailing, sender == nil ? 0 : 4)
        .accessibilityHidden(true)
    }
}

/// "Aigerim / invites you to play Durak".
struct InviteText: View {
    let invite: GameInvite

    var body: some View {
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
    }
}

/// A thin bar along the bottom that runs down as the invite expires.
private struct InviteTimeBar: View {
    let invite: GameInvite

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = invite.expiresAt.timeIntervalSince(context.date) / GameInvite.lifetime
            GeometryReader { proxy in
                Capsule()
                    .fill(GameTheme.accent)
                    .frame(width: proxy.size.width * min(max(left, 0), 1), height: 3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 3)
        }
        .accessibilityHidden(true)
    }
}

/// "5 min left" for an invite still open.
func inviteTimeLeft(_ invite: GameInvite, now: Date) -> String {
    let minutes = max(1, Int((invite.expiresAt.timeIntervalSince(now) / 60).rounded(.up)))
    return L10n.format("%d min left", minutes)
}

struct ToastButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(prominent ? AnyShapeStyle(GameTheme.accent) : AnyShapeStyle(Color(.tertiarySystemFill)),
                        in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}
