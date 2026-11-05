import AppKit
import SwiftUI

enum MantisPalette {
    static let background: UInt32 = 0x12231D
    static let surface: UInt32 = 0x1D342B
    static let border: UInt32 = 0x3B5947
    static let pink: UInt32 = 0xE8CFD4 // Exact light pink from the app icon.
    static let green: UInt32 = 0xA6CC82
    static let text: UInt32 = 0xEDF2E7
    static let secondary: UInt32 = 0xB2C1B5
}

enum MantisTheme {
    static func color(_ value: UInt32) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 255) / 255,
              green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
    static let background = color(MantisPalette.background)
    static let surface = color(MantisPalette.surface)
    static let border = color(MantisPalette.border)
    static let pink = color(MantisPalette.pink)
    static let green = color(MantisPalette.green)
    static let text = color(MantisPalette.text)
    static let secondary = color(MantisPalette.secondary)

    /// Small immutable procedural tile; no timers, network, or per-frame noise generation.
    static let grain: CGImage? = {
        let side = 128
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        var seed: UInt32 = 0x4D414E54
        for pixel in 0..<(side * side) {
            seed = 1_664_525 &* seed &+ 1_013_904_223
            let level = UInt8((seed >> 24) & 255)
            bytes[pixel * 4] = level
            bytes[pixel * 4 + 1] = level
            bytes[pixel * 4 + 2] = level
            bytes[pixel * 4 + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }()
}

struct MantisBrandMark: View {
    var size: CGFloat = 28
    private static let template = Bundle.main.url(forResource: "MantisTemplate", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        Group {
            if let image = Self.template {
                Image(nsImage: image).resizable().renderingMode(.template).scaledToFit()
                    .foregroundStyle(MantisTheme.pink)
            } else {
                // Same geometry as Resources/Brand/mantis-head.svg, for offscreen previews.
                Canvas { context, size in
                    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                        CGPoint(x: (32 + 1.8 * (x - 32)) * size.width / 64,
                                y: (32 + 1.8 * (y - 17)) * size.height / 64)
                    }
                    var antennae = Path()
                    antennae.move(to: point(26, 16)); antennae.addLine(to: point(22, 9))
                    antennae.move(to: point(38, 16)); antennae.addLine(to: point(42, 9))
                    context.stroke(antennae, with: .color(MantisTheme.pink),
                                   style: StrokeStyle(lineWidth: 3.5 * 1.8 * size.width / 64, lineCap: .round))
                    var head = Path()
                    head.move(to: point(21, 16)); head.addQuadCurve(to: point(43, 16), control: point(32, 11))
                    head.addLine(to: point(34, 25)); head.addQuadCurve(to: point(30, 25), control: point(32, 27)); head.closeSubpath()
                    context.fill(head, with: .color(MantisTheme.pink))
                    context.blendMode = .destinationOut
                    for x in [CGFloat(25), CGFloat(36)] {
                        let center = point(x, 17)
                        let diameter = 3 * 1.8 * size.width / 64
                        context.fill(Path(ellipseIn: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                                                            width: diameter, height: diameter)), with: .color(.black))
                    }
                }.compositingGroup()
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct MantisBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            MantisTheme.background
            if !reduceMotion, !reduceTransparency, let grain = MantisTheme.grain {
                Image(decorative: grain, scale: 1)
                    .resizable(resizingMode: .tile).interpolation(.none)
                    .blendMode(.softLight).opacity(0.12)
            }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}

private struct MantisAppearance: ViewModifier {
    func body(content: Content) -> some View {
        content.background { MantisBackground() }
            .preferredColorScheme(.dark).tint(MantisTheme.green)
            .foregroundStyle(MantisTheme.text)
    }
}

private struct MantisCard: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.padding(14)
            .background(MantisTheme.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(contrast == .increased ? MantisTheme.secondary : MantisTheme.border, lineWidth: 1))
    }
}

extension View {
    func mantisAppearance() -> some View { modifier(MantisAppearance()) }
    func mantisCard() -> some View { modifier(MantisCard()) }
}
