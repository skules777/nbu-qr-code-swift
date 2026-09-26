import CoreGraphics

/// Контур знака гривні (₴), який `NBUQRImageRenderer` ставить у центр QR-коду
/// (додаток 1, пп. 10–12).
///
/// Форму протрасовано з чотирьох QR-кодів формату 003 у постанові №97 (додаток 4,
/// приклади 1–4), а не взято зі шрифту: п. 14 лишає форму знака за НБУ, а гліф шрифту
/// і відрізняється від неї, і може бути відсутній під час виконання. Чотири растри
/// суміщено й усереднено, контур протрасовано, прямі ребра вирівняно, решту
/// апроксимовано кубічними кривими. Відрендерений назад у масштабі кожного прикладу,
/// контур відрізняється від нього в середньому на 0,013 покриття на піксель
/// (IoU 0,987) — стільки ж, скільки самі приклади відрізняються один від одного.
///
/// Координати: рамка знака центрована на (0, 0), мінімальне описане коло має радіус 1,
/// вісь y спрямована вгору. Так знак розміщено й у прикладах: його рамка центрована на
/// фоновому колі, а радіус описаного кола — фіксована частка радіуса цього кола
/// (див. `NBUQRImageRenderer.signToBackgroundCircleRatio`).
enum NBUHryvniaSign {
    static func path(enclosingRadius radius: CGFloat, centeredAt center: CGPoint) -> CGPath {
        let transform = CGAffineTransform(translationX: center.x, y: center.y).scaledBy(x: radius, y: radius)
        let path = CGMutablePath()
        path.move(to: start, transform: transform)
        for segment in segments {
            switch segment {
            case .line(let end):
                path.addLine(to: end, transform: transform)
            case .curve(let control1, let control2, let end):
                path.addCurve(to: end, control1: control1, control2: control2, transform: transform)
            }
        }
        path.closeSubpath()
        return path
    }

    private enum Segment {
        case line(CGPoint)
        case curve(CGPoint, CGPoint, CGPoint)
    }

    private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: x, y: y)
    }

    private static let start = p(-0.5334, 0.8491)

    private static let segments: [Segment] = [
        .line(p(-0.5448, 0.5659)),
        .curve(p(-0.493, 0.5581), p(-0.4168, 0.5942), p(-0.3645, 0.6071)),
        .curve(p(-0.2186, 0.6432), p(0.0084, 0.6567), p(0.0875, 0.4983)),
        .curve(p(0.12, 0.4334), p(0.1024, 0.3756), p(0.064, 0.318)),
        .curve(p(0.0368, 0.2771), p(0.0006, 0.2413), p(-0.0356, 0.2094)),
        .line(p(-0.6022, 0.2094)),
        .line(p(-0.6096, 0.0257)),
        .line(p(-0.263, 0.0257)),
        .line(p(-0.3549, -0.0561)),
        .line(p(-0.6265, -0.0561)),
        .line(p(-0.6339, -0.2399)),
        .line(p(-0.5346, -0.2399)),
        .curve(p(-0.5353, -0.2719), p(-0.5559, -0.3019), p(-0.5655, -0.3333)),
        .curve(p(-0.5978, -0.4398), p(-0.5731, -0.5748), p(-0.5175, -0.669)),
        .curve(p(-0.3669, -0.9248), p(0.0775, -0.9313), p(0.3352, -0.8798)),
        .curve(p(0.4038, -0.866), p(0.4884, -0.8699), p(0.5488, -0.8329)),
        .line(p(0.561, -0.5267)),
        .curve(p(0.51, -0.525), p(0.4529, -0.5659), p(0.4019, -0.5781)),
        .curve(p(0.2717, -0.6094), p(0.1421, -0.6383), p(0.0078, -0.6152)),
        .curve(p(-0.1043, -0.5959), p(-0.2089, -0.4807), p(-0.1658, -0.3634)),
        .curve(p(-0.1478, -0.3143), p(-0.105, -0.2729), p(-0.0674, -0.2398)),
        .line(p(0.6004, -0.2398)),
        .line(p(0.6078, -0.0561)),
        .line(p(0.1358, -0.0561)),
        .line(p(0.2278, 0.0257)),
        .line(p(0.6265, 0.0257)),
        .line(p(0.6339, 0.2094)),
        .line(p(0.4249, 0.2094)),
        .curve(p(0.4299, 0.2515), p(0.4763, 0.2956), p(0.4931, 0.338)),
        .curve(p(0.5239, 0.4154), p(0.5107, 0.5181), p(0.4849, 0.5952)),
        .curve(p(0.3823, 0.9027), p(-0.017, 0.9227), p(-0.2861, 0.8977)),
        .curve(p(-0.3682, 0.89), p(-0.4579, 0.8832), p(-0.5334, 0.8491)),
    ]
}
