import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import NBUQRCode

/// Рівень корекції помилок графічного QR-коду.
///
/// "L" тут навмисно відсутній: Правила НБУ забороняють його використання при
/// обов'язковому (для версії формату 003) накладанні графічного знака гривні
/// (додаток 1, п. 13). Причина фізична — фонове коло зі знаком гривні затирає
/// ≈7% площі коду, тобто рівно стільки, скільки здатен відновити рівень "L".
public enum NBUQRErrorCorrectionLevel: String, Sendable {
    /// "M" — відновлює ≈15% пошкоджень коду.
    case medium = "M"
    /// "Q" — відновлює ≈25% пошкоджень коду.
    case quartile = "Q"
}

/// Спосіб вибору рівня корекції.
public enum NBUQRErrorCorrection: Hashable, Sendable {
    /// Найвищий рівень, за якого версія QR-коду лишається в дозволених 10–17:
    /// спершу "Q", і лише якщо даних забагато — "M".
    case automatic
    /// Фіксований рівень. Якщо він дає версію поза 10–17, рендер кидає
    /// `dataTooShort` або `dataTooLong` замість того, щоб мовчки видати
    /// несумісний код.
    case fixed(NBUQRErrorCorrectionLevel)
}

/// Помилки рендеру. `description` — англійською, для логів і розробника;
/// користувачу показуйте власний текст за кейсом.
public enum NBUQRImageError: Error, Equatable, LocalizedError, CustomStringConvertible {
    /// Даних замало: версія нижча за мінімальну 10 (додаток 1, п. 5).
    /// `additionalDataBytes` — скільки приблизно байтів даних бракує; заповнені
    /// як слід поля платежу покривають це з запасом.
    case dataTooShort(version: Int, minimumVersion: Int, additionalDataBytes: Int, level: NBUQRErrorCorrectionLevel)
    /// Даних забагато: версія вища за максимальну 17 (додаток 4, п. 9).
    /// `excessDataBytes` — на скільки приблизно треба скоротити дані.
    case dataTooLong(version: Int, maximumVersion: Int, excessDataBytes: Int, level: NBUQRErrorCorrectionLevel)
    /// `accentColor` надто світлий на білому тлі: контраст `1 − яскравість`
    /// нижчий за `minimum`.
    case insufficientAccentContrast(contrast: Double, minimum: Double)
    /// `moduleSize` менший за 1 піксель.
    case invalidModuleSize(moduleSize: Int)
    /// `quietZoneModules` від'ємний.
    case invalidQuietZone(quietZoneModules: Int)
    /// Збій платформного QR-кодувальника чи растеризації — не наслідок вхідних
    /// даних. `reason` пояснює деталі для логів.
    case renderingFailed(reason: String)

    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .dataTooShort(let version, let minimum, let additional, let level):
            return "Payment data is too short: QR version \(version) at correction level \(level.rawValue), "
                + "but the NBU rules require at least version \(minimum). Add about \(additional) more bytes "
                + "of payment data — a full recipient name, a meaningful purpose or a reference is normally enough."
        case .dataTooLong(let version, let maximum, let excess, let level):
            return "Payment data is too long: QR version \(version) at correction level \(level.rawValue), "
                + "but the NBU rules allow at most version \(maximum). Remove about \(excess) bytes of payment "
                + "data — the purpose field is usually the place to shorten."
        case .insufficientAccentContrast(let contrast, let minimum):
            return "Accent colour is too light for a white background: contrast "
                + String(format: "%.2f", contrast) + ", at least " + String(format: "%.2f", minimum)
                + " is required, since it paints the finder patterns' centres too "
                + "(ISO/IEC 18004 symbol contrast grade A). Use a darker colour."
        case .invalidModuleSize(let moduleSize):
            return "Module size must be at least 1 pixel, got \(moduleSize)."
        case .invalidQuietZone(let quietZoneModules):
            return "Quiet zone cannot be negative, got \(quietZoneModules) modules."
        case .renderingFailed(let reason):
            return "Failed to render the QR code image: " + reason
        }
    }
}

