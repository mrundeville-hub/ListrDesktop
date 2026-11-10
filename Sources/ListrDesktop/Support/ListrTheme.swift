import SwiftUI

// "Air" look: near-white canvas with a faint colored glow, monochrome controls, system type.
// Color comes from the book covers, not from the chrome.
enum ListrTheme {
    static let paper = Color(listrHex: 0xF5F5F7)
    static let ink = Color(listrHex: 0x1D1D1F)
    static let mutedLabel = Color(listrHex: 0x6E6E73)
    static let fill = ink.opacity(0.06)                // resting control / row fill
    static let highlight = Color(listrHex: 0xC9B8FF)   // spoken-word wash
}

extension Color {
    init(listrHex hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension View {
    /// Window-level setup shared by the main window, the floating player and Settings.
    func listrWindowStyle() -> some View {
        tint(ListrTheme.ink)
            .preferredColorScheme(.light) // palette is light-only
    }
}

// Window background: paper with three very soft blobs of color, like light through frosted glass.
struct ListrBackdrop: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ListrTheme.paper
                blob(0xFFB8DC, x: 0.18, y: 0.10, in: geo.size)
                blob(0xC9B8FF, x: 0.85, y: 0.25, in: geo.size)
                blob(0xFFDCC0, x: 0.55, y: 0.95, in: geo.size)
            }
        }
        .ignoresSafeArea()
    }

    private func blob(_ hex: UInt32, x: CGFloat, y: CGFloat, in size: CGSize) -> some View {
        Circle()
            .fill(Color(listrHex: hex).opacity(0.28))
            .frame(width: size.width * 0.5, height: size.width * 0.5)
            .blur(radius: 110)
            .position(x: size.width * x, y: size.height * y)
    }
}

// Generated cover: an iridescent blur whose hues are fixed by the book title.
struct ListrCover: View {
    let seed: String
    var cornerRadius: CGFloat = 20

    var body: some View {
        // Stable across launches (String.hashValue is reseeded per process).
        let hash = seed.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 3600 }
        let hue = Double(hash % 360) / 360

        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .fill(Color(hue: (hue + 0.10).truncatingRemainder(dividingBy: 1), saturation: 0.40, brightness: 1))
                    .frame(width: side * 0.9)
                    .offset(x: -side * 0.22, y: side * 0.28)
                Circle()
                    .fill(Color(hue: (hue + 0.85).truncatingRemainder(dividingBy: 1), saturation: 0.36, brightness: 1))
                    .frame(width: side * 0.7)
                    .offset(x: side * 0.28, y: -side * 0.20)
                Circle()
                    .fill(.white.opacity(0.85))
                    .frame(width: side * 0.35)
                    .offset(x: side * 0.05, y: side * 0.02)
            }
            .blur(radius: side * 0.14)
            .frame(width: geo.size.width, height: geo.size.height)
            .background(Color(hue: hue, saturation: 0.10, brightness: 0.97)) // unblurred, so the edge stays crisp
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

// Title-bar row that sits level with the traffic lights: actions left and right, title centered.
struct ListrTopBar<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ListrTheme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(ListrTheme.mutedLabel)
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 230)

            HStack(spacing: 8) {
                leading
                Spacer()
                trailing
            }
        }
        .padding(.leading, 84) // clears the traffic lights
        .padding(.trailing, 16)
        .frame(height: 36)
    }
}

// Round icon button. Plain shows its circle on hover only; prominent is the one black button.
struct ListrIconButtonStyle: ButtonStyle {
    enum Kind { case plain, filled, prominent }

    var size: CGFloat = 32
    var kind: Kind = .plain

    func makeBody(configuration: Configuration) -> some View {
        ListrButtonBody(configuration: configuration, kind: kind, shape: Circle()) { label in
            label
                .font(.system(size: size * 0.42, weight: .medium))
                .frame(width: size, height: size)
        }
    }
}

// Text button in a capsule.
struct ListrCapsuleButtonStyle: ButtonStyle {
    var prominent = false
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        ListrButtonBody(configuration: configuration, kind: prominent ? .prominent : .filled, shape: Capsule()) { label in
            label
                .font(.system(size: large ? 15 : 13, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, large ? 22 : 14)
                .frame(height: large ? 40 : 30)
        }
    }
}

// Shared hover / press / disabled behaviour so every button in the app answers the same way.
private struct ListrButtonBody<S: Shape, Content: View>: View {
    let configuration: ButtonStyleConfiguration
    let kind: ListrIconButtonStyle.Kind
    let shape: S
    @ViewBuilder let content: (ButtonStyleConfiguration.Label) -> Content

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        content(configuration.label)
            .foregroundStyle(kind == .prominent ? Color.white : ListrTheme.ink)
            .background(background, in: shape)
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(isEnabled ? 1 : 0.3)
            .onHover { isHovered = $0 }
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    private var background: Color {
        switch kind {
        case .prominent: ListrTheme.ink.opacity(isHovered ? 0.82 : 1)
        case .filled: ListrTheme.ink.opacity(isHovered ? 0.11 : 0.06)
        case .plain: ListrTheme.ink.opacity(isHovered ? 0.07 : 0)
        }
    }
}

// Playback track: click or drag anywhere on it to seek. Thickens under the pointer.
struct ListrScrubber: View {
    let progress: Double
    let onSeek: (Double) -> Void

    @State private var isHovered = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(ListrTheme.ink.opacity(0.1))
                Capsule()
                    .fill(ListrTheme.ink)
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
            }
            .frame(height: isHovered ? 6 : 4)
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
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

// Playback speed picker.
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
            Picker("Playback speed", selection: $speed) {
                ForEach(Self.options, id: \.self) { option in
                    Text(Self.label(option)).tag(option)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Text(Self.label(speed))
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(ListrTheme.ink)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(ListrTheme.fill, in: Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain) // keeps the label's own capsule instead of a stock menu button
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Playback speed")
        .onChange(of: speed) { _, newValue in onChange(newValue) }
    }

    private static func label(_ value: Double) -> String {
        (formatter.string(from: value as NSNumber) ?? "1") + "×"
    }
}

extension PlaybackStore {
    /// The passage around the spoken word: what was read is solid, what is coming is faded,
    /// and the word itself gets a soft wash (no weight change, so the text never reflows).
    func highlightedSnippet(fontSize: CGFloat, before: Int, after: Int) -> AttributedString {
        let source = currentText
        let font = Font.system(size: fontSize)

        guard
            let word = currentWord,
            let range = Range(NSRange(location: word.location, length: word.length), in: source)
        else {
            var preview = AttributedString(String(source.prefix(before + after)))
            preview.foregroundColor = ListrTheme.ink.opacity(0.6)
            preview.font = font
            return preview
        }

        let start = source.index(range.lowerBound, offsetBy: -before, limitedBy: source.startIndex) ?? source.startIndex
        let end = source.index(range.upperBound, offsetBy: after, limitedBy: source.endIndex) ?? source.endIndex

        var read = AttributedString((start == source.startIndex ? "" : "…") + source[start..<range.lowerBound])
        read.foregroundColor = ListrTheme.ink

        var spoken = AttributedString(source[range])
        spoken.foregroundColor = ListrTheme.ink
        spoken.backgroundColor = ListrTheme.highlight.opacity(0.7)

        var upcoming = AttributedString(source[range.upperBound..<end] + (end == source.endIndex ? "" : "…"))
        upcoming.foregroundColor = ListrTheme.ink.opacity(0.38)

        var snippet = read + spoken + upcoming
        snippet.font = font
        return snippet
    }
}
