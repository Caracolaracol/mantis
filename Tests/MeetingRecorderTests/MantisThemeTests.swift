import XCTest
@testable import MeetingRecorder

final class MantisThemeTests: XCTestCase {
    private func luminance(_ color: UInt32) -> Double {
        let channels = [16, 8, 0].map { shift -> Double in
            let value = Double((color >> shift) & 255) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
    }

    func testPaletteKeepsIconPinkAndReadableText() {
        XCTAssertEqual(MantisPalette.pink, 0xE8CFD4)
        for foreground in [MantisPalette.text, MantisPalette.secondary, MantisPalette.pink, MantisPalette.green] {
            for background in [MantisPalette.background, MantisPalette.surface] {
                let ratio = (max(luminance(foreground), luminance(background)) + 0.05)
                    / (min(luminance(foreground), luminance(background)) + 0.05)
                XCTAssertGreaterThanOrEqual(ratio, 4.5)
            }
        }
    }

    func testGrainIsSmallFixedTile() throws {
        let image = try XCTUnwrap(MantisTheme.grain)
        XCTAssertEqual(image.width, 128)
        XCTAssertEqual(image.height, 128)
    }
}
