import AVFoundation
import SwiftUI

/// Short synthesized game sounds. Buffers are generated once in code, so the
/// app ships no audio files. The `.ambient` session respects the silent switch
/// and mixes with the user's music.
@MainActor
enum SoundFX {
    enum Sound: CaseIterable {
        case tap, jump, point, coin, bounce, whoosh, pop, hit, lose, win
        case place, card, wrong, merge, clear, pour, tick
        case simon0, simon1, simon2, simon3

        static func simon(_ index: Int) -> Self { [.simon0, .simon1, .simon2, .simon3][index % 4] }
    }

    static let enabledKey = "soundEnabled"
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static func play(_ sound: Sound) {
        guard isEnabled else { return }
        Player.shared.play(sound)
    }

    @MainActor
    private final class Player {
        static let shared = Player()
        private let engine = AVAudioEngine()
        private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        private var nodes: [AVAudioPlayerNode] = []
        private var nextNode = 0
        private var buffers: [Sound: AVAudioPCMBuffer] = [:]
        private var lastPlayed: [Sound: TimeInterval] = [:]
        private var configured = false

        private func configure() {
            configured = true
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            // A small pool lets overlapping effects play without cutting each other off.
            for _ in 0..<8 {
                let node = AVAudioPlayerNode()
                engine.attach(node)
                engine.connect(node, to: engine.mainMixerNode, format: format)
                nodes.append(node)
            }
            engine.mainMixerNode.outputVolume = 0.55
            for sound in Sound.allCases { buffers[sound] = makeBuffer(Synth.samples(for: sound)) }
            NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                                                   object: engine, queue: .main) { _ in
                MainActor.assumeIsolated { Player.shared.startIfNeeded() }
            }
        }

        private func startIfNeeded() {
            guard !engine.isRunning else { return }
            try? engine.start()
        }

        func play(_ sound: Sound) {
            if !configured { configure() }
            // Rapid repeats (chain reactions) collapse into one audible hit.
            let now = ProcessInfo.processInfo.systemUptime
            if let last = lastPlayed[sound], now - last < 0.035 { return }
            lastPlayed[sound] = now
            startIfNeeded()
            guard engine.isRunning, let buffer = buffers[sound] else { return }
            let node = nodes[nextNode]
            nextNode = (nextNode + 1) % nodes.count
            node.stop()
            node.scheduleBuffer(buffer, at: nil)
            node.play()
        }

        private func makeBuffer(_ samples: [Float]) -> AVAudioPCMBuffer? {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { return nil }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
            return buffer
        }
    }
}

private enum Synth {
    static let rate: Double = 44_100

    enum Wave { case sine, triangle, square, noise }

    /// A single voice whose pitch glides from `from` to `to`, with a fast
    /// attack and exponential decay to avoid clicks.
    static func tone(_ from: Double, _ to: Double, duration: Double, wave: Wave = .sine,
                     volume: Float = 0.6, decay: Double = 4) -> [Float] {
        let count = Int(duration * rate)
        var phase = 0.0
        var noiseState: UInt32 = 0x1234_5678
        return (0..<count).map { i in
            let t = Double(i) / Double(count)
            let frequency = from * pow(to / from, t)
            phase += frequency / rate
            let p = phase - floor(phase)
            let value: Double
            switch wave {
            case .sine: value = sin(2 * .pi * p)
            case .triangle: value = 4 * abs(p - 0.5) - 1
            case .square: value = p < 0.5 ? 0.6 : -0.6
            case .noise:
                noiseState = noiseState &* 1_664_525 &+ 1_013_904_223
                value = Double(noiseState >> 8) / Double(1 << 23) - 1
            }
            let attack = min(1, Double(i) / (0.004 * rate))
            let envelope = attack * exp(-decay * t) * (1 - t)
            return Float(value * envelope) * volume
        }
    }

    static func sequence(_ parts: [[Float]]) -> [Float] { parts.flatMap { $0 } }

    static func mix(_ a: [Float], _ b: [Float]) -> [Float] {
        (0..<max(a.count, b.count)).map { i in
            (i < a.count ? a[i] : 0) + (i < b.count ? b[i] : 0)
        }
    }

