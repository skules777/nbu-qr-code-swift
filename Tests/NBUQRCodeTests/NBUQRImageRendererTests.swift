import CoreImage
import XCTest
@testable import NBUQRCode
@testable import NBUQRCodeImage

// Декодування назад робимо через CIDetector (CoreImage), щоб перевірка лишалась
// повністю самодостатньою — без Python/zbar/OpenCV. Round-trip тим самим
// інструментом, який реально сканує QR-коди в застосунках на Apple-платформах.
final class NBUQRImageRendererTests: XCTestCase {
    private func decodeQRImage(data: Data) -> String? {
        guard let ciImage = CIImage(data: data) else { return nil }
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: ciImage) as? [CIQRCodeFeature] ?? []
        return features.first?.messageString
    }

    func testRenderedQRWithHryvniaMarkDecodesBackToTheSameURL() throws {
        let payload = try NBUQRPayload(officialOnlineStorePayment())
        let expectedURL = try payload.qrURL().absoluteString

        let pngData = try NBUQRImageRenderer().pngData(for: payload)
        XCTAssertFalse(pngData.isEmpty)

        let decoded = decodeQRImage(data: pngData)
        XCTAssertEqual(decoded, expectedURL)
    }

    // Правила (додаток 1, п. 5; додаток 4, п. 9) вимагають версію QR-коду
    // 10-17. CIQRCodeGenerator сам підбирає версію під обсяг даних — для
    // типових (не мінімальних) платежів вона природно лишається в межах.
    func testTypicalP2PPaymentStaysWithinNBUVersionRange() throws {
        let o = NBUQRPayment(
            function: .ict,
            recipient: "Петренко Роман Петрович",
            iban: "UA906543210000000260323012024",
            amount: 63,
            recipientCode: "40121425",
            category: "MP2P/MP2B",
            reference: "DR-5678-12",
            purpose: "За каву"
        )
        let url = try qrURL(o).absoluteString

        guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
            XCTFail("CIQRCodeGenerator unavailable")
            return
        }
        filter.setValue(Data(url.utf8), forKey: "inputMessage")
        filter.setValue("Q", forKey: "inputCorrectionLevel")
        let side = Int((filter.outputImage?.extent.width ?? 0).rounded())
        let version = (side - 2 - 17) / 4

        XCTAssertTrue((10...17).contains(version), "got version \(version)")
    }
}

// Версія QR-коду має лишатись у 10–17 (додаток 1 п. 5, додаток 4 п. 9).
// Обмеження залежить не лише від обсягу даних, а й від рівня корекції: на "Q"
// версія 17 вичерпується раніше, ніж дозволені 507 байтів даних.
final class NBUQRVersionRangeTests: XCTestCase {
    private func version(of pngData: Data, moduleSize: Int, quietZoneModules: Int) -> Int {
        // Сторона полотна = (модулі матриці + 2 × тиха зона) × розмір модуля.
        let side = Int((CIImage(data: pngData)?.extent.width ?? 0).rounded()) / moduleSize
        return (side - 2 * quietZoneModules - 17) / 4
    }

    private func tinyPayment() -> NBUQRPayment {
        NBUQRPayment(
            function: .ict, recipient: "К", iban: "UA511234567890123456789012345",
            recipientCode: "1", category: "MP2P/MP2B", purpose: "Ч")
    }

    /// Понад стелю "Q" (≈364 байти), але в межах "M" (≈504).
    private func bulkyPayment() -> NBUQRPayment {
        largestQRPayment(from: officialOnlineStorePayment(), reachingURLBytes: 450)
    }

    func testTooLittleDataIsRejectedInsteadOfRenderingVersionBelow10() {
        XCTAssertThrowsError(try NBUQRImageRenderer().pngData(for: NBUQRPayload(tinyPayment()))) { error in
            guard case NBUQRImageError.dataTooShort(let version, let minimum, let additional, _) = error else {
                return XCTFail("expected dataTooShort, got \(error)")
            }
            XCTAssertLessThan(version, minimum)
            XCTAssertGreaterThan(additional, 0)
        }
    }

