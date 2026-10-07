import Foundation

/// Validated mate-in-one diagrams from the supplied Polgár PDF, bundled for offline play.
@MainActor
enum ChessPuzzleLibrary {
    private struct Record: Decodable {
        let fen: String
        let best: String
        let solutions: [String]?
    }

    private static let records: [Record] = {
        let resourceURL = Bundle.main.url(forResource: "MateInOne", withExtension: "json")
            ?? Bundle.main.url(forResource: "MateInOne", withExtension: "json", subdirectory: "Resources")
        guard let url = resourceURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Record].self, from: data) else {
            return []
        }
        return decoded.filter { record in
            let fields = record.fen.split(separator: " ")
            guard fields.count == 6, fields[1] == "w",
                  ([record.best] + (record.solutions ?? [])).allSatisfy({ uci in
                      let move = Array(uci)
                      return (move.count == 4 || move.count == 5)
                          && "abcdefgh".contains(move[0]) && "12345678".contains(move[1])
                          && "abcdefgh".contains(move[2]) && "12345678".contains(move[3])
                          && (move.count == 4 || "qrbn".contains(move[4]))
                  }) else { return false }
            let ranks = fields[0].split(separator: "/")
            return ranks.count == 8 && ranks.allSatisfy { rank in
                var squares = 0
                for character in rank {
                    if let empty = character.wholeNumberValue, (1...8).contains(empty) {
                        squares += empty
                    } else if "prnbqkPRNBQK".contains(character) {
                        squares += 1
                    } else {
                        return false
                    }
                }
                return squares == 8
            }
        }
    }()

    static func randomSeries(count: Int = 10) -> [ChessPuzzle] {
        var seen = Set<String>()
        var series: [ChessPuzzle] = []
        for record in records.shuffled() {
            // Ignore move counters when excluding repeated board positions.
            let position = String(record.fen.split(separator: " ")[0])
            guard seen.insert(position).inserted else { continue }
            series.append(ChessPuzzle(title: L10n.text("Mate in 1"),
                                      fen: record.fen, line: [record.best],
                                      solutions: record.solutions ?? []))
            if series.count == count { break }
        }
        return series
    }
}
