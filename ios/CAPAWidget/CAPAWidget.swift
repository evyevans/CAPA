import SwiftUI
import WidgetKit

struct CAPAEntry: TimelineEntry { let date: Date }
struct CAPAProvider: TimelineProvider {
    func placeholder(in context: Context) -> CAPAEntry { CAPAEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (CAPAEntry) -> Void) { completion(CAPAEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CAPAEntry>) -> Void) {
        completion(Timeline(entries: [CAPAEntry(date: .now)], policy: .never))
    }
}

struct CAPAWidgetView: View {
    let entry: CAPAEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "waveform").font(.title2)
            if family != .accessoryCircular {
                Text("CAPA").font(.caption.weight(.semibold))
                if family != .accessoryRectangular { Text("Speak to Hermes").font(.caption2) }
            }
        }.foregroundStyle(Color(red: 0.75, green: 0.66, blue: 0.48))
            .containerBackground(Color(red: 0.025, green: 0.025, blue: 0.035), for: .widget)
            .widgetURL(URL(string: "capavoice://record"))
            .accessibilityLabel("Open CAPA and record a request to Hermes")
    }
}

@main
struct CAPAWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CAPAQuickMemo", provider: CAPAProvider()) { CAPAWidgetView(entry: $0) }
            .configurationDisplayName("Speak to Hermes")
            .description("Open CAPA directly to its voice recorder.")
            .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}
