import AVFoundation

/// Small interface sounds, synthesised here (no audio files): a soft chime when a scan ends, a brighter
/// run when cleaning finishes, a low double tone on failure, and a faint tick for the big round buttons.
@MainActor
final class Sounds {
    enum Cue: CaseIterable { case scanDone, cleanDone, failed, pressDown, pressUp }

    static let shared = Sounds()
    static let defaultsKey = "soundsEnabled"

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var buffers: [Cue: AVAudioPCMBuffer] = [:]

    private init() {
        UserDefaults.standard.register(defaults: [Self.defaultsKey: true])
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        for cue in Cue.allCases { buffers[cue] = render(cue) }
    }

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.defaultsKey) }

    func play(_ cue: Cue) {
        guard isEnabled, let buffer = buffers[cue] else { return }
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        if !player.isPlaying { player.play() }
    }

    // MARK: Synthesis

    /// One struck tone: a few slightly inharmonic partials with an exponential decay, like a small bell.
    private struct Note {
        var frequency: Double
        var start: Double
        var decay: Double
        var gain: Double
        var partials: [(ratio: Double, weight: Double)] = [(1, 1), (2.01, 0.28), (3.98, 0.1)]
    }

    private func render(_ cue: Cue) -> AVAudioPCMBuffer {
        let notes: [Note]
        var tick = false
        switch cue {
        case .scanDone:
            notes = [Note(frequency: 659.25, start: 0, decay: 0.28, gain: 0.22), Note(frequency: 987.77, start: 0.11, decay: 0.42, gain: 0.2)]
        case .cleanDone:
            notes = [523.25, 659.25, 783.99, 1046.5].enumerated().map { i, f in
                Note(frequency: f, start: Double(i) * 0.085, decay: i == 3 ? 0.6 : 0.3, gain: 0.2)
            }
        case .failed:
            notes = [Note(frequency: 233.08, start: 0, decay: 0.22, gain: 0.3, partials: [(1, 1), (2, 0.2)]),
                     Note(frequency: 174.61, start: 0.13, decay: 0.3, gain: 0.3, partials: [(1, 1), (2, 0.2)])]
        case .pressDown:
            notes = [Note(frequency: 1_250, start: 0, decay: 0.012, gain: 0.16, partials: [(1, 1)])]; tick = true
        case .pressUp:
            notes = [Note(frequency: 1_700, start: 0, decay: 0.009, gain: 0.1, partials: [(1, 1)])]; tick = true
        }
        let rate = format.sampleRate
        let length = Int((notes.map { $0.start + $0.decay * 5 }.max() ?? 0.1) * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(length))!
        buffer.frameLength = AVAudioFrameCount(length)
        let samples = buffer.floatChannelData![0]
        for i in 0..<length { samples[i] = 0 }
        var seed: UInt32 = 0x9E3779B9
        for note in notes {
            let first = Int(note.start * rate)
            guard first < length else { continue }
            for i in first..<length {
                let t = Double(i - first) / rate
                let envelope = exp(-t / note.decay) * min(1, t / 0.003)   // 3 ms attack avoids a click
                var value = 0.0
                for (ratio, weight) in note.partials { value += weight * sin(2 * .pi * note.frequency * ratio * t) }
                if tick, t < 0.006 {   // a breath of noise makes the tick feel physical
                    seed = seed &* 1_664_525 &+ 1_013_904_223
                    value += (Double(seed >> 9) / Double(1 << 23) - 0.5) * 1.4
                }
                samples[i] += Float(value * envelope * note.gain)
            }
        }
        return buffer
    }
}
