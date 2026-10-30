import SwiftUI
import CapaCore

/// Presentation only. Neither glass nor its decorative outline can intercept clicks.
struct VoiceWidgetFace: View {
    let recording: Bool
    let speaking: Bool
    let waiting: Bool
    let needsReview: Bool
    let level: Double
    let pitch: Double
    let reduceMotion: Bool
    var hovered = false
    var recordHovered = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let gold = Color(red: 0.75, green: 0.66, blue: 0.48)
    private var active: Bool { recording || speaking || waiting }
    var body: some View {
        ZStack {
            surface
            Capsule().fill(.white.opacity(hovered ? 0.08 : 0))
            Capsule().strokeBorder(.white.opacity(hovered ? 0.25 : 0.06), lineWidth: 0.5)
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !active)) { context in
                let phase = reduceMotion || !active ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 8) * 45
                Capsule().strokeBorder(AngularGradient(colors: [.cyan, .blue, .purple, .pink, .orange, .green, .cyan],
                    center: .center, angle: .degrees(phase)), lineWidth: 0.8)
                    .opacity(active || hovered ? 0.60 : 0.25)
            }
            if needsReview && !recording && !waiting {
                Circle().fill(.orange).frame(width: 4, height: 4).offset(x: -43, y: 0)
            }
            Rectangle().fill(.white.opacity(0.12)).frame(width: 0.5, height: 11).offset(x: 27, y: 0)
            if waiting {
                ProgressView().controlSize(.mini).tint(gold)
            } else if speaking {
                Image(systemName: "speaker.wave.2.fill").font(.system(size: 12)).foregroundStyle(gold)
            } else {
                HStack(spacing: 2.3) {
                    ForEach(0..<7) { index in
                        Capsule().fill(recordHovered ? Color(red: 0.95, green: 0.86, blue: 0.67) : gold).frame(width: 2.2, height: barHeight(index))
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.09), value: level)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.09), value: pitch)
            }
        }
        .frame(width: CompactWidgetGeometry.width, height: CompactWidgetGeometry.height)
        .allowsHitTesting(false)
    }
    @ViewBuilder private var surface: some View {
        if reduceTransparency {
            Capsule().fill(Color(red: 0.07, green: 0.07, blue: 0.08))
        } else if #available(macOS 26.0, *) {
            Capsule().fill(.clear).glassEffect(.regular.tint(.black.opacity(0.24)), in: Capsule()).opacity(0.60)
        } else {
            Capsule().fill(.ultraThinMaterial).opacity(0.60)
        }
    }
    private func barHeight(_ index: Int) -> Double {
        let baseline = [5.0, 9, 14, 19, 14, 9, 5][index]
        guard recording, !reduceMotion else { return baseline * (recording ? 1 : 0.75) }
        let tone = pitch > 0 ? min(1, max(0, log2(pitch / 65) / log2(500 / 65))) : 0
        let contour = 0.7 + 0.3 * cos(Double(index - 3) * (0.6 + tone))
        return 3 + baseline * min(1, max(0, level)) * contour
    }
}
