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

    // The menu's: shorter and quieter than the switch's, each saying what
    // its option did. The plain ones are the website's (lib/sfx.ts).
    enum Sound: Hashable {
        case on, off                    // the switch's chime
        case check(Bool)                // an option checked, or unchecked
        case monochrome(Bool)           // the color drains out, or comes back
        case compact(Bool)              // the switch shrinks, or grows back
        case length(hours: Int?)        // a timed session, nil for No Time Limit
        case batteryLimit(Int)          // percent
        case refused                    // too hot, the battery too low, an update that could not be had
        case tap, done, link, bye       // Check for Updates; up to date; a link; Quit

        static let all: [Sound] = [.on, .off, .check(true), .check(false), .monochrome(true), .monochrome(false),
                                   .compact(true), .compact(false)]
            + [1, 2, 4, 8, nil].map { .length(hours: $0) } + [5, 10, 20, 30].map { .batteryLimit($0) }
            + [.refused, .tap, .done, .link, .bye]

        var name: String {
            switch self {
            case .on: return "on"
            case .off: return "off"
            case .check(let on): return on ? "check" : "uncheck"
            case .monochrome(let on): return "monochrome \(on ? "on" : "off")"
            case .compact(let on): return "compact \(on ? "on" : "off")"
            case .length(let hours): return hours.map { "length \($0)h" } ?? "no time limit"
            case .batteryLimit(let percent): return "battery limit \(percent)%"
            case .refused: return "refused"
            case .tap: return "tap"
            case .done: return "done"
            case .link: return "link"
            case .bye: return "bye"
            }
        }
    }

    // Semitones above E5 for each note of the menu's runs, from the bottom.
    static let run = [0, 4, 7, 12, 16, 19, 24]

    static func samples(_ sound: Sound) -> [Float] {
        switch sound {
        case .on: return samples(on: true)
        case .off: return samples(on: false)
        // G#5 to E6, up, or down.
        case .check(let on): return on ? notes([4, 12], gap: 0.04, ring: 0.08, peak: 0.1) : notes([12, 4], gap: 0.04, ring: 0.07, peak: 0.08)
        // One B5 that loses its harmonics to a plain tone, as the switch
        // loses its colors, or gains them back.
        case .monochrome(let on):
            return glide(from: 7, to: 7, length: 0.24, decay: 0.12, peak: 0.1, brightness: on ? (1, 0) : (0, 1))
        // A slide down a fifth as the switch shrinks, up as it grows back.
        case .compact(let on):
            return glide(from: on ? 7 : 0, to: on ? 0 : 7, length: 0.2, decay: 0.12, peak: 0.1, brightness: (1, 1))
        // The longer the session, the higher the run climbs: 2 notes for an
        // hour, 5 for 8 hours, the whole run with no time limit.
        case .length(let hours):
            let count = hours.map { [1: 2, 2: 3, 4: 4, 8: 5][$0] ?? 2 } ?? run.count
            return notes(Array(run.prefix(count)), gap: 0.03, ring: hours == nil ? 0.14 : 0.09, peak: 0.1)
        // Two blips, higher for a higher limit: E5 at 5%, E6 at 30%.
        case .batteryLimit(let percent):
            let step = [5: 0, 10: 4, 20: 7, 30: 12][percent] ?? 0
            return notes([step, step], gap: 0.06, ring: 0.06, peak: 0.1)
        // B4 down to A#4, out of the key: no.
        case .refused: return notes([-5, -6], gap: 0.07, ring: 0.09, peak: 0.1)
        case .tap: return notes([7], gap: 0.04, ring: 0.05, peak: 0.1)
        case .done: return notes([12, 16, 19, 24], gap: 0.03, ring: 0.09, peak: 0.085)
        case .link: return notes([12, 19], gap: 0.035, ring: 0.06, peak: 0.085)
        case .bye: return notes([7, 0], gap: 0.045, ring: 0.06, peak: 0.08)
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

    // One note that slides from one step to another and turns brighter or
    // plainer (1 all of its harmonics, 0 none but the first) as it goes, both
    // on the spring the switch moves on.
    private static func glide(from start: Int, to end: Int, length: Double, decay: Double, peak: Double,
                              brightness: (from: Double, to: Double)) -> [Float] {
        var out = [Float](repeating: 0, count: Int((length + 0.02) * rate))
        pulse(&out, at: 0, length: length, freq: root * pow(2, Double(start) / 12), decay: decay,
              slide: Double(end - start), brightness: brightness)
        return scaled(out, to: peak)
    }

    // A critically damped spring from 0 to 1 over p in 0...1, as the switch
    // moves between looks.
    static func spring(_ p: Double) -> Double {
        (1 - (1 + 6 * p) * exp(-6 * p)) / (1 - 7 * exp(-6))
    }

    // A band-limited 25% pulse: its harmonics summed up to 18 kHz, so no
    // aliasing hiss. It may slide by `slide` semitones and change brightness
    // over its length.
    private static func pulse(_ out: inout [Float], at start: Double, length: Double, freq: Double, decay: Double,
                              slide: Double = 0, brightness: (from: Double, to: Double) = (1, 1)) {
        let duty = 0.25
        let top = freq * pow(2, max(0, slide) / 12)
        var harmonics: [(n: Double, amp: Double)] = []
        for k in 1...Int(18_000 / top) {
            let n = Double(k)
            harmonics.append((n, 2 / (n * .pi) * sin(n * .pi * duty)))
        }
        let first = Int(start * rate)
        let count = Int(length * rate)
        let moves = slide != 0 || brightness != (1, 1)
        var phase = 0.0
        for i in 0..<count where first + i < out.count {
            let t = Double(i) / rate
            let edge = min(1, t / 0.0015, (length - t) / 0.002) // no click at either end
            var value = 0.0
            if moves {
                let p = spring(t / length)
                let bright = brightness.from + (brightness.to - brightness.from) * p
                for h in harmonics { value += h.amp * pow(bright, h.n - 1) * cos(h.n * phase) }
                phase += 2 * .pi * freq * pow(2, slide * p / 12) / rate
            } else {
                for h in harmonics { value += h.amp * cos(2 * .pi * h.n * freq * t) }
            }
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
