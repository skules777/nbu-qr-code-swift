import XCTest
@testable import NBUQRCode

// Значення полів узяті з офіційного прикладу Правил НБУ (додаток 4, приклад 4:
// оплата товару в інтернет-магазині, таблиця 9) ручним base64url-декодуванням
// його hex-байтів. Перевіряються вони round-trip'ом, а не побайтовим
// порівнянням payload: збігу байт-у-байт немає через поле 17
// (docs/NBU-COMPLIANCE.md, "Кодування даних", п. 10). Напряму звіряються
// лише байти Windows-1251 у полі "Отримувач" — там, де кодування має значення. На відміну від прикладу 1,
// тут текст і hex-байти дат не суперечать одне одному, тож дати теж
// перевіряються.
final class NBUQROfficialOnlineStoreExampleTests: XCTestCase {
    private var kyivCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = NBUQRFormat.timeZone
        return calendar
    }

    private var validUntil: Date {
        kyivCalendar.date(from: DateComponents(year: 2025, month: 3, day: 21, hour: 12, minute: 0, second: 0))!
    }

    private var createdAt: Date {
        kyivCalendar.date(from: DateComponents(year: 2025, month: 1, day: 29, hour: 12, minute: 0, second: 0))!
    }

    private func examplePayment() -> NBUQRPayment {
        var o = officialOnlineStorePayment()
        o.validUntil = validUntil
        o.createdAt = createdAt
        return o
    }

    func testOfficialExampleFieldsRoundTrip() throws {
        let o = examplePayment()
        let parsed = try parsedQR(o)

        XCTAssertEqual(parsed.function, "ICT")
        XCTAssertEqual(parsed.recipient, "ТОВ «ФК „ЕВО“»")
        XCTAssertEqual(parsed.iban, "UA673005280000026500504354077")
        XCTAssertEqual(parsed.amount, "UAH150")
        XCTAssertEqual(parsed.recipientCode, "37193071")
        XCTAssertEqual(parsed.category, "OTHR/GDDS")
        XCTAssertEqual(parsed.reference, "1225102576")
        XCTAssertEqual(parsed.purpose, o.purpose)
        XCTAssertEqual(parsed.displayText, o.displayText)
        XCTAssertEqual(parsed.lockMask, "FFFF")
        XCTAssertEqual(parsed.validUntil, "250321120000")
        XCTAssertEqual(parsed.createdAt, "250129120000")
    }

    func testWindows1251BytesMatchOfficialExample() {
        let recipientData = "ТОВ «ФК „ЕВО“»".data(using: .windowsCP1251)!
        let expectedBytes: [UInt8] = [
            0xD2, 0xCE, 0xC2, 0x20, 0xAB, 0xD4, 0xCA, 0x20,
            0x84, 0xC5, 0xC2, 0xCE, 0x93, 0xBB,
        ]
        XCTAssertEqual([UInt8](recipientData), expectedBytes)
    }
}
