import SwiftUI

// Cover Flow: the centered cover faces you, the others turn toward it from both sides and
// stand on a glossy black floor. Swipe, scroll, drag the slider or press ← → to flip through;
// click the centered cover (or press Return) to open it, a side cover to bring it forward.
struct CoverFlowView: View {
    @Environment(PlaybackStore.self) private var playbackStore

    let books: [Book]
    let onOpen: (Book) -> Void

    @State private var centeredID: Book.ID?
    @FocusState private var isFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let height = max(min((geo.size.height - 150) / 1.35, 340), 120)
            let size = CGSize(width: height * 0.75, height: height)
            let step = size.width * 0.42 // distance between neighbours on the side stacks
            let centerIndex = books.firstIndex { $0.id == centeredID } ?? 0
            let viewport = geo.size.width

            VStack(spacing: 18) {
                Spacer(minLength: 0)

                ScrollView(.horizontal) {
                    // ponytail: plain HStack, as LazyHStack ignores zIndex and the stacks would overlap
                    // the wrong way round. Every cover is laid out; switch to a windowed range past ~1000 books.
                    HStack(spacing: step - size.width) {
                        ForEach(Array(books.enumerated()), id: \.element.id) { index, book in
                            CoverFlowItem(book: book, size: size)
                                .visualEffect { content, proxy in
                                    // -1…1 across the first neighbour on each side, then held.
                                    let distance = (proxy.frame(in: .scrollView(axis: .horizontal)).midX - viewport / 2) / step
                                    let turn = min(max(distance, -1), 1)
                                    return content
                                        .rotation3DEffect(.degrees(-turn * 62), axis: (0, 1, 0), perspective: 0.6)
                                        .scaleEffect(1 - abs(turn) * 0.14, anchor: .bottom)
                                        .offset(x: turn * size.width * 0.42) // clear room around the centered cover
                                }
                                .zIndex(-Double(abs(index - centerIndex)))
                                .onTapGesture { select(book) }
                                .accessibilityAddTraits(.isButton)
                                .accessibilityLabel("\(book.title), \(book.author)")
                        }
                    }
                    .scrollTargetLayout()
                }
                .contentMargins(.horizontal, (viewport - size.width) / 2, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $centeredID, anchor: .center)
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .frame(height: size.height * 1.32)

                caption

                if books.count > 1 {
                    Slider(value: sliderValue(centerIndex), in: 0...Double(books.count - 1))
                        .controlSize(.small)
                        .frame(maxWidth: 360)
                        .accessibilityLabel("Browse books")
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .background {
            LinearGradient(colors: [.black, Color(white: 0.09)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea() // under the toolbar, sidebar and player as well
        }
        .environment(\.colorScheme, .dark) // Cover Flow is always on black
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.leftArrow) { move(-1) }
        .onKeyPress(.rightArrow) { move(1) }
        .onKeyPress(.return) {
            guard let book = centeredBook else { return .ignored }
            onOpen(book)
            return .handled
        }
        .onAppear {
            // Start on the book being listened to, if it is on the shelf.
            centeredID = books.first { $0.id == playbackStore.currentBookID }?.id ?? centeredID ?? books.first?.id
            isFocused = true
        }
        .onChange(of: books.map(\.id)) { _, ids in
            if let centeredID, ids.contains(centeredID) { return }
            centeredID = ids.first
        }
    }

    private var centeredBook: Book? {
        books.first { $0.id == centeredID }
    }

    @ViewBuilder private var caption: some View {
        VStack(spacing: 3) {
            Text(centeredBook?.title ?? " ")
                .font(.headline)
                .foregroundStyle(.primary)
            Text(centeredBook?.author ?? " ")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .padding(.horizontal, 40)
        .contentTransition(.opacity)
        .animation(.easeOut(duration: 0.15), value: centeredID)
    }

    private func select(_ book: Book) {
        if book.id == centeredID {
            onOpen(book)
        } else {
            withAnimation(.smooth(duration: 0.35)) { centeredID = book.id }
        }
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard !books.isEmpty else { return .ignored }
        let index = (books.firstIndex { $0.id == centeredID } ?? 0) + delta
        guard books.indices.contains(index) else { return .handled }
        withAnimation(.smooth(duration: 0.3)) { centeredID = books[index].id }
        return .handled
    }

    private func sliderValue(_ centerIndex: Int) -> Binding<Double> {
        Binding(
            get: { Double(centerIndex) },
            set: { value in
                let index = min(max(Int(value.rounded()), 0), books.count - 1)
                guard books[index].id != centeredID else { return }
                withAnimation(.smooth(duration: 0.2)) { centeredID = books[index].id }
            }
        )
    }
}

// One cover and its reflection on the floor.
private struct CoverFlowItem: View {
    let book: Book
    let size: CGSize

    var body: some View {
        VStack(spacing: 2) {
            cover
            cover
                .scaleEffect(x: 1, y: -1)
                .frame(height: size.height * 0.3, alignment: .top) // the flipped bottom edge
                .clipped()
                .mask(LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    private var cover: some View {
        ListrCover(seed: book.title, imagePath: book.coverPath, cornerRadius: 2)
            .frame(width: size.width, height: size.height)
    }
}
