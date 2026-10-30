import Foundation

/// Local audio features for UI feedback. Samples and measurements are never retained.
public struct VoiceSignal: Sendable {
    public let level: Double
    public let pitch: Double
    public static let quiet = VoiceSignal(level: 0, pitch: 0)

    public static func measure(samples: [Float], sampleRate: Double) -> VoiceSignal {
        guard sampleRate.isFinite, sampleRate >= 1000, samples.count >= 128 else { return .quiet }
        let stride = max(1, Int(sampleRate / 8000))
        let values = Swift.stride(from: 0, to: min(samples.count, 8192), by: stride).map {
            samples[$0].isFinite ? Double(samples[$0]) : 0
        }
        let rate = sampleRate / Double(stride)
        let mean = values.reduce(0, +) / Double(values.count)
        let centered = values.map { $0 - mean }
        let rms = sqrt(centered.reduce(0) { $0 + $1 * $1 } / Double(centered.count))
        let level = min(1, max(0, (20 * log10(max(rms, 0.00001)) + 55) / 50))
        guard rms > 0.004 else { return VoiceSignal(level: level, pitch: 0) }
        let first = max(2, Int(rate / 500)), last = min(centered.count / 2, Int(rate / 65))
        guard first + 2 < last else { return VoiceSignal(level: level, pitch: 0) }
        var correlation: [Double] = []
        for lag in (first - 1)...(last + 1) {
            var product = 0.0, a = 0.0, b = 0.0
            for i in 0..<(centered.count - lag) {
                let x = centered[i], y = centered[i + lag]
                product += x * y; a += x * x; b += y * y
            }
            correlation.append(product / max(sqrt(a * b), 0.0000001))
        }
        // First strong local peak avoids octave-down aliases of a voiced signal.
        for i in 1..<(correlation.count - 1) where correlation[i] > 0.85 &&
            correlation[i] >= correlation[i - 1] && correlation[i] > correlation[i + 1] {
            return VoiceSignal(level: level, pitch: rate / Double(first - 1 + i))
        }
        return VoiceSignal(level: level, pitch: 0)
    }
}

public enum RecorderIntent: Sendable {
    case wait, stopSpeaking, finishRecording, record, reviewMemo
    public static func resolve(recording: Bool, preparing: Bool, processing: Bool, speaking: Bool,
                               pending: Bool, hasDraft: Bool, saved: Bool) -> RecorderIntent {
        if preparing || processing { return .wait }
        if speaking { return .stopSpeaking }
        if recording { return .finishRecording }
        if pending || hasDraft || saved { return .reviewMemo }
        return .record
    }
}
