import CoreGraphics
import Foundation

/// Колір акценту графічного QR-коду в sRGB (див. `NBUQRImageRenderer.accentColor`).
///
/// Постанова задає колір лише фонового кола — білий (додаток 1, п. 10); колір
/// знака ₴ вона лишає вільним.
public struct NBUQRColor: Hashable, Sendable {
    /// Червоний компонент, 0…1.
    public let red: Double
    /// Зелений компонент, 0…1.
    public let green: Double
    /// Синій компонент, 0…1.
    public let blue: Double

    /// Колір у sRGB; компоненти поза 0…1 обмежуються цим діапазоном.
    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    /// `"#007B47"` або `"007B47"`; `nil`, якщо рядок не є 6 hex-цифрами.
    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, digits.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// Чорний — акцент за замовчуванням, тобто весь код одного кольору.
    public static let black = NBUQRColor(red: 0, green: 0, blue: 0)

    /// Зелений НБУ, `#007B47`: фірмовий колір bank.gov.ua, яким там же, на
    /// сторінці про QR-коди (bank.gov.ua/ua/payments/use-qr), намальовано знак ₴
    /// і центри шукових візерунків.
    public static let nbuGreen = NBUQRColor(red: 0, green: 123.0 / 255, blue: 71.0 / 255)

    /// Відносна яскравість за sRGB / WCAG: 0 для чорного, 1 для білого.
    var relativeLuminance: Double {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }
}
