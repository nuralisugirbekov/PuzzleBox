import SwiftUI

/// The detached search tab: category tiles until the player types,
/// then matching games.
struct SearchView: View {
    @State private var query = ""

    private var results: [GameID] {
        GameID.allCases.filter { id in
            let info = id.info
            return info.title.localizedCaseInsensitiveContains(query)
                || info.tagline.localizedCaseInsensitiveContains(query)
                || L10n.text(info.category.rawValue).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if query.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(title: L10n.text("Browse Categories"))
                        CategoryGrid()
                    }
                    .padding(.vertical)
                } else if results.isEmpty {
                    ContentUnavailableView {
                        Label(L10n.text("No games found"), systemImage: "magnifyingglass")
                    } description: {
                        Text(L10n.text("Try another search."))
                    }
                    .padding(.top, 40)
                } else {
                    GameGrid(games: results, source: "search")
                        .padding(.horizontal)
                        .padding(.vertical)
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(L10n.text("Search"))
            .searchable(text: $query, prompt: L10n.text("Search games"))
            .autocorrectionDisabled()
        }
    }
}
