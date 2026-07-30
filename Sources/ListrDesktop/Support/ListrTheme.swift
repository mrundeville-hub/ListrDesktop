import SwiftUI

enum ListrTheme {
    static let electricBlue = Color(red: 0.15, green: 0.36, blue: 0.96)
    static let softMint = Color(red: 0.68, green: 0.93, blue: 0.86)
    static let paperPink = Color(red: 1.0, green: 0.70, blue: 0.86)
    static let sunYellow = Color(red: 1.0, green: 0.88, blue: 0.26)
    static let citrusOrange = Color(red: 1.0, green: 0.55, blue: 0.28)
    static let ink = Color(red: 0.09, green: 0.10, blue: 0.13)
    static let quietBlue = Color(red: 0.82, green: 0.91, blue: 1.0)
    static let cream = Color(red: 1.0, green: 0.97, blue: 0.88)

    // Reference "cloud" palette (cool gray canvas, floating white cards, pill chips)
    static let paper = Color(red: 0.945, green: 0.945, blue: 0.953)       // page background
    static let card = Color.white                                          // floating card surface
    static let hairline = Color.black.opacity(0.06)                        // whisper borders
    static let chip = Color(red: 0.957, green: 0.957, blue: 0.965)         // pill chip fill
    static let mutedLabel = Color(red: 0.62, green: 0.62, blue: 0.66)      // secondary text
    static let accent = Color(red: 0.42, green: 0.36, blue: 0.90)          // "Summary" violet
    static let accentWash = Color(red: 0.93, green: 0.92, blue: 0.99)      // violet chip fill
    static let highlight = Color(red: 0.93, green: 0.92, blue: 0.99)       // spoken-word wash

    static var mono: Font.Design { .monospaced }
    static var serif: Font.Design { .serif }
}

// Floating white card, soft diffuse shadow — the reference card look.
struct ListrCard: ViewModifier {
    var radius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .background(ListrTheme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.07), radius: 22, y: 10)
            .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
    }
}

extension View {
    func listrCard(radius: CGFloat = 20) -> some View {
        modifier(ListrCard(radius: radius))
    }
}

// Pill chip: icon + text on a light gray capsule (reference "1.2k followers" chips).
struct ListrChip: View {
    let text: String
    var icon: String? = nil
    var fill: Color = ListrTheme.chip
    var tint: Color = ListrTheme.ink

    var body: some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
            }
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(fill, in: Capsule())
    }
}

// Playback track: click or drag anywhere on it to seek.
struct ListrScrubber: View {
    let progress: Double
    let onSeek: (Double) -> Void
    var barHeight: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(ListrTheme.chip)
                Capsule()
                    .fill(ListrTheme.ink)
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
            }
            .frame(height: barHeight)
            .frame(maxHeight: .infinity) // center the bar in a taller hit area
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { value in
                    guard geo.size.width > 0 else { return }
                    onSeek(value.location.x / geo.size.width)
                }
            )
        }
        .frame(height: 16)
    }
}

// Playback speed picker shown as a pill chip.
struct ListrSpeedMenu: View {
    @Binding var speed: Double
    let onChange: (Double) -> Void

    private static let options: [Double] = [0.75, 1, 1.25, 1.5, 1.75, 2]
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    var body: some View {
        Menu {
            ForEach(Self.options, id: \.self) { option in
                Button {
                    speed = option
                    onChange(option)
                } label: {
                    Text(option == speed ? "✓ \(Self.label(option))" : Self.label(option))
                }
            }
        } label: {
            ListrChip(text: Self.label(speed), icon: "speedometer")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Playback speed")
    }

    private static func label(_ value: Double) -> String {
        (formatter.string(from: value as NSNumber) ?? "1") + "×"
    }
}

// Black pill primary button (reference "Share" / "Save changes").
struct ListrPillButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .lineLimit(1)
            .fixedSize() // keep the label on one line when the row runs out of width
            .foregroundStyle(prominent ? Color.white : ListrTheme.ink)
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(prominent ? ListrTheme.ink : ListrTheme.chip, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