    static func samples(for sound: SoundFX.Sound) -> [Float] {
        switch sound {
        case .tap:
            return tone(1_100, 900, duration: 0.035, wave: .triangle, volume: 0.35, decay: 6)
        case .jump:
            return tone(330, 780, duration: 0.14, wave: .triangle, volume: 0.45, decay: 2)
        case .point:
            return sequence([tone(880, 880, duration: 0.05, wave: .triangle, volume: 0.4, decay: 1),
                             tone(1_320, 1_320, duration: 0.09, wave: .triangle, volume: 0.4, decay: 3)])
        case .coin:
            return sequence([tone(988, 988, duration: 0.06, wave: .square, volume: 0.3, decay: 0.5),
                             tone(1_319, 1_319, duration: 0.22, wave: .square, volume: 0.3, decay: 3)])
        case .bounce:
            return tone(620, 340, duration: 0.09, wave: .sine, volume: 0.6, decay: 3)
        case .whoosh:
            return mix(tone(1, 1, duration: 0.16, wave: .noise, volume: 0.18, decay: 3),
                       tone(500, 1_200, duration: 0.16, wave: .sine, volume: 0.15, decay: 3))
        case .pop:
            return tone(500, 1_300, duration: 0.05, wave: .sine, volume: 0.45, decay: 4)
        case .hit:
            return mix(tone(1, 1, duration: 0.2, wave: .noise, volume: 0.35, decay: 6),
                       tone(220, 70, duration: 0.25, wave: .sine, volume: 0.7, decay: 3))
        case .lose:
            return mix(tone(1, 1, duration: 0.3, wave: .noise, volume: 0.25, decay: 7),
                       sequence([tone(392, 370, duration: 0.14, wave: .triangle, volume: 0.45, decay: 1),
                                 tone(330, 311, duration: 0.14, wave: .triangle, volume: 0.45, decay: 1),
                                 tone(262, 196, duration: 0.35, wave: .triangle, volume: 0.45, decay: 2)]))
        case .place:
            return tone(260, 180, duration: 0.07, wave: .sine, volume: 0.55, decay: 5)
        case .card:
            return mix(tone(1, 1, duration: 0.06, wave: .noise, volume: 0.22, decay: 8),
                       tone(700, 500, duration: 0.04, wave: .triangle, volume: 0.15, decay: 5))
        case .wrong:
            return sequence([tone(196, 190, duration: 0.08, wave: .square, volume: 0.22, decay: 1),
                             tone(165, 160, duration: 0.14, wave: .square, volume: 0.22, decay: 3)])
        case .merge:
            return mix(tone(400, 900, duration: 0.12, wave: .sine, volume: 0.45, decay: 3),
                       tone(800, 1_800, duration: 0.12, wave: .sine, volume: 0.15, decay: 4))
        case .clear:
            return sequence([783.99, 1_046.5, 1_318.5, 1_568].map { tone($0, $0 * 1.01, duration: 0.06, wave: .sine, volume: 0.35, decay: 2) })
        case .pour:
            return sequence([700, 560, 640, 480, 540].map { tone(Double($0), Double($0) * 0.8, duration: 0.045, wave: .sine, volume: 0.35, decay: 3) })
        case .tick:
            return tone(2_000, 1_800, duration: 0.02, wave: .triangle, volume: 0.2, decay: 6)
        case .simon0, .simon1, .simon2, .simon3:
            let notes: [SoundFX.Sound: Double] = [.simon0: 329.63, .simon1: 440, .simon2: 554.37, .simon3: 659.25]
            let note = notes[sound] ?? 440
            return tone(note, note, duration: 0.3, wave: .triangle, volume: 0.45, decay: 2)
        case .win:
            return sequence([523.25, 659.25, 783.99].map { tone($0, $0, duration: 0.08, wave: .triangle, volume: 0.4, decay: 1) }
                            + [tone(1_046.5, 1_046.5, duration: 0.35, wave: .triangle, volume: 0.45, decay: 3)])
        }
    }
}