/// Рендерить графічне зображення QR-коду НБУ версії формату 003 — сам QR-код
/// плюс обов'язковий графічний знак національної грошової одиниці (₴) у
/// білому колі по центру (додаток 1, пп. 10–14). Знак — векторний контур з
/// `NBUHryvniaSign`, тож від шрифтів системи рендер не залежить.
///
/// У зображення завжди кодується `NBUQRPayload.qrURL()`, тобто код старту
/// застосунку `https://qr.bank.gov.ua/`. Передати сюди готове посилання неможливо
/// навмисно: QR-код з кодом старту застосунку банку (`NBUQRBank`) читає лише сканер цього
/// банку (docs/NBU-COMPLIANCE.md, "QR-код і deep link").
public struct NBUQRImageRenderer: Sendable {
    /// Додаток 1, п. 5 (мінімум) і додаток 4, п. 9 (максимум для формату 003).
    static let allowedVersions = 10...17

    /// Спосіб вибору рівня корекції. За замовчуванням ``NBUQRErrorCorrection/automatic``.
    public var errorCorrection: NBUQRErrorCorrection
    /// Розмір одного модуля QR-коду в пікселях ("X-розмір", додаток 1, п. 7).
    /// Щонайменше 1, інакше рендер кидає `invalidModuleSize`. Верхньої межі свідомо
    /// немає: розмір зображення — рішення клієнта, а не стандарту.
    public var moduleSize: Int
    /// Тиха зона з кожного боку QR-коду, у модулях. За замовчуванням 4 — як у
    /// ДСТУ ISO/IEC 18004:2019, на який спираються Правила. Менше значення,
    /// зокрема 0, — свідоме відхилення на розсуд клієнта; від'ємне — `invalidQuietZone`.
    public var quietZoneModules: Int
    /// Колір знака ₴ і центрів 3×3 трьох шукових візерунків у кутах коду —
    /// як у прикладі на bank.gov.ua/ua/payments/use-qr. Решта модулів лишається
    /// чорною, тло, тиха зона й фонове коло — білими.
    public var accentColor: NBUQRColor

    /// Найменший контраст `accentColor` з білим тлом, `1 − яскравість`. Центри
    /// шукових візерунків — частина розмітки, за якою сканер знаходить код, тож
    /// світлий акцент зламав би пошук. 0,7 — межа класу "A" за методикою
    /// ISO/IEC 15415, якою ДСТУ ISO/IEC 18004 оцінює якість символу.
    static let minimumAccentContrast = 0.7

    // Створення CIContext ініціалізує Metal і компілює ядра CI — сотні мілісекунд на
    // старших пристроях, — тож створювати його на кожен рендер не можна.
    private static let shared = SharedCIContext()

    // CIContext задокументований як потокобезпечний, але позначений Sendable лише в
    // новіших SDK: старіші відхиляють статичну не-Sendable константу, а новіші вважають
    // nonisolated(unsafe) на ній зайвим. Обгортка @unchecked компілюється чисто на обох.
    private final class SharedCIContext: @unchecked Sendable {
        let context = CIContext(options: nil)
    }

    /// Створює рендер; параметри відповідають однойменним властивостям.
    ///
    /// Значення перевіряються під час рендеру, а не тут: властивості змінні й
    /// після створення.
    public init(
        errorCorrection: NBUQRErrorCorrection = .automatic,
        moduleSize: Int = 10,
        quietZoneModules: Int = 4,
        accentColor: NBUQRColor = .black
    ) {
        self.errorCorrection = errorCorrection
        self.moduleSize = moduleSize
        self.quietZoneModules = quietZoneModules
        self.accentColor = accentColor
    }