    // Число в помилці має бути дією, а не прикрасою: дописавши стільки байтів
    // у призначення платежу, користувач справді отримує сумісний QR-код.
    func testReportedShortfallIsEnoughToMakeItRender() throws {
        var payment = tinyPayment()
        var shortfall = 0
        XCTAssertThrowsError(try NBUQRImageRenderer().pngData(for: NBUQRPayload(payment))) { error in
            guard case NBUQRImageError.dataTooShort(_, _, let additional, _) = error else {
                return XCTFail("expected dataTooShort, got \(error)")
            }
            shortfall = additional
        }

        payment.purpose += String(repeating: "т", count: shortfall)
        let renderer = NBUQRImageRenderer()
        let png = try renderer.pngData(for: NBUQRPayload(payment))
        let rendered = version(of: png, moduleSize: renderer.moduleSize, quietZoneModules: renderer.quietZoneModules)
        XCTAssertTrue(NBUQRImageRenderer.allowedVersions.contains(rendered), "got version \(rendered)")
    }

    // Даних забагато для "Q", але достатньо для "M" — автовибір має мовчки
    // перейти на нижчий рівень замість того, щоб видати версію 18+.
    func testAutomaticFallsBackToMediumWhenQuartileOverflows() throws {
        let renderer = NBUQRImageRenderer()
        let png = try renderer.pngData(for: NBUQRPayload(bulkyPayment()))
        let rendered = version(of: png, moduleSize: renderer.moduleSize, quietZoneModules: renderer.quietZoneModules)
        XCTAssertTrue(NBUQRImageRenderer.allowedVersions.contains(rendered), "got version \(rendered)")
    }

    // Колишня мертва зона: п. 8 дозволяє 507 байтів даних, але версія 17
    // вичерпується раніше навіть на "M" (близько 504). Після того як додався
    // ліміт таблиці 1 (payload ≤ 475, тобто URL ≤ 498), зона стала недосяжною:
    // найбільший платіж, який проходить валідацію, гарантовано рендериться.
    func testLargestAcceptedPaymentAlwaysRenders() throws {
        let maximal = try NBUQRPayload(largestQRPayment(from: officialOnlineStorePayment()))
        let urlBytes = try maximal.qrURL().absoluteString.utf8.count
        XCTAssertLessThanOrEqual(
            urlBytes,
            NBUQRFormat.qrAppStartURL.utf8.count + NBUQRFormat.maxPayloadLength
        )

        let renderer = NBUQRImageRenderer()
        let png = try renderer.pngData(for: maximal)
        let rendered = version(of: png, moduleSize: renderer.moduleSize, quietZoneModules: renderer.quietZoneModules)
        XCTAssertTrue(NBUQRImageRenderer.allowedVersions.contains(rendered), "got version \(rendered)")
    }

    func testFixedQuartileRefusesOversizedDataInsteadOfSilentlyExceeding() {
        let renderer = NBUQRImageRenderer(errorCorrection: .fixed(.quartile))
        XCTAssertThrowsError(try renderer.pngData(for: NBUQRPayload(bulkyPayment()))) { error in
            guard case NBUQRImageError.dataTooLong(let version, let maximum, let excess, let level) = error else {
                return XCTFail("expected dataTooLong, got \(error)")
            }
            XCTAssertGreaterThan(version, maximum)
            XCTAssertGreaterThan(excess, 0)
            XCTAssertEqual(level, .quartile)
        }
    }

    func testTypicalPaymentStillRendersAtQuartile() throws {
        let renderer = NBUQRImageRenderer()
        let png = try renderer.pngData(for: NBUQRPayload(officialOnlineStorePayment()))
        let rendered = version(of: png, moduleSize: renderer.moduleSize, quietZoneModules: renderer.quietZoneModules)
        XCTAssertTrue(NBUQRImageRenderer.allowedVersions.contains(rendered), "got version \(rendered)")
    }
}

// Версія QR-коду виводиться зі сторони матриці, а та залежить від того,
// скільки тихої зони додає CIQRCodeGenerator (спостережено: 1 модуль з боку).
// Цей тест — сторожа проти зміни цієї поведінки в майбутніх версіях ОС: якщо
// вона зміниться, перевірка 10–17 почне рахувати версію зі зсувом.
final class NBUQRMatrixGeometryTests: XCTestCase {
    func testQuietZoneIsOneModulePerSideAcrossSizesAndLevels() {
        for length in stride(from: 30, through: 507, by: 7) {
            for level in ["M", "Q"] {
                guard let filter = CIFilter(name: "CIQRCodeGenerator") else {
                    return XCTFail("CIQRCodeGenerator unavailable")
                }
                filter.setValue(Data(String(repeating: "A", count: length).utf8), forKey: "inputMessage")
                filter.setValue(level, forKey: "inputCorrectionLevel")
                guard let output = filter.outputImage else {
                    return XCTFail("no output for \(length) bytes at \(level)")
                }

                let side = Int(output.extent.width.rounded())
                XCTAssertEqual(
                    (side - 2 - 17) % 4, 0,
                    "сторона \(side) не відповідає геометрії «версія × 4 + 17 + 2 модулі тихої зони» "
                        + "(\(length) байтів, рівень \(level))"
                )
            }
        }
    }

