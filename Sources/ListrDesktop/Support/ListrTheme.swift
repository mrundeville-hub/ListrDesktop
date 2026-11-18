import SwiftUI

// Native macOS look: system colors and the user's accent color, so light/dark mode, Increase
// Contrast and accent changes all follow System Settings. Color comes from the book covers.
enum ListrTheme {
    static let paper = Color(nsColor: .windowBackgroundColor)
    static let ink = Color(nsColor: .labelColor)
    static let mutedLabel = Color(nsColor: .secondaryLabelColor)
    static let fill = Color(nsColor: .quaternaryLabelColor)       // resting control fill
    static let highlight = Color.accentColor.opacity(0.35)        // spoken-word wash
}

// A book's cover: its own picture when the file had one, else an iridescent blur whose hues
// are fixed by the book title.
struct ListrCover: View {
    let seed: String
    var imagePath: String? = nil
    var cornerRadius: CGFloat = 6

    var body: some View {
        Group {
            if let image = CoverImages.image(at: imagePath) {
                // Fills whatever frame the caller gives, cropping the overflow.
                Color.clear.overlay {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                }
            } else {
                generated
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }

    private var generated: some View {
        // Stable across launches (String.hashValue is reseeded per process).
        let hash = seed.unicodeScalars.reduce(7) { ($0 &* 31 &+ Int($1.value)) % 3600 }
        let hue = Double(hash % 360) / 360

        return GeometryReader { geo in
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
        .drawingGroup() // three big blurs: flatten them once instead of per frame (grid hover, Cover Flow)
    }
}

/// Cover files decoded once, at thumbnail size: a library can hold hundreds of them.
@MainActor
private enum CoverImages {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(at path: String?) -> NSImage? {
        guard let path else { return nil }
        if let cached = cache.object(forKey: path as NSString) { return cached }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 640
        ]
        guard
            let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
            let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let image = NSImage(cgImage: thumbnail, size: .zero)
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}

// Round icon button for the player: a bare glyph, its circle shows on hover. Prominent is the
// bigger play glyph.
struct ListrIconButtonStyle: ButtonStyle {
    enum Kind { case plain, prominent }

    var size: CGFloat = 32
    var kind: Kind = .plain

    func makeBody(configuration: Configuration) -> some View {
        ListrButtonBody(configuration: configuration, kind: kind, shape: Circle()) { label in
            label
                .font(.system(size: size * (kind == .prominent ? 0.55 : 0.42), weight: kind == .prominent ? .semibold : .medium))
                .frame(width: size, height: size)
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
            .foregroundStyle(ListrTheme.ink)
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
        case .prominent: ListrTheme.ink.opacity(isHovered ? 0.07 : 0)
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

extension View {
    /// Makes the word links of `highlightedPage` seek instead of opening a browser.
    func listrSeeksOnWordClick(_ playbackStore: PlaybackStore) -> some View {
        environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "listr-seek", let time = Double(url.absoluteString.dropFirst("listr-seek:".count)) else {
                return .systemAction
            }
            playbackStore.seek(toTime: time)
            return .handled
        })
    }
}

// Sleep timer: stop after a while, or when the chapter ends.
struct ListrSleepMenu: View {
    @Environment(PlaybackStore.self) private var playbackStore

    var body: some View {
        Menu {
            if case .at(let deadline) = playbackStore.sleepTimer {
                Text("Stops at \(deadline.formatted(date: .omitted, time: .shortened))")
            } else if playbackStore.sleepTimer == .endOfChapter {
                Text("Stops when this chapter ends")
            }
            ForEach([15, 30, 45, 60], id: \.self) { minutes in
                Button("In \(minutes) minutes") { playbackStore.sleep(afterMinutes: minutes) }
            }
            Button("At the end of the chapter") { playbackStore.sleepTimer = .endOfChapter }
            if isOn {
                Divider()
                Button("Turn Off") { playbackStore.sleepTimer = .off }
            }
        } label: {
            Image(systemName: isOn ? "moon.fill" : "moon")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(ListrTheme.ink)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(isOn ? "Sleep timer is on" : "Sleep timer")
    }

    private var isOn: Bool { playbackStore.sleepTimer != .off }
}
