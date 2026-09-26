import CoreGraphics
import XCTest
@testable import NBUQRCode
@testable import NBUQRCodeImage

final class NBUHryvniaSignTests: XCTestCase {
    // Частка описаного кола, яку покриває протрасований знак, виміряна на самому
    // контурі. Ловить випадок, коли знак мовчки зникає чи змінює товщину.
    private let inkShareOfEnclosingCircle = 0.4324
    // Контур центрований на своїй рамці, а не на описаному колі, тож його найдальша
    // точка лежить трохи за радіусом 1.
    private let farthestPointFromBoxCenter: CGFloat = 1.0027

    func testOutlineIsCenteredOnItsBoundingBox() {
        let points = sampledPoints(of: NBUHryvniaSign.path(enclosingRadius: 1, centeredAt: .zero))
        let xs = points.map(\.x), ys = points.map(\.y)
        XCTAssertEqual((xs.min()! + xs.max()!) / 2, 0, accuracy: 0.001)
        XCTAssertEqual((ys.min()! + ys.max()!) / 2, 0, accuracy: 0.001)
        XCTAssertEqual(points.map { hypot($0.x, $0.y) }.max()!, farthestPointFromBoxCenter, accuracy: 0.001)
    }

    // Розмір і положення — як у прикладах додатка 4: рамка знака центрована на фоновому
    // колі, а радіус описаного кола — фіксована частка радіуса цього кола.
    func testRenderedSignMatchesTheExamplesProportions() throws {
        let renderer = NBUQRImageRenderer()
        let image = try renderer.cgImage(for: NBUQRPayload(officialOnlineStorePayment()))
        let pixels = try grayPixels(of: image)
        let side = image.width
        let module = CGFloat(renderer.moduleSize)

        let matrixModules = side / renderer.moduleSize - 2 * renderer.quietZoneModules
        let version = (matrixModules - 17) / 4
        let backgroundRadius = CGFloat(NBUQRImageRenderer.backgroundCircleDiameterModules(forVersion: version)) * module / 2
        let signRadius = backgroundRadius * NBUQRImageRenderer.signToBackgroundCircleRatio
        let signExtent = signRadius * farthestPointFromBoxCenter
        let center = CGFloat(side) / 2

        var farthestInk: CGFloat = 0
        var ink = 0.0
        var darkPixelsInGap = 0
        for y in 0..<side {
            for x in 0..<side {
                let distance = hypot(CGFloat(x) + 0.5 - center, CGFloat(y) + 0.5 - center)
                guard distance < backgroundRadius - 1 else { continue }
                let coverage = 1 - Double(pixels[y * side + x]) / 255
                if coverage > 0.5 { farthestInk = max(farthestInk, distance) }
                if distance <= signExtent + 1 {
                    ink += coverage
                } else if coverage > 0.02 {
                    darkPixelsInGap += 1
                }
            }
        }

        XCTAssertEqual(farthestInk, signExtent, accuracy: 1.5)
        XCTAssertEqual(darkPixelsInGap, 0, "the ring between the sign and the background circle's edge must stay white")
        XCTAssertEqual(ink / (Double.pi * Double(signRadius * signRadius)), inkShareOfEnclosingCircle, accuracy: 0.01)
    }

    private func sampledPoints(of path: CGPath) -> [CGPoint] {
        var points: [CGPoint] = []
        var current = CGPoint.zero
        path.applyWithBlock { element in
            let p = element.pointee.points
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint:
                current = p[0]
                points.append(current)
            case .addCurveToPoint:
                for step in 1...64 {
                    let t = CGFloat(step) / 64, mt = 1 - t
                    let a = mt * mt * mt, b = 3 * mt * mt * t, c = 3 * mt * t * t, d = t * t * t
                    points.append(CGPoint(
                        x: a * current.x + b * p[0].x + c * p[1].x + d * p[2].x,
                        y: a * current.y + b * p[0].y + c * p[1].y + d * p[2].y
                    ))
                }
                current = p[2]
            default:
                break
            }
        }
        return points
    }
}