    func testRendererDerivesVersionFromTheSameGeometry() throws {
        let renderer = NBUQRImageRenderer()
        let png = try renderer.pngData(for: NBUQRPayload(officialOnlineStorePayment()))
        let rendered = version(of: png, moduleSize: renderer.moduleSize, quietZoneModules: renderer.quietZoneModules)
        XCTAssertEqual((rendered * 4 + 17) % 4, (17 % 4), "версія має бути цілим числом модульної сітки")
        XCTAssertTrue(NBUQRImageRenderer.allowedVersions.contains(rendered))
    }

    private func version(of pngData: Data, moduleSize: Int, quietZoneModules: Int) -> Int {
        let side = Int((CIImage(data: pngData)?.extent.width ?? 0).rounded()) / moduleSize
        return (side - 2 * quietZoneModules - 17) / 4
    }
}

// Неможливі розміри мають давати помилку з самим значенням, а не renderingFailed,
// який означає збій платформи, а не хибні вхідні дані.
final class NBUQRRendererConfigurationTests: XCTestCase {
    private func payload() throws -> NBUQRPayload {
        try NBUQRPayload(officialOnlineStorePayment())
    }

    func testNonPositiveModuleSizeIsRejected() throws {
        for moduleSize in [0, -1] {
            let renderer = NBUQRImageRenderer(moduleSize: moduleSize)
            XCTAssertThrowsError(try renderer.pngData(for: payload())) { error in
                XCTAssertEqual(error as? NBUQRImageError, .invalidModuleSize(moduleSize: moduleSize))
            }
        }
    }

    func testNegativeQuietZoneIsRejected() throws {
        let renderer = NBUQRImageRenderer(quietZoneModules: -1)
        XCTAssertThrowsError(try renderer.cgImage(for: payload())) { error in
            XCTAssertEqual(error as? NBUQRImageError, .invalidQuietZone(quietZoneModules: -1))
        }
    }

    // Властивості змінні, тож перевірка має спрацювати й для значення,
    // присвоєного після створення.
    func testInvalidValueAssignedAfterInitIsRejected() throws {
        var renderer = NBUQRImageRenderer()
        renderer.moduleSize = 0
        XCTAssertThrowsError(try renderer.cgImage(for: payload())) { error in
            XCTAssertEqual(error as? NBUQRImageError, .invalidModuleSize(moduleSize: 0))
        }
    }

    // Тиха зона — рівно стільки модулів, скільки просили, включно з нулем:
    // CIQRCodeGenerator додає свій модуль сам, і рендер має це компенсувати.
    func testQuietZoneIsExactlyAsRequested() throws {
        let moduleSize = 10
        let bare = try NBUQRImageRenderer(moduleSize: moduleSize, quietZoneModules: 0).cgImage(for: payload())
        XCTAssertEqual(bare.width % moduleSize, 0)
        let matrixModules = bare.width / moduleSize
        XCTAssertTrue(NBUQRImageRenderer.allowedVersions.contains((matrixModules - 17) / 4))

        for quietZone in [0, 1, 2, 4, 7] {
            let image = try NBUQRImageRenderer(moduleSize: moduleSize, quietZoneModules: quietZone).cgImage(for: payload())
            XCTAssertEqual(image.width, (matrixModules + 2 * quietZone) * moduleSize, "quietZone \(quietZone)")

            // Кутовий модуль матриці — зовнішня рамка шукового візерунка, тобто
            // темний; усе, що лівіше й вище від нього, — біле поле.
            let pixels = try grayPixels(of: image)
            func brightness(atModule x: Int, _ y: Int) -> UInt8 {
                pixels[(y * moduleSize + moduleSize / 2) * image.width + x * moduleSize + moduleSize / 2]
            }
            XCTAssertLessThan(brightness(atModule: quietZone, quietZone), 128, "quietZone \(quietZone)")
            if quietZone > 0 {
                XCTAssertGreaterThan(brightness(atModule: quietZone - 1, quietZone - 1), 128, "quietZone \(quietZone)")
            }
        }
    }

    func testOnePixelModuleRenders() throws {
        let image = try NBUQRImageRenderer(moduleSize: 1, quietZoneModules: 0).cgImage(for: payload())
        XCTAssertTrue(NBUQRImageRenderer.allowedVersions.contains((image.width - 17) / 4))
    }
}
