import XCTest
@testable import NBUQRCode

final class NBUQREditableFieldTests: XCTestCase {
    func testAmountAloneProducesFEFF() {
        XCTAssertEqual(NBUQRLockMask.hex(editable: [.amount]), "FEFF")
    }

    func testEmptySetLocksEverything() {
        XCTAssertEqual(NBUQRLockMask.hex(editable: []), "FFFF")
    }

    func testAllFieldsProducesExpectedMask() {
        // Кожен з 7 togglable-бітів (6,7,8,9,10,12,13) очищений; 0,1-5,11,14,15 лишаються 1.
        XCTAssertEqual(NBUQRLockMask.hex(editable: Set(NBUQREditableField.allCases)), "C83F")
    }

    func testCombiningMultipleFields() {
        // 1<<8 | 1<<12 = 0x100 | 0x1000 = 0x1100; ~0x1100 & 0xFFFF = 0xEEFF
        XCTAssertEqual(NBUQRLockMask.hex(editable: [.amount, .purpose]), "EEFF")
    }

    func testNilLeavesField14Empty() throws {
        var o = validPayment(); o.editableFields = nil
        XCTAssertEqual(try parsedQR(o).lockMask, "")
    }

    func testEditableFieldsReachTheEncodedMask() throws {
        var o = validPayment(); o.editableFields = [.amount]
        XCTAssertEqual(try parsedQR(o).lockMask, "FEFF")
    }

    func testDecodeRoundTrip() {
        let original: Set<NBUQREditableField> = [.amount, .recipientCode]
        XCTAssertEqual(NBUQRLockMask.editableFields(fromHex: NBUQRLockMask.hex(editable: original)), original)
    }

    func testDecodeIgnoresUnknownBits() {
        // Останній нібл "0" очищає й невідомий/невживаний біт 0 — decode має це проігнорувати
        // й повернути лише розпізнані поля.
        XCTAssertEqual(NBUQRLockMask.editableFields(fromHex: "FEFE"), [.amount])
    }

    func testDecodeAcceptsShortAndLowercaseMasks() {
        // Поле 14 — hex-число змінної довжини (таблиця 2), тож "FEF" означає 0x0FEF:
        // старші біти призначення й відображення нульові, тож ці поля можна змінювати.
        XCTAssertEqual(NBUQRLockMask.editableFields(fromHex: "FEF"), [.purpose, .displayText])
        XCTAssertEqual(NBUQRLockMask.editableFields(fromHex: "feff"), [.amount])
    }

    func testDecodeRejectsWrongLength() {
        XCTAssertNil(NBUQRLockMask.editableFields(fromHex: ""))
        XCTAssertNil(NBUQRLockMask.editableFields(fromHex: "FEFFF"))
    }

    func testDecodeRejectsNonHex() {
        XCTAssertNil(NBUQRLockMask.editableFields(fromHex: "ZZZZ"))
        XCTAssertNil(NBUQRLockMask.editableFields(fromHex: "+FFF"))
        XCTAssertNil(NBUQRLockMask.editableFields(fromHex: "\u{FF26}\u{FF25}\u{FF26}\u{FF26}"))
    }

    // Маску будує сама бібліотека, тож п. 4.14 ("зміна полів 1–5, 11, 14, 15
    // завжди заборонена") мусить виконуватись для будь-якої множини полів.
    func testEveryConstructedMaskKeepsAlwaysLockedFields() {
        let all = NBUQREditableField.allCases
        for bits in 0..<(1 << all.count) {
            let fields = Set(all.enumerated().filter { bits & (1 << $0.offset) != 0 }.map(\.element))
            let value = UInt16(NBUQRLockMask.hex(editable: fields), radix: 16)!
            XCTAssertEqual(value & NBUQRLockMask.alwaysLockedBits, NBUQRLockMask.alwaysLockedBits, "\(fields)")
        }
    }
}