    /// Рендерить QR-код для закодованого платежу.
    ///
    /// Кидає `NBUQRError.qrDataTooLong`, якщо дані не вміщуються в ліміти
    /// графічного QR-коду; `NBUQRImageError.dataTooShort` / `.dataTooLong`, якщо
    /// жоден дозволений рівень корекції не дає версію в межах 10–17;
    /// `.insufficientAccentContrast` для надто світлого `accentColor`;
    /// `.invalidModuleSize` / `.invalidQuietZone` для неможливих розмірів.
    public func cgImage(for payload: NBUQRPayload) throws -> CGImage {
        // Перевіряється тут, а не в init: властивості змінні й після створення.
        guard moduleSize >= 1 else {
            throw NBUQRImageError.invalidModuleSize(moduleSize: moduleSize)
        }
        guard quietZoneModules >= 0 else {
            throw NBUQRImageError.invalidQuietZone(quietZoneModules: quietZoneModules)
        }
        let contrast = 1 - accentColor.relativeLuminance
        guard contrast >= Self.minimumAccentContrast else {
            throw NBUQRImageError.insufficientAccentContrast(contrast: contrast, minimum: Self.minimumAccentContrast)
        }
        let candidate = try selectMatrix(for: try payload.qrURL().absoluteString)
        return try draw(candidate)
    }

    /// PNG-байти зображення QR-коду для закодованого платежу.
    public func pngData(for payload: NBUQRPayload) throws -> Data {
        try Self.pngData(from: try cgImage(for: payload))
    }

    // MARK: - Вибір рівня корекції

    private struct Candidate {
        let image: CIImage
        let version: Int
        let level: NBUQRErrorCorrectionLevel
    }

    private func selectMatrix(for url: String) throws -> Candidate {
        switch errorCorrection {
        case .fixed(let level):
            return try checked(matrix(for: url, level: level), url: url)

        case .automatic:
            let quartile = try matrix(for: url, level: .quartile)
            if Self.allowedVersions.contains(quartile.version) { return quartile }

            // Нижчий рівень корекції завжди дає меншу або рівну версію, тож
            // перехід на "M" рятує лише від перевищення стелі. Якщо навіть "Q"
            // не дотягнув до мінімальної версії 10, "M" тим паче не дотягне —
            // пробувати його немає сенсу, даних просто замало.
            guard quartile.version > Self.allowedVersions.upperBound else {
                return try checked(quartile, url: url)
            }
            return try checked(matrix(for: url, level: .medium), url: url)
        }
    }

    private func checked(_ candidate: Candidate, url: String) throws -> Candidate {
        if candidate.version < Self.allowedVersions.lowerBound {
            throw NBUQRImageError.dataTooShort(
                version: candidate.version,
                minimumVersion: Self.allowedVersions.lowerBound,
                additionalDataBytes: dataBytes(urlCharacters: shortfall(of: url, level: candidate.level)),
                level: candidate.level
            )
        }
        if candidate.version > Self.allowedVersions.upperBound {
            throw NBUQRImageError.dataTooLong(
                version: candidate.version,
                maximumVersion: Self.allowedVersions.upperBound,
                excessDataBytes: dataBytes(urlCharacters: excess(of: url, level: candidate.level)),
                level: candidate.level
            )
        }
        return candidate
    }

    // MARK: - Наскільки саме промахнулись

    // Межі не зашиті константами і рахуються пробним кодуванням: залежність
    // версії від обсягу даних задає CIQRCodeGenerator, а не ми, і вона може
    // змінитись з оновленням системи. Проби робляться лише на шляху помилки.
    private static let probeLimit = 512

    /// Скільки символів бракує посиланню, щоб дотягти до мінімальної версії.
    private func shortfall(of url: String, level: NBUQRErrorCorrectionLevel) -> Int {
        // Доповнюємо саме реальне посилання: рядок з малих і великих літер
        // кодується в byte mode, і дописаний символ не змінює режим. Проба на
        // синтетичному "AAA..." дала б alphanumeric mode і меншу версію.
        search { padding in
            guard let candidate = try? matrix(for: url + String(repeating: "A", count: padding), level: level) else {
                return false
            }
            return candidate.version >= Self.allowedVersions.lowerBound
        }
    }

    /// Скільки символів зайві відносно максимальної версії.
    private func excess(of url: String, level: NBUQRErrorCorrectionLevel) -> Int {
        search { trim in
            guard trim < url.count,
                  let candidate = try? matrix(for: String(url.dropLast(trim)), level: level) else {
                return false
            }
            return candidate.version <= Self.allowedVersions.upperBound
        }
    }

