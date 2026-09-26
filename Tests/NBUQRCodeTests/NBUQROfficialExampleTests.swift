import XCTest
@testable import NBUQRCode

// Значення полів узяті з офіційного прикладу Правил НБУ (додаток 4, приклад 1:
// оплата комунальних послуг) ручним base64url-декодуванням його hex-байтів.
// Перевіряються вони round-trip'ом, а не побайтовим порівнянням payload:
// збігу байт-у-байт немає через поле 17 (docs/NBU-COMPLIANCE.md, "Кодування даних", п. 10).
// Напряму звіряються лише байти Windows-1251 у полі "Отримувач" — там, де
// кодування має значення. Дати в прикладі документа текстово суперечать
// власним hex-байтам — схоже на артефакт PDF, тому тут не перевіряються.
final class NBUQROfficialExampleTests: XCTestCase {
    private func officialExamplePayment() -> NBUQRPayment {
        NBUQRPayment(
            function: .uct,
            encoding: .windows1251,
            recipient: "ТОВ «ГК«Нафтогаз України»",
            iban: "UA201234560000000260323012042",
            amount: 2998.39,
            recipientCode: "40121452",
            category: "SUPP/SUPP",
            reference: "AA15678-679",
            purpose: "?TickNo=\u{201D}YA1267\u{201D}&Addr=\u{201D}вулиця Лугова, буд. 911,Микитинцi\u{201D}",
            editableFields: [.amount]
        )
    }

    func testOfficialExampleFieldsRoundTrip() throws {
        let o = officialExamplePayment()
        let parsed = try parsedQR(o)

        XCTAssertEqual(parsed.function, "UCT")
        XCTAssertEqual(parsed.recipient, "ТОВ «ГК«Нафтогаз України»")
        XCTAssertEqual(parsed.iban, "UA201234560000000260323012042")
        XCTAssertEqual(parsed.amount, "UAH2998.39")
        XCTAssertEqual(parsed.recipientCode, "40121452")
        XCTAssertEqual(parsed.category, "SUPP/SUPP")
        XCTAssertEqual(parsed.reference, "AA15678-679")
        XCTAssertEqual(parsed.purpose, o.purpose)
        XCTAssertEqual(parsed.lockMask, "FEFF")
    }

    func testOfficialExampleLockMaskDecodesToAmount() throws {
        let parsed = try parsedQR(officialExamplePayment())
        XCTAssertEqual(NBUQRLockMask.editableFields(fromHex: parsed.lockMask), [.amount])
    }

    func testWindows1251BytesMatchOfficialExample() {
        let recipientData = "ТОВ «ГК«Нафтогаз України»".data(using: .windowsCP1251)!
        let expectedBytes: [UInt8] = [
            0xD2, 0xCE, 0xC2, 0x20, 0xAB, 0xC3, 0xCA, 0xAB, 0xCD,
            0xE0, 0xF4, 0xF2, 0xEE, 0xE3, 0xE0, 0xE7, 0x20, 0xD3,
            0xEA, 0xF0, 0xE0, 0xBF, 0xED, 0xE8, 0xBB,
        ]
        XCTAssertEqual([UInt8](recipientData), expectedBytes)
    }
}
