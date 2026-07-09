// VesnAI iOS home-screen widget (WidgetKit).
//
// Reads the shared snapshot the Flutter app writes into the App Group
// `group.ai.vesnai.shared` and shows recent notes plus a quick-capture deep link.
// Add this target in Xcode (Widget Extension) and enable the App Group capability
// on both the app and this extension.

import SwiftUI
import WidgetKit

private let appGroupId = "group.ai.vesnai.shared"
private let snapshotKey = "widget_snapshot"
private let widgetRecentsLimit = 10
private let widgetSmallRecentsLimit = 4

/// Sync colors with NoteTypeColors in app/lib/features/notes/note_type_ui.dart
enum NoteTypePalette {
    static func color(for type: String) -> Color {
        switch type {
        case "Idea":
            return Color(red: 0.91, green: 0.64, blue: 0.09)
        case "Task":
            return Color(red: 0.17, green: 0.66, blue: 0.60)
        case "Photo":
            return Color(red: 0.61, green: 0.42, blue: 0.83)
        default:
            return Color(red: 0.13, green: 0.42, blue: 0.30)
        }
    }

    static func icon(for type: String) -> String {
        switch type {
        case "Idea":
            return "lightbulb"
        case "Task":
            return "checkmark.circle"
        case "Photo":
            return "camera"
        default:
            return "square.and.pencil"
        }
    }
}

struct VesnaiNote: Decodable {
    let title: String
    let type: String
    let generated: Bool
}

struct VesnaiSnapshot: Decodable {
    let version: Int
    let recents: [VesnaiNote]
}

struct VesnaiEntry: TimelineEntry {
    let date: Date
    let recents: [VesnaiNote]
}

func loadSnapshot() -> VesnaiSnapshot? {
    guard
        let defaults = UserDefaults(suiteName: appGroupId),
        let raw = defaults.string(forKey: snapshotKey),
        let data = raw.data(using: .utf8)
    else { return nil }
    return try? JSONDecoder().decode(VesnaiSnapshot.self, from: data)
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> VesnaiEntry {
        VesnaiEntry(date: Date(), recents: [VesnaiNote(title: "Your notes", type: "Note", generated: false)])
    }

    func getSnapshot(in context: Context, completion: @escaping (VesnaiEntry) -> Void) {
        completion(VesnaiEntry(date: Date(), recents: loadSnapshot()?.recents ?? []))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VesnaiEntry>) -> Void) {
        let entry = VesnaiEntry(date: Date(), recents: loadSnapshot()?.recents ?? [])
        // Refresh roughly every 30 minutes; the app also reloads timelines on write.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct VesnaiWidgetEntryView: View {
    var entry: VesnaiEntry
    @Environment(\.widgetFamily) private var family

    private var visibleRecents: [VesnaiNote] {
        let limit = family == .systemSmall ? widgetSmallRecentsLimit : widgetRecentsLimit
        return Array(entry.recents.prefix(limit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("VesnAI").font(.headline)
                Spacer()
                Link(destination: URL(string: "vesnai://capture")!) {
                    Image(systemName: "plus.circle.fill")
                }
            }
            ForEach(Array(visibleRecents.enumerated()), id: \.offset) { _, note in
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(NoteTypePalette.color(for: note.type).opacity(0.18))
                            .frame(width: 24, height: 24)
                        Image(systemName: NoteTypePalette.icon(for: note.type))
                            .font(.system(size: 12))
                            .foregroundColor(NoteTypePalette.color(for: note.type))
                    }
                    Text(note.title).font(.caption).lineLimit(1)
                    if note.generated {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                            .foregroundColor(Color(red: 0.56, green: 0.42, blue: 0.84))
                    }
                }
            }
            if entry.recents.isEmpty {
                Text("Tap + to capture a thought").font(.caption2).foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

@main
struct VesnaiWidget: Widget {
    let kind = "VesnaiWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            VesnaiWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("VesnAI")
        .description("Recent notes and quick capture.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
