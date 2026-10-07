import Foundation
import FirebaseAnalytics

/// Stable identifiers keep reports consistent across all UI languages.
@MainActor
enum AppAnalytics {
    static func log(_ event: String, parameters: [String: Any] = [:]) {
        var values = parameters
        if values["app_language"] == nil {
            values["app_language"] = UserDefaults.standard.string(forKey: L10n.languageKey)
                .flatMap(AppLanguage.init(rawValue:))?.rawValue ?? "not_selected"
        }
        Analytics.logEvent(event, parameters: values)
    }

    static func screen(_ name: String) {
        log(AnalyticsEventScreenView, parameters: [
            AnalyticsParameterScreenName: name,
            AnalyticsParameterScreenClass: name
        ])
    }

    static func updateLanguageProperty() {
        let language = UserDefaults.standard.string(forKey: L10n.languageKey)
            .flatMap(AppLanguage.init(rawValue:))
        Analytics.setUserProperty(language?.rawValue, forName: "app_language")
    }

    static func selectLanguage(_ language: AppLanguage) {
        let previous = UserDefaults.standard.string(forKey: L10n.languageKey)
            .flatMap(AppLanguage.init(rawValue:))
        guard previous != language else { return }
        Analytics.setUserProperty(language.rawValue, forName: "app_language")
        log("language_selected", parameters: [
            "app_language": language.rawValue,
            "previous_language": previous?.rawValue ?? "not_selected",
            "selection_source": previous == nil ? "onboarding" : "settings"
        ])
    }

    static func selectGame(_ game: GameID, source: String) {
        log(AnalyticsEventSelectContent, parameters: [
            AnalyticsParameterContentType: "game",
            AnalyticsParameterItemID: game.rawValue,
            "selection_source": source
        ])
    }
}

/// One start/end pair per round, including explicit exits and restarts.
/// Duration uses monotonic time and excludes pauses and inactive app time.
@MainActor
final class GameRoundAnalytics {
    private var game: GameID?
    private var ended = true
    private var elapsed: TimeInterval = 0
    private var activeSince: TimeInterval?

    func start(_ game: GameID, active: Bool) {
        guard ended else { return }
        self.game = game
        ended = false
        elapsed = 0
        activeSince = active ? ProcessInfo.processInfo.systemUptime : nil
        event(AnalyticsEventLevelStart)
    }

    func setActive(_ active: Bool) {
        guard !ended else { return }
        if active {
            if activeSince == nil { activeSince = ProcessInfo.processInfo.systemUptime }
        } else if let start = activeSince {
            elapsed += ProcessInfo.processInfo.systemUptime - start
            activeSince = nil
        }
    }

    func event(_ name: String, score: Int? = nil) {
        guard let game, !ended else { return }
        var parameters = context(game)
        if let score { parameters[AnalyticsParameterScore] = score }
        AppAnalytics.log(name, parameters: parameters)
    }

    func finish(score: Int, reason: String, won: Bool = false, newRecord: Bool = false, timeBonus: Int? = nil) {
        guard let game, !ended else { return }
        setActive(false)
        ended = true
        var parameters = context(game)
        parameters[AnalyticsParameterScore] = score
        parameters[AnalyticsParameterSuccess] = won ? 1 : 0
        parameters["end_reason"] = reason
        parameters["duration_seconds"] = Int(elapsed)
        parameters["new_high_score"] = newRecord ? 1 : 0
        if let timeBonus { parameters["time_bonus"] = timeBonus }
        AppAnalytics.log(AnalyticsEventLevelEnd, parameters: parameters)
        if reason == "completed" {
            AppAnalytics.log(AnalyticsEventPostScore, parameters: [
                AnalyticsParameterScore: score, "game_id": game.rawValue
            ])
            if newRecord {
                AppAnalytics.log("new_high_score", parameters: [
                    "game_id": game.rawValue, AnalyticsParameterScore: score
                ])
            }
        }
    }

    private func context(_ game: GameID) -> [String: Any] {
        ["game_id": game.rawValue,
         AnalyticsParameterLevelName: game.rawValue,
         "game_category": game.info.category.rawValue.lowercased(),
         "difficulty": game.info.difficulty.rawValue.lowercased()]
    }
}
