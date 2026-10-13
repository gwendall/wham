import Foundation

// Wham's sounds, all on one 25% pulse wave, like an old console's square
// channel, and in one key, E major. Synthesized when first played, so they
// ship as code, not as files.
//
// The switch's: a little 8-bit arpeggio. It climbs to switch on and falls to
// switch off, softer. One note at a time, each cut by the next.
enum Chime {
    static let rate = 44_100.0
    static let root = 659.26 // E5
    static let steps = [0, 4, 7, 12] // E5 G#5 B5 E6: a major chord, up
    static let gap = 0.055 // seconds from one note to the next
    static let ring = 0.16 // how long the last note lasts

    static func samples(on: Bool) -> [Float] {
        let notes = (on ? steps : steps.reversed()).map { root * pow(2, Double($0) / 12) }
        var out = [Float](repeating: 0, count: Int((Double(notes.count - 1) * gap + ring + 0.02) * rate))
        for (index, freq) in notes.enumerated() {
            let last = index == notes.count - 1
            pulse(&out, at: Double(index) * gap, length: last ? ring : gap, freq: freq, decay: last ? 0.07 : 0.05)
        }
        return scaled(out, to: on ? 0.25 : 0.19)
    }

    // The menu's: four, shorter and quieter than the switch's, as on the
    // website (lib/sfx.ts). An option checked goes up and unchecked goes
    // down, as the switch does; a value picked ticks; a refusal falls out of
    // the key.
    enum Sound: Hashable {
        case on, off      // the switch's chime
        case check(Bool)  // an option checked, or unchecked
        case select       // a length, a battery limit, a link, Check for Updates
        case refused      // too hot, the battery too low, an update that could not be had

        static let all: [Sound] = [.on, .off, .check(true), .check(false), .select, .refused]

        var name: String {
            switch self {
            case .on: return "on"
            case .off: return "off"
            case .check(let on): return on ? "check" : "uncheck"
            case .select: return "select"
            case .refused: return "refused"
            }
        }
    }

    static func samples(_ sound: Sound) -> [Float] {
        switch sound {
        case .on: return samples(on: true)
        case .off: return samples(on: false)
        // G#5 to E6, up, or down.
        case .check(let on): return on ? notes([4, 12], gap: 0.04, ring: 0.08, peak: 0.1) : notes([12, 4], gap: 0.04, ring: 0.07, peak: 0.08)
        // One B5.
        case .select: return notes([7], gap: 0.04, ring: 0.05, peak: 0.1)
        // B4 down to A#4, out of the key: no.
        case .refused: return notes([-5, -6], gap: 0.07, ring: 0.09, peak: 0.1)
        }
    }

    // `steps` semitones above E5, `gap` seconds apart, each cut by the next,
    // the last one ringing `ring`: the website's sounds.
    private static func notes(_ steps: [Int], gap: Double, ring: Double, peak: Double) -> [Float] {
        var out = [Float](repeating: 0, count: Int((Double(steps.count - 1) * gap + ring + 0.02) * rate))
        for (index, step) in steps.enumerated() {
            let last = index == steps.count - 1
            pulse(&out, at: Double(index) * gap, length: last ? ring : gap, freq: root * pow(2, Double(step) / 12),
                  decay: last ? ring / 2.5 : gap)
        }
        return scaled(out, to: peak)
    }

    // A band-limited 25% pulse: its harmonics summed up to 18 kHz, so no aliasing hiss.
    private static func pulse(_ out: inout [Float], at start: Double, length: Double, freq: Double, decay: Double) {
        let duty = 0.25
        var harmonics: [(n: Double, amp: Double)] = []
        for k in 1...Int(18_000 / freq) {
            let n = Double(k)
            harmonics.append((n, 2 / (n * .pi) * sin(n * .pi * duty)))
        }
        let first = Int(start * rate)
        let count = Int(length * rate)
        for i in 0..<count where first + i < out.count {
            let t = Double(i) / rate
            let edge = min(1, t / 0.0015, (length - t) / 0.002) // no click at either end
            var value = 0.0
            for h in harmonics { value += h.amp * cos(2 * .pi * h.n * freq * t) }
            out[first + i] += Float(value * edge * exp(-t / decay))
        }
    }

    private static func scaled(_ samples: [Float], to peak: Double) -> [Float] {
        let top = samples.lazy.map(abs).max() ?? 1
        return samples.map { $0 / top * Float(peak) }
    }

    static func wav(_ samples: [Float]) -> Data {
        var data = Data()
        func le<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); le(36 + bytes); data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); le(UInt32(16)); le(UInt16(1)); le(UInt16(1))
        le(UInt32(rate)); le(UInt32(rate) * 2); le(UInt16(2)); le(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); le(bytes)
        for sample in samples { le(Int16(max(-1, min(1, sample)) * 32767)) }
        return data
    }
}