    /// Найменше `n` в межах `1...probeLimit`, для якого `fits` істинна.
    private func search(_ fits: (Int) -> Bool) -> Int {
        var low = 1
        var high = Self.probeLimit
        var answer = Self.probeLimit
        while low <= high {
            let mid = (low + high) / 2
            if fits(mid) {
                answer = mid
                high = mid - 1
            } else {
                low = mid + 1
            }
        }
        return answer
    }

    /// Base64URL кодує 3 байти даних у 4 символи посилання.
    private func dataBytes(urlCharacters: Int) -> Int {
        (urlCharacters * 3 + 3) / 4
    }

    private func matrix(for url: String, level: NBUQRErrorCorrectionLevel) throws -> Candidate {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            throw NBUQRImageError.renderingFailed(reason: "CIQRCodeGenerator filter is unavailable")
        }
        filter.setValue(Data(url.utf8), forKey: "inputMessage")
        filter.setValue(level.rawValue, forKey: "inputCorrectionLevel")

        guard let image = filter.outputImage else {
            throw NBUQRImageError.renderingFailed(reason: "CIQRCodeGenerator produced no QR matrix")
        }

        // CIQRCodeGenerator сам додає тиху зону в 1 модуль з кожного боку,
        // тому "гола" QR-матриця (без тихої зони) на 2 модулі менша за extent —
        // перевірено на версії 1 (21×21 модуль за ISO/IEC 18004): extent = 23.
        let sideWithQuietZone = Int(image.extent.width.rounded())

        // Ширина тихої зони — спостережена поведінка CIQRCodeGenerator, а не
        // контракт його API, і саме на ній тримається обчислення версії, тобто
        // вся перевірка відповідності Правилам. Якщо Apple колись віддаватиме
        // інакшу тиху зону (ISO/IEC 18004 рекомендує 4 модулі), сторона
        // перестане бути кратною: за 1 модуля "сторона − 19" ділиться на 4
        // націло, за 4 модулів залишок дорівнював би 2. Тоді версія
        // порахувалася б зі зсувом і перевірка 10–17 почала б мовчки брехати —
        // краще впасти гучно.
        let bareSide = sideWithQuietZone - 2
        let version = (bareSide - 17) / 4
        guard (bareSide - 17) % 4 == 0, (1...40).contains(version) else {
            throw NBUQRImageError.renderingFailed(
                reason: "CIQRCodeGenerator returned a \(sideWithQuietZone)×\(sideWithQuietZone) module matrix, which does not "
                    + "match the expected \"version × 4 + 17 modules plus a 1-module quiet zone\" geometry. "
                    + "The QR version cannot be derived, so NBU conformance cannot be verified."
            )
        }

