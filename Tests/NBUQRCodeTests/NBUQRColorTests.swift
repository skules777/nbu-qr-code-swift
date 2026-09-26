import CoreGraphics
import CoreImage
import XCTest
@testable import NBUQRCode
@testable import NBUQRCodeImage

final class NBUQRColorTests: XCTestCase {
    private let black = [0, 0, 0], white = [255, 255, 255], green = [0x00, 0x7B, 0x47]

    func testHexParsing() {
        XCTAssertEqual(NBUQRColor(hex: "#007B47"), .nbuGreen)
        XCTAssertEqual(NBUQRColor(hex: "000000"), .black)
        XCTAssertNil(NBUQRColor(hex: "#007B4"))
        XCTAssertNil(NBUQRColor(hex: "#007B4G"))
        XCTAssertNil(NBUQRColor(hex: "+07B47"))
    }

    func testDefaultRenderingStaysBlack() throws {
        let image = try Rendered(NBUQRImageRenderer(), payload: NBUQRPayload(officialOnlineStorePayment()))
        for finder in image.finders {
            assertClose(image.color(atModule: finder.center), black)
        }
        assertClose(image.dominantSignColor(), black)
        assertClose(image.dominantDataModuleColor(), black)
    }

    // Як на bank.gov.ua/ua/payments/use-qr: акцент фарбує знак і центри 3×3 шукових
    // візерунків; їхня зовнішня рамка й усі інші модулі лишаються чорними.
    func testAccentPaintsSignAndFinderCentersOnly() throws {
        let renderer = NBUQRImageRenderer(accentColor: .nbuGreen)
        let image = try Rendered(renderer, payload: NBUQRPayload(officialOnlineStorePayment()))

        for finder in image.finders {
            for dx in -1...1 {
                for dy in -1...1 {
                    assertClose(image.color(atModule: (finder.center.0 + Double(dx), finder.center.1 + Double(dy))), green)
                }
            }
            assertClose(image.color(atModule: finder.whiteRing), white)
            assertClose(image.color(atModule: finder.outerRing), black)
        }
        assertClose(image.dominantSignColor(), green)
        assertClose(image.dominantDataModuleColor(), black)
        XCTAssertFalse(image.bottomRightCornerContains(green), "the bottom-right corner has no finder pattern")
        XCTAssertEqual(try decode(renderer), try qrURL(officialOnlineStorePayment()).absoluteString)
    }

    func testCustomDarkAccentStillScans() throws {
        let navy = try XCTUnwrap(NBUQRColor(hex: "#1A237E"))
        let renderer = NBUQRImageRenderer(accentColor: navy)
        let image = try Rendered(renderer, payload: NBUQRPayload(officialOnlineStorePayment()))
        assertClose(image.color(atModule: image.finders[0].center), [0x1A, 0x23, 0x7E])
        XCTAssertEqual(try decode(renderer), try qrURL(officialOnlineStorePayment()).absoluteString)
    }

    // За центрами шукових візерунків сканер знаходить код, тож блідий акцент зламав би
    // розпізнавання, а не просто виглядав би блякло.
    func testTooLightAccentIsRejected() {
        let lightGrey = NBUQRColor(hex: "#9E9E9E")!
        XCTAssertThrowsError(try NBUQRImageRenderer(accentColor: lightGrey).cgImage(for: NBUQRPayload(officialOnlineStorePayment()))) { error in
            guard case NBUQRImageError.insufficientAccentContrast(let contrast, let minimum) = error else {
                return XCTFail("unexpected error \(error)")
            }
            XCTAssertLessThan(contrast, minimum)
        }
    }

    // MARK: - Допоміжне

    private func decode(_ renderer: NBUQRImageRenderer) throws -> String? {
        let image = CIImage(cgImage: try renderer.cgImage(for: NBUQRPayload(officialOnlineStorePayment())))
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        return (detector?.features(in: image).first as? CIQRCodeFeature)?.messageString
    }

