import Foundation

/// A round's active time is independent of card snapshots, so Undo cannot rewind it.
struct CardRoundClock {
    private(set) var elapsed: TimeInterval = 0
    private var anchor: TimeInterval?

    mutating func tick() {
        guard let anchor else { return }
        let now = ProcessInfo.processInfo.systemUptime
        elapsed += max(0, now - anchor)
        self.anchor = now
    }

    mutating func setActive(_ active: Bool) {
        tick()
        anchor = active ? ProcessInfo.processInfo.systemUptime : nil
    }

    /// Continues a saved round from `elapsed` seconds.
    mutating func resume(from elapsed: TimeInterval, active: Bool) {
        self.elapsed = elapsed
        anchor = active ? ProcessInfo.processInfo.systemUptime : nil
    }

    mutating func reset(active: Bool) {
        elapsed = 0
        anchor = active ? ProcessInfo.processInfo.systemUptime : nil
    }

    var formattedTime: String {
        let seconds = Int(elapsed)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    /// 1,000 maximum; 500 at five minutes, 333 at ten. Only awarded on victory.
    var victoryBonus: Int { Int(1000 / (1 + elapsed / 300)) }
}
