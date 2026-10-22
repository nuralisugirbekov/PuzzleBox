import SwiftUI

// Apple Music–style building blocks shared by Home, Discover and Search.

/// A tab's large title with its buttons and Settings in one row (Figma
/// "All games" header). Tabs hide the navigation bar and put this at the top
/// of their content, because the system large title always sits a row below
/// the toolbar buttons.
struct TabHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            trailing()
            SettingsButton()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}

extension TabHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// 44pt glass circle with an SF Symbol, for `TabHeader` actions.
struct HeaderCircleButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .glassCircle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

extension View {
    /// Root of a tab: no navigation bar, so `TabHeader` takes its place. The
    /// title is kept as the back button label of pushed screens.
    func tabRoot(title: String) -> some View {
        navigationTitle(title)
            .toolbar(.hidden, for: .navigationBar)
    }
}

/// Bold section title with an optional trailing chevron, like "Recently Played ›".
struct ShelfHeader<Destination: View>: View {
    let title: String
    @ViewBuilder var destination: () -> Destination

    var body: some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                Image(systemName: "chevron.forward")
                    .imageScale(.small)
            }
            .font(.title2.bold())
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }
}

/// Bold section title without a destination.
struct SectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title2.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
    }
}

/// Horizontally scrolling row that snaps to its items.
struct Shelf<Item: Identifiable, Content: View>: View {
    let items: [Item]
    var spacing: CGFloat = 12
    @ViewBuilder var content: (Item) -> Content

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: spacing) {
                ForEach(items) { content($0) }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
    }
}

/// Large hero card with the title over the artwork.
struct FeaturedGameCard: View {
    let gameID: GameID
    let eyebrow: String
    var source: String = "featured"

    @Environment(\.playGame) private var playGame

    var body: some View {
        let info = gameID.info
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Button {
                playGame(gameID, source: source)
            } label: {
                GamePreviewArt(gameID: gameID)
                    .frame(height: 220)
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.title)
                                .font(.title.bold())
                            Text(info.tagline)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        .padding(16)
                        .padding(.trailing, FavoriteButton.size + 8)
                    }
                    .clipShape(.rect(cornerRadius: 24))
                    .contentShape(.rect(cornerRadius: 24))
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottomTrailing) {
                FavoriteButton(gameID: gameID)
                    .padding(12)
            }
        }
    }
}

// MARK: - Categories

extension GameCategory {
    var symbol: String {
        switch self {
        case .logic: "brain.head.profile"
        case .casual: "sparkles"
        case .arcade: "arcade.stick"
        case .cards: "suit.spade.fill"
        case .attention: "eye.fill"
        case .visual: "square.grid.3x3.fill"
        case .numbers: "number"
        case .japanese: "circle.grid.3x3"
        case .physics: "basketball.fill"
        case .reaction: "bolt.fill"
        }
    }

    var tint: Color {
        switch self {
        case .logic: .indigo
        case .casual: .pink
        case .arcade: .green
        case .cards: .teal
        case .attention: .cyan
        case .visual: .purple
        case .numbers: .orange
        case .japanese: .red
        case .physics: .blue
        case .reaction: .mint
        }
    }

    var games: [GameID] {
        GameID.catalog.filter { $0.info.category == self }
    }

    /// Categories with at least one game left after hiding.
    static var listed: [GameCategory] { allCases.filter { !$0.games.isEmpty } }
}

/// Coloured category tile, like the genre tiles in Apple Music's Browse.
struct CategoryTile: View {
    let category: GameCategory

    var body: some View {
        NavigationLink {
            CategoryGamesView(category: category)
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 16)
                    .fill(category.tint.gradient)
                Image(systemName: category.symbol)
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .rotationEffect(.degrees(20))
                    .offset(x: 18, y: 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .clipped()
                Text(L10n.text(category.rawValue))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(12)
            }
            .frame(height: 104)
            .clipShape(.rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

/// Two-column grid of category tiles.
struct CategoryGrid: View {
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12),
                            GridItem(.flexible(), spacing: 12)],
                  spacing: 12) {
            ForEach(GameCategory.listed) { CategoryTile(category: $0) }
        }
        .padding(.horizontal)
    }
}

extension GameID {
    /// Random daily pick, shared by Home and Discover and retained across launches.
    static var gameOfTheDay: GameID {
        let defaults = UserDefaults.standard
        let day = Calendar.current.startOfDay(for: .now).timeIntervalSince1970
        let dateKey = "dailyGame.date"
        let gameKey = "dailyGame.id"
        if defaults.double(forKey: dateKey) == day,
           let raw = defaults.string(forKey: gameKey),
           let saved = GameID(rawValue: raw), catalog.contains(saved) {
            return saved
        }
        let previous = defaults.string(forKey: gameKey)
        let candidates = catalog.filter { $0.rawValue != previous }
        let selected = candidates.randomElement() ?? catalog.randomElement() ?? .bounce
        defaults.set(selected.rawValue, forKey: gameKey)
        defaults.set(day, forKey: dateKey)
        return selected
    }
}