        return Candidate(image: image, version: version, level: level)
    }

    // MARK: - Рендер

    private func draw(_ candidate: Candidate) throws -> CGImage {
        guard let qrCGImage = Self.shared.context.createCGImage(candidate.image, from: candidate.image.extent) else {
            throw NBUQRImageError.renderingFailed(reason: "CoreGraphics could not rasterise the image")
        }

        let qrSideModules = Int(candidate.image.extent.width.rounded())
        let matrixModules = qrSideModules - 2
        let canvasSidePixels = (matrixModules + 2 * quietZoneModules) * moduleSize

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
            data: nil,
            width: canvasSidePixels,
            height: canvasSidePixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw NBUQRImageError.renderingFailed(reason: "CoreGraphics could not rasterise the image")
        }

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: canvasSidePixels, height: canvasSidePixels))

        // Модулі мають лишатись чіткими прямокутниками — без згладжування.
        context.interpolationQuality = .none
        let qrSidePixels = qrSideModules * moduleSize
        // CIQRCodeGenerator сам додає 1 модуль тихої зони, тож зображення зсувається
        // на модуль назовні. За `quietZoneModules == 0` ця власна зона виходить за
        // полотно й обрізається.
        let qrOrigin = CGFloat((quietZoneModules - 1) * moduleSize)
        context.draw(qrCGImage, in: CGRect(x: qrOrigin, y: qrOrigin, width: CGFloat(qrSidePixels), height: CGFloat(qrSidePixels)))
        drawFinderCenters(in: context, qrOrigin: qrOrigin, matrixModules: matrixModules)

        drawCurrencyMark(in: context, canvasSidePixels: canvasSidePixels, version: candidate.version)

        guard let finalImage = context.makeImage() else {
            throw NBUQRImageError.renderingFailed(reason: "CoreGraphics could not rasterise the image")
        }
        return finalImage
    }

    /// Зафарбовує `accentColor` темний центр 3×3 кожного шукового візерунка. Візерунки
    /// стоять у верхньому лівому, верхньому правому й нижньому лівому кутах "голої"
    /// матриці, яка починається на модуль усередину від `qrOrigin` (власна тиха зона
    /// CIQRCodeGenerator).
    private func drawFinderCenters(in context: CGContext, qrOrigin: CGFloat, matrixModules: Int) {
        let module = CGFloat(moduleSize)
        let matrixOrigin = qrOrigin + module
        let far = CGFloat(matrixModules - 7)
        context.setFillColor(accentColor.cgColor)
        // Вісь y у CoreGraphics спрямована вгору, тож верхні кути — на дальньому кінці y.
        for (column, row) in [(0, far), (far, far), (0, 0)] as [(CGFloat, CGFloat)] {
            context.fill(CGRect(
                x: matrixOrigin + (column + 2) * module,
                y: matrixOrigin + (row + 2) * module,
                width: 3 * module,
                height: 3 * module
            ))
        }
    }

    private static func pngData(from image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else {
            throw NBUQRImageError.renderingFailed(reason: "ImageIO could not encode the image as PNG")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NBUQRImageError.renderingFailed(reason: "ImageIO could not encode the image as PNG")
        }
        return data as Data
    }

    // MARK: - Графічний знак гривні (додаток 1, пп. 10–14)

    /// Радіус описаного кола знака відносно радіуса фонового кола — як у прикладах
    /// постанови (додаток 4, приклади 1–4): у всіх чотирьох 0,6957 ± 0,0009, хоча
    /// самі кола там різного розміру. Це менше, ніж давало б буквальне вписування
    /// в коло на 4 модулі менше (п. 12), — розмір свідомо взято з прикладів.
    static let signToBackgroundCircleRatio: CGFloat = 0.6957

    private func drawCurrencyMark(in context: CGContext, canvasSidePixels: Int, version: Int) {
        let circleModules = Self.backgroundCircleDiameterModules(forVersion: version)

        let center = CGFloat(canvasSidePixels) / 2
        let circleDiameterPx = CGFloat(circleModules * moduleSize)

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fillEllipse(in: CGRect(
            x: center - circleDiameterPx / 2,
            y: center - circleDiameterPx / 2,
            width: circleDiameterPx,
            height: circleDiameterPx
        ))

        let signRadiusPx = circleDiameterPx / 2 * Self.signToBackgroundCircleRatio
        context.setFillColor(accentColor.cgColor)
        context.addPath(NBUHryvniaSign.path(enclosingRadius: signRadiusPx, centeredAt: CGPoint(x: center, y: center)))
        context.fillPath()
    }

    /// Діаметр фонового кола в модулях (додаток 1, п. 11). Таблиця охоплює
    /// рівно версії 10–17 — інших значень у Правилах немає, і саме тому версія
    /// перевіряється до рендеру: для версії поза цим діапазоном довелось би
    /// вигадати діаметр, якого стандарт не визначає.
    static func backgroundCircleDiameterModules(forVersion version: Int) -> Int {
        switch version {
        case 10: return 17
        case 11, 12: return 19
        case 13: return 21
        case 14, 15: return 23
        // Версія гарантовано в межах 10–17, тож гілка покриває лише 16 і 17.
        default: return 25
        }
    }
}