    private func assertClose(_ actual: [Int], _ expected: [Int], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, 3, file: file, line: line)
        for (a, e) in zip(actual, expected) {
            XCTAssertLessThanOrEqual(abs(a - e), 1, "got \(actual), expected \(expected)", file: file, line: line)
        }
    }
}

/// Відрендерене зображення, прочитане як sRGB-пікселі й адресоване в модулях "голої"
/// QR-матриці (початок у її верхньому лівому куті, y вниз).
private struct Rendered {
    typealias Point = (Double, Double)
    struct Finder { let center: Point; let whiteRing: Point; let outerRing: Point }

    let side: Int
    let rgba: [UInt8]
    let module: Double
    let matrixOrigin: Double
    let matrixModules: Int
    let backgroundRadius: Double
    let signRadius: Double

    init(_ renderer: NBUQRImageRenderer, payload: NBUQRPayload) throws {
        let image = try renderer.cgImage(for: payload)
        side = image.width
        var buffer = [UInt8](repeating: 0, count: side * side * 4)
        let context = try XCTUnwrap(CGContext(
            data: &buffer, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        rgba = buffer

        module = Double(renderer.moduleSize)
        matrixOrigin = Double(renderer.quietZoneModules) * module
        matrixModules = side / renderer.moduleSize - 2 * renderer.quietZoneModules
        let version = (matrixModules - 17) / 4
        backgroundRadius = Double(NBUQRImageRenderer.backgroundCircleDiameterModules(forVersion: version)) * module / 2
        signRadius = backgroundRadius * Double(NBUQRImageRenderer.signToBackgroundCircleRatio)
    }

    var finders: [Finder] {
        let far = Double(matrixModules - 7)
        return [(0.0, 0.0), (far, 0.0), (0.0, far)].map { x, y in
            Finder(center: (x + 3.5, y + 3.5), whiteRing: (x + 1.5, y + 3.5), outerRing: (x + 0.5, y + 3.5))
        }
    }

    func color(atModule point: Point) -> [Int] {
        pixel(Int(matrixOrigin + point.0 * module), Int(matrixOrigin + point.1 * module))
    }

    func dominantSignColor() -> [Int] {
        dominant { distanceFromCenter($0, $1) < signRadius }
    }

    /// Модулі поза фоновим колом і поза трьома шуковими візерунками.
    func dominantDataModuleColor() -> [Int] {
        dominant { x, y in
            let mx = (Double(x) - matrixOrigin) / module, my = (Double(y) - matrixOrigin) / module
            let far = Double(matrixModules - 8)
            let inFinder = (mx < 8 || mx >= far) && (my < 8 || my >= far) && !(mx >= far && my >= far)
            return !inFinder && distanceFromCenter(x, y) > backgroundRadius + module
        }
    }

    func bottomRightCornerContains(_ color: [Int]) -> Bool {
        let start = Int(matrixOrigin + Double(matrixModules - 8) * module)
        let end = Int(matrixOrigin + Double(matrixModules) * module)
        for y in start..<end {
            for x in start..<end where zip(pixel(x, y), color).allSatisfy({ abs($0 - $1) <= 1 }) { return true }
        }
        return false
    }

    private func pixel(_ x: Int, _ y: Int) -> [Int] {
        let i = (y * side + x) * 4
        return [Int(rgba[i]), Int(rgba[i + 1]), Int(rgba[i + 2])]
    }

    private func distanceFromCenter(_ x: Int, _ y: Int) -> Double {
        let center = Double(side) / 2
        return hypot(Double(x) + 0.5 - center, Double(y) + 0.5 - center)
    }

    private func dominant(where include: (Int, Int) -> Bool) -> [Int] {
        var counts: [[Int]: Int] = [:]
        for y in 0..<side {
            for x in 0..<side where include(x, y) {
                let color = pixel(x, y)
                if color != [255, 255, 255] { counts[color, default: 0] += 1 }
            }
        }
        return counts.max { $0.value < $1.value }?.key ?? []
    }
}
