import XCTest
@testable import NBUQRCode

final class NBUQRPayloadRoundTripTests: XCTestCase {
    func testURLRoundTrip() throws {
        let url = try qrURL(validPayment()).absoluteString
        XCTAssertTrue(url.hasPrefix("https://qr.bank.gov.ua/"))
        XCTAssertLessThanOrEqual(url.utf8.count, NBUQRFormat.maxQRDataLength)

        let parsed = try parsedQR(validPayment())
        XCTAssertEqual(parsed.serviceTag, "BCD")
        XCTAssertEqual(parsed.version, "003")
        XCTAssertEqual(parsed.function, "ICT")
        XCTAssertEqual(parsed.recipient, "ТОВ \"Тестова компанія\"")
        XCTAssertEqual(parsed.iban, "UA511234567890123456789012345")
    }

    func testPayloadValueIsTheQRURLWithoutHost() throws {
        let payload = try NBUQRPayload(validPayment())
        XCTAssertEqual(try payload.qrURL().absoluteString, "https://qr.bank.gov.ua/" + payload.value)
        XCTAssertEqual(try NBUQRDecoder.parse(payload: payload.value), try parsedQR(validPayment()))
    }

    func testEqualPaymentsProduceEqualPayloads() throws {
        XCTAssertEqual(validPayment(), validPayment())
        XCTAssertEqual(try NBUQRPayload(validPayment()), try NBUQRPayload(validPayment()))
    }

    func testNilAmountProducesEmptyAmountField() throws {
        var o = validPayment(); o.amount = nil
        XCTAssertEqual(try parsedQR(o).amount, "")
    }

    // Додаток 4, п. 4.8: копійки або відсутні, або записані рівно двома цифрами.
    func testAmountFormatting() throws {
        let cases: [(Decimal, String)] = [
            (100, "UAH100"),
            (100.00, "UAH100"),
            (100.5, "UAH100.50"),
            (100.50, "UAH100.50"),
            (100.10, "UAH100.10"),
            (100.99, "UAH100.99"),
            (100.05, "UAH100.05"),
            (0, "UAH0"),
            (0.5, "UAH0.50"),
            (0.01, "UAH0.01"),
            // Через Decimal(string:), бо десятковий літерал у Swift спершу стає
            // Double і на межі діапазону дає значення, більше за дозволене.
            (Decimal(string: "999999999.99")!, "UAH999999999.99"),
            (Decimal(string: "999999999.90")!, "UAH999999999.90"),
            (Decimal(string: "100.994")!, "UAH100.99"),
            (Decimal(string: "100.996")!, "UAH101"),
        ]
        for (amount, expected) in cases {
            var o = validPayment(); o.amount = amount
            XCTAssertEqual(try parsedQR(o).amount, expected, "amount \(amount)")
        }
    }

    // Поля 15–16 кодуються в київському часі незалежно від поясу машини.
    func testDateTimeFormatting() throws {
        var kyiv = Calendar(identifier: .gregorian)
        kyiv.timeZone = NBUQRFormat.timeZone
        let date = kyiv.date(from: DateComponents(year: 2025, month: 9, day: 21, hour: 12, minute: 30, second: 45))!

        var o = validPayment()
        o.validUntil = date
        o.createdAt = date

        let parsed = try parsedQR(o)
        XCTAssertEqual(parsed.validUntil, "250921123045")
        XCTAssertEqual(parsed.createdAt, "250921123045")
    }

    // Той самий момент часу, заданий у будь-якому іншому поясі, має дати ті
    // самі цифри: інакше байти залежали б від того, де виконується код.
    func testSameInstantEncodesIdenticallyRegardlessOfCallerTimeZone() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        // 21.09.2025 09:30:45 UTC — це 12:30:45 за Києвом (літній час, +3).
        let instant = utc.date(from: DateComponents(year: 2025, month: 9, day: 21, hour: 9, minute: 30, second: 45))!

        var o = validPayment()
        o.validUntil = instant
        XCTAssertEqual(try parsedQR(o).validUntil, "250921123045")
    }

    // Україна переходить на зимовий час: та сама дата взимку має дати +2, а не +3.
    func testWinterTimeUsesStandardOffset() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let instant = utc.date(from: DateComponents(year: 2025, month: 12, day: 21, hour: 10, minute: 30, second: 45))!

        var o = validPayment()
        o.validUntil = instant
        XCTAssertEqual(try parsedQR(o).validUntil, "251221123045")
    }

    func testDecoderRejectsUnknownHost() {
        XCTAssertThrowsError(try NBUQRDecoder.parse(URL(string: "https://invalid.com/test")!))
    }
}
