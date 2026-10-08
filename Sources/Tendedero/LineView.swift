import SwiftUI

enum Layout {
    static let baseHeight: CGFloat = 210
    /// How much a photo grows while the pointer rests on it, and how far
    /// scrolling over it can take it.
    static let zoom: CGFloat = 2
    static let maxZoom: CGFloat = 3.5
    /// Zooming needs room below the cards. The extra strip is see through
    /// and lets clicks through, like the rest of the panel.
    static var panelHeight: CGFloat { Line.zoomOnHover ? 470 : baseHeight }
    static let ropeTop: CGFloat = 10
    static let spacing: CGFloat = 174
    static let cardWidth: CGFloat = 150
    static let pinAbove: CGFloat = 9.5

    /// The rope hangs as a parabola from edge to edge of the screen.
    static func sag(width: CGFloat) -> CGFloat { min(30, width * 0.018) }

    static func ropeY(x: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return ropeTop }
        let f = x / width
        return ropeTop + 4 * sag(width: width) * f * (1 - f)
    }

    /// How far the neighbours of a zoomed photo step aside to make room.
    static func push(for imageSize: CGSize, zoom: CGFloat) -> CGFloat {
        let zoomed = PeggedView.cardSize(for: imageSize, zoom: zoom).width
        return max(0, zoomed / 2 + cardWidth / 2 + 14 - spacing)
    }

    static func x(index: Int, count: Int, width: CGFloat) -> CGFloat {
        let total = CGFloat(max(count - 1, 0)) * spacing
        return width / 2 - total / 2 + CGFloat(index) * spacing
    }
}

struct LineView: View {
    @ObservedObject var line: Line

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let zoomIndex = line.zoomedID.flatMap { id in line.items.firstIndex { $0.id == id } }
            let push = zoomIndex.map { Layout.push(for: line.items[$0].thumb.size, zoom: line.zoomLevel) } ?? 0
            ZStack(alignment: .topLeading) {
                Rope(width: width)

                if line.items.isEmpty {
                    Hint()
                        .position(x: width / 2, y: Layout.ropeY(x: width / 2, width: width) + 34)
                        .transition(.opacity)
                }

                // Only what is on screen, or about to be, is drawn.
                ForEach(Array(line.items.enumerated()).filter { line.place(of: $0.offset, width: width).overflow < 2 },
                        id: \.element.id) { index, item in
                    let shift = zoomIndex.map { index < $0 ? -push : (index > $0 ? push : 0) } ?? 0
                    let place = line.place(of: index, width: width)
                    let x = place.x + shift
                    let ropeY = Layout.ropeY(x: x, width: width)
                    PeggedView(item: item, line: line, hidden: place.overflow >= 0.5)
                        .opacity(Double(max(0, 1 - place.overflow)))
                        .frame(width: Layout.cardWidth, height: Layout.panelHeight - ropeY, alignment: .top)
                        .position(x: x, y: ropeY - Layout.pinAbove + (Layout.panelHeight - ropeY) / 2)
                        .zIndex(line.zoomedID == item.id ? 1 : 0)
                }

                // Mouse friendly: arrows at the ends step through a long line.
                if line.maxOffset > 0 {
                    let y = Layout.ropeY(x: 40, width: width) + 70
                    LineArrow(symbol: "chevron.left", id: LineArrow.olderID, line: line) { line.step(by: 3) }
                        .position(x: 40, y: y)
                        .opacity(line.offset < line.maxOffset ? 1 : 0)
                        .zIndex(2)
                    LineArrow(symbol: "chevron.right", id: LineArrow.newerID, line: line) { line.step(by: -3) }
                        .position(x: width - 40, y: y)
                        .opacity(line.offset > 0 ? 1 : 0)
                        .zIndex(2)
                }
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.78), value: line.items.map(\.id))
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.86), value: line.offset)
            // The neighbours of a zoomed photo slide aside, like the Dock.
            .animation(.spring(response: 0.34, dampingFraction: 0.78), value: line.zoomedID)
            .animation(.easeInOut(duration: 0.3), value: line.items.isEmpty)
            // Tucked away, the whole line waits above the top edge and slides
            // out from under the menu bar, the way an auto-hiding Dock does.
            .offset(y: line.revealed ? 0 : -(Layout.panelHeight + 12))
            .animation(line.revealed ? .spring(response: 0.42, dampingFraction: 0.82)
                                     : .easeIn(duration: 0.22), value: line.revealed)
        }
        .onPreferenceChange(HitRectsKey.self) { rects in
            line.hitRects = rects
        }
    }
}

/// A round glass button at one end of the line. It reports its frame like
/// a card does, so the panel catches clicks over it.
private struct LineArrow: View {
    static let olderID = UUID()
    static let newerID = UUID()

    let symbol: String
    let id: UUID
    @ObservedObject var line: Line
    let action: () -> Void

    var body: some View {
        let active = id == LineArrow.olderID ? line.offset < line.maxOffset : line.offset > 0
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.primary)
            .frame(width: 34, height: 34)
            .glassFrame(circle: true)
            .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
            .overlay(ClickArea(action: action))
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: HitRectsKey.self, value: active ? [id: g.frame(in: .global)] : [:])
                }
            )
            .allowsHitTesting(active)
    }
}

/// Takes a click even though the panel never becomes active.
struct ClickArea: NSViewRepresentable {
    let action: () -> Void
    func makeNSView(context: Context) -> ClickView { let v = ClickView(); v.action = action; return v }
    func updateNSView(_ view: ClickView, context: Context) { view.action = action }

    final class ClickView: NSView {
        var action: (() -> Void)?
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) {}
        override func mouseUp(with event: NSEvent) {
            if bounds.contains(convert(event.locationInWindow, from: nil)) { action?() }
        }
    }
}

private struct Hint: View {
    var body: some View {
        Text(L("Take a screenshot and it will hang here"))
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
    }
}

/// A thin, neutral line: a mid gray core with a faint highlight and a soft
/// shadow, so it reads on light and dark backgrounds alike. It fades out at
/// both ends so it seems to come from beyond the screen.
struct Rope: View {
    let width: CGFloat

    private var path: Path {
        Path { p in
            let top = Layout.ropeTop
            p.move(to: CGPoint(x: -20, y: top))
            p.addQuadCurve(
                to: CGPoint(x: width + 20, y: top),
                control: CGPoint(x: width / 2, y: top + 2 * Layout.sag(width: width)))
        }
    }

    var body: some View {
        ZStack {
            path.stroke(Color.black.opacity(0.22), lineWidth: 1.4).offset(y: 1.2).blur(radius: 1.2)
            path.stroke(Color(white: 0.55), lineWidth: 1.2)
            path.stroke(Color.white.opacity(0.45), lineWidth: 0.4).offset(y: -0.35)
        }
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.08),
                .init(color: .black, location: 0.92),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        )
        .allowsHitTesting(false)
    }
}

struct HitRectsKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}
