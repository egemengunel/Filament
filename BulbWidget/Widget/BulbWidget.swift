import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Timeline

struct BulbEntry: TimelineEntry {
    let date: Date
    let state: BulbState
}

struct BulbProvider: TimelineProvider {
    func placeholder(in context: Context) -> BulbEntry {
        BulbEntry(date: .now, state: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (BulbEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }
        Task { completion(BulbEntry(date: .now, state: await BulbClient.state())) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<BulbEntry>) -> Void) {
        Task {
            let entry = BulbEntry(date: .now, state: await BulbClient.state())
            // Taps reload immediately; this only catches changes made elsewhere.
            completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(5 * 60))))
        }
    }
}

// MARK: - Widget

struct BulbWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BulbWidget", provider: BulbProvider()) { entry in
            BulbWidgetView(state: entry.state)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Bulb")
        .description("Turn the light on or off, adjust brightness and pick a preset.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct BulbWidgetBundle: WidgetBundle {
    var body: some Widget {
        BulbWidget()
    }
}

// MARK: - Views

struct BulbWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let state: BulbState

    var body: some View {
        switch family {
        case .systemLarge: LargeBulbView(state: state)
        case .systemMedium: MediumBulbView(state: state)
        default: SmallBulbView(state: state)
        }
    }
}

struct SmallBulbView: View {
    let state: BulbState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PowerButton(state: state)
            Spacer(minLength: 8)
            TileLabels(state: state)
            HStack(spacing: 8) {
                StepButton(state: state, delta: -10, height: 28)
                StepButton(state: state, delta: 10, height: 28)
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MediumBulbView: View {
    let state: BulbState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                PowerButton(state: state)
                TileLabels(state: state)
                Spacer(minLength: 8)
                PresetRow(state: state, size: 28)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                StepButton(state: state, delta: -5, height: 32)
                    .frame(width: 32)
                HorizontalBrightnessSlider(state: state)
                    .frame(height: 32)
                StepButton(state: state, delta: 5, height: 32)
                    .frame(width: 32)
            }
        }
    }
}

struct LargeBulbView: View {
    let state: BulbState

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                PowerButton(state: state)
                TileLabels(state: state)
                Spacer(minLength: 0)
            }
            VerticalBrightnessSlider(state: state)
                .frame(width: 104)
                .frame(maxHeight: .infinity)
            PresetRow(state: state, size: 40)
        }
    }
}

/// The round bulb icon from Home tiles; tapping it toggles the light.
private struct PowerButton: View {
    let state: BulbState

    var body: some View {
        Button(intent: SetBulbPowerIntent(on: !state.on)) {
            Image(systemName: state.isLit ? "lightbulb.fill" : "lightbulb")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(state.isLit ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 40, height: 40)
                .background {
                    Circle().fill(state.isLit ? AnyShapeStyle(iconTint) : AnyShapeStyle(.fill.secondary))
                }
                .widgetAccentable()
        }
        .buttonStyle(.plain)
        .disabled(!state.reachable)
        .accessibilityLabel(state.on ? "Turn Off" : "Turn On")
    }

    /// Home shows warm/cool white bulbs as yellow, colored bulbs in their color.
    private var iconTint: Color {
        state.colorTemp == 0 ? state.lightTint : .yellow
    }
}

private struct TileLabels: View {
    let state: BulbState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(state.room)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(state.name)
                .font(.headline)
            statusText
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private var statusText: some View {
        if !state.reachable {
            Text("No Response")
        } else if state.on {
            Text(Double(state.brightness) / 100, format: .percent)
        } else {
            Text("Off")
        }
    }
}

/// Dim or brighten by a fixed step.
private struct StepButton: View {
    let state: BulbState
    let delta: Int
    let height: CGFloat

    var body: some View {
        Button(intent: StepBulbBrightnessIntent(delta: delta)) {
            Image(systemName: delta < 0 ? "sun.min.fill" : "sun.max.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
                .background(.fill.secondary, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!state.reachable)
        .accessibilityLabel(delta < 0 ? "Dim" : "Brighten")
    }
}

/// Favourite presets as Home-style color circles; the active one gets a ring.
private struct PresetRow: View {
    let state: BulbState
    let size: CGFloat

    var body: some View {
        HStack(spacing: size / 3.5) {
            ForEach(BulbPreset.all) { preset in
                Button(intent: ApplyBulbPresetIntent(presetID: preset.id)) {
                    Circle()
                        .fill(preset.swatch)
                        .overlay(Circle().strokeBorder(.quaternary, lineWidth: 1))
                        .padding(4)
                        .overlay {
                            if preset.matches(state) {
                                Circle().strokeBorder(.primary, lineWidth: 2)
                            }
                        }
                        .frame(width: size + 8, height: size + 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(preset.name))
            }
        }
        .disabled(!state.reachable)
    }
}

/// Brightness levels the sliders snap to. Widgets can't drag, so each level is a tap target.
private let brightnessLevels = Array(stride(from: 10, through: 100, by: 10))

private struct HorizontalBrightnessSlider: View {
    let state: BulbState

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(.fill.secondary)
                Rectangle()
                    .fill(state.lightTint)
                    .frame(width: proxy.size.width * fillFraction(state))
                    .widgetAccentable()
                HStack(spacing: 0) {
                    ForEach(brightnessLevels, id: \.self) { level in
                        LevelButton(level: level)
                    }
                }
            }
            .clipShape(Capsule())
        }
        .disabled(!state.reachable)
    }
}

/// The tall Home brightness slider.
private struct VerticalBrightnessSlider: View {
    let state: BulbState

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                Rectangle().fill(.fill.secondary)
                Rectangle()
                    .fill(state.lightTint)
                    .frame(height: proxy.size.height * fillFraction(state))
                    .widgetAccentable()
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(state.isLit ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .padding(.bottom, 16)
                VStack(spacing: 0) {
                    ForEach(brightnessLevels.reversed(), id: \.self) { level in
                        LevelButton(level: level)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .disabled(!state.reachable)
    }
}

private struct LevelButton: View {
    let level: Int

    var body: some View {
        Button(intent: SetBulbBrightnessIntent(level: level)) {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(Double(level) / 100, format: .percent))
    }
}

private func fillFraction(_ state: BulbState) -> CGFloat {
    state.isLit ? CGFloat(state.brightness) / 100 : 0
}

#Preview(as: .systemSmall) {
    BulbWidget()
} timeline: {
    BulbEntry(date: .now, state: .preview)
    BulbEntry(date: .now, state: .noResponse)
}

#Preview(as: .systemMedium) {
    BulbWidget()
} timeline: {
    BulbEntry(date: .now, state: .preview)
}

#Preview(as: .systemLarge) {
    BulbWidget()
} timeline: {
    BulbEntry(date: .now, state: .preview)
}
