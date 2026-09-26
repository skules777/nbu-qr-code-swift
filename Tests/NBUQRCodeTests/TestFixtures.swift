import CoreGraphics
import Foundation
import XCTest
@testable import NBUQRCode

func validPayment() -> NBUQRPayment {
    NBUQRPayment(
        function: .ict,
        recipient: "ТОВ \"Тестова компанія\"",
        iban: "UA511234567890123456789012345",
        amount: 100.50,
        recipientCode: "12345678",
        category: "MP2B/GSCB",
        reference: "REF-123",
        purpose: "Тестовий платіж"
    )
}

/// Додаток 4, приклад 4 (оплата товару в інтернет-магазині, таблиця 9) — офіційний
/// приклад із Постанови №97, звірений байт-у-байт (див.
/// `NBUQROfficialExampleTests`), не вигадані/бізнес-специфічні дані.
func officialOnlineStorePayment() -> NBUQRPayment {
    NBUQRPayment(
        function: .ict,
        encoding: .windows1251,
        recipient: "ТОВ «ФК „ЕВО“»",
        iban: "UA673005280000026500504354077",
        amount: 150,
        recipientCode: "37193071",
        category: "OTHR/GDDS",
        reference: "1225102576",
        purpose: "?MerchantBusinessName=\"ROZETKA.UA\", Покупка товарів, замовлення №821558965.",
        displayText: "?<InstrForCdtrAgt><InstrInf>MerchID:01234-TermId:43210</InstrInf></InstrForCdtrAgt>",
        editableFields: []
    )
}

func qrURL(_ payment: NBUQRPayment) throws -> URL {
    try NBUQRPayload(payment).qrURL()
}

func parsedQR(_ payment: NBUQRPayment) throws -> NBUQRParsedData {
    try NBUQRDecoder.parse(qrURL(payment))
}

/// Найбільший варіант `base` з призначенням "ттт…", для якого ще будується
/// `qrURL()`; зупиняється раніше, щойно посилання досягає `urlBytes`.
func largestQRPayment(from base: NBUQRPayment, reachingURLBytes urlBytes: Int = .max) -> NBUQRPayment {
    var probe = base
    var best = base
    for n in 1...420 {
        probe.purpose = String(repeating: "т", count: n)
        guard let url = try? qrURL(probe) else { break }
        best = probe
        if url.absoluteString.utf8.count >= urlBytes { break }
    }
    return best
}

/// Яскравість пікселів зображення, 0–255, рядок за рядком згори донизу.
func grayPixels(of image: CGImage) throws -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height)
    let context = try XCTUnwrap(CGContext(
        data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width, space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    ))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return pixels
}
