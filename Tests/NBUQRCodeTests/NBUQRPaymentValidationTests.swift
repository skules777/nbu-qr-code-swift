import XCTest
@testable import NBUQRCode

private func issue(_ field: NBUQRField, _ problem: NBUQRValidationIssue.Problem) -> NBUQRValidationIssue {
    NBUQRValidationIssue(field: field, problem: problem)
}

final class NBUQRPaymentValidationTests: XCTestCase {
    func testValidPaymentProducesNoIssues() {
        XCTAssertEqual(validPayment().validate(), [])
    }

    func testEmptyRecipientFails() {
        var o = validPayment(); o.recipient = ""
        XCTAssertTrue(o.validate().contains(issue(.recipient, .missing)))
    }

    func testEmptyIBANFails() {
        var o = validPayment(); o.iban = ""
        XCTAssertTrue(o.validate().contains(issue(.iban, .missing)))
    }

    func testWrongLengthIBANFails() {
        var o = validPayment(); o.iban = "INVALID_IBAN"
        XCTAssertTrue(o.validate().contains(issue(.iban, .invalidFormat)))
    }

    func testNonUkrainianIBANFails() {
        var o = validPayment(); o.iban = "DE511234567890123456789012345"
        XCTAssertTrue(o.validate().contains(issue(.iban, .invalidFormat)))
    }

    func testNonASCIIDigitsInIBANFail() {
        // Арабо-індійські цифри проходять `Character.isNumber`, але не є рахунком.
        var o = validPayment(); o.iban = "UA5112345678901234567890123\u{0664}\u{0665}"
        XCTAssertTrue(o.validate().contains(issue(.iban, .invalidFormat)))
    }

    func testWrongIBANChecksumFails() {
        var o = validPayment(); o.iban = "UA521234567890123456789012345"
        XCTAssertTrue(o.validate().contains(issue(.iban, .invalidChecksum)))
    }

    func testValidChecksumPassesValidation() {
        // Реальні рахунки з офіційних прикладів Правил (додаток 4, приклади 1 і 4).
        for iban in ["UA201234560000000260323012042", "UA673005280000026500504354077"] {
            var o = validPayment(); o.iban = iban
            XCTAssertEqual(o.validate(), [], iban)
        }
    }

    func testChecksumIsCheckedOnlyAfterShapeIsValid() {
        // Один рахунок — одна помилка: контрольну суму немає сенсу рахувати
        // для рядка, який ще не є IBAN за формою.
        var o = validPayment(); o.iban = "DE511234567890123456789012345"
        XCTAssertFalse(o.validate().contains(issue(.iban, .invalidChecksum)))
    }

    func testSpacesInIBANAreIgnored() {
        var o = validPayment(); o.iban = "UA51 1234 5678 9012 3456 7890 12345"
        XCTAssertEqual(o.validate(), [])
    }

    func testEmptyRecipientCodeFails() {
        var o = validPayment(); o.recipientCode = ""
        XCTAssertTrue(o.validate().contains(issue(.recipientCode, .missing)))
    }

    func testEmptyPurposeFails() {
        var o = validPayment(); o.purpose = ""
        XCTAssertTrue(o.validate().contains(issue(.purpose, .missing)))
    }

    func testNegativeAmountFails() {
        var o = validPayment(); o.amount = -100
        XCTAssertTrue(o.validate().contains(issue(.amount, .outOfRange)))
    }

    func testTooLargeAmountFails() {
        var o = validPayment(); o.amount = 1_000_000_000
        XCTAssertTrue(o.validate().contains(issue(.amount, .outOfRange)))
    }

    func testMaximumAmountFromFloatLiteralPasses() throws {
        // Літерал проходить через Double і стає Decimal 999999999.990000009….
        var o = validPayment(); o.amount = 999999999.99
        XCTAssertEqual(o.validate(), [])
        XCTAssertEqual(try parsedQR(o).amount, "UAH999999999.99")
    }

    func testAmountIsCheckedAfterRoundingToKopecks() throws {
        var roundsDown = validPayment(); roundsDown.amount = Decimal(string: "999999999.994")
        XCTAssertEqual(roundsDown.validate(), [])
        XCTAssertEqual(try parsedQR(roundsDown).amount, "UAH999999999.99")

        var roundsUp = validPayment(); roundsUp.amount = Decimal(string: "999999999.995")
        XCTAssertTrue(roundsUp.validate().contains(issue(.amount, .outOfRange)))
    }

    func testTinyNegativeAmountFailsEvenThoughItRoundsToZero() {
        var o = validPayment(); o.amount = Decimal(string: "-0.001")
        XCTAssertTrue(o.validate().contains(issue(.amount, .outOfRange)))
    }

    func testTooLongRecipientFails() {
        var o = validPayment(); o.recipient = String(repeating: "А", count: 141)
        XCTAssertTrue(o.validate().contains(issue(.recipient, .tooLong(max: 140, unit: .characters))))
    }

    func testTooLongRecipientCodeFails() {
        var o = validPayment(); o.recipientCode = "12345678901"
        XCTAssertTrue(o.validate().contains(issue(.recipientCode, .tooLong(max: 10, unit: .bytes))))
    }

    func testRecipientCodeByteLimitCountsBytesNotCharactersForUTF8() {
        // 10 кириличних символів = 10 байт у Windows-1251, але 20 байт у UTF-8 —
        // поле 9 задеклароване в БАЙТАХ (таблиця 2 додатка 4), тому має впасти
        // лише для UTF-8.
        let tooLong = issue(.recipientCode, .tooLong(max: 10, unit: .bytes))
        let tenCyrillicChars = String(repeating: "А", count: 10)

        var utf8Payment = validPayment()
        utf8Payment.encoding = .utf8
        utf8Payment.recipientCode = tenCyrillicChars
        XCTAssertTrue(utf8Payment.validate().contains(tooLong))

        var windows1251Payment = validPayment()
        windows1251Payment.encoding = .windows1251
        windows1251Payment.recipientCode = tenCyrillicChars
        XCTAssertFalse(windows1251Payment.validate().contains(tooLong))
    }

    func testMalformedCategoryFails() {
        let malformed = [
            "1234567890",      // задовгий
            "MP2B",            // без другої частини
            "MP2B/",           // друга частина порожня
            "MP2/GSCB",        // перша частина коротша за 4
            "MP2B/GSCBB",      // друга частина довша за 4
            "mp2b/gscb",       // нижній регістр
            "MP2B GSCB",       // без роздільника
            "MP2B/GSCB/XXXX",  // зайва частина
        ]
        for category in malformed {
            var o = validPayment(); o.category = category
            XCTAssertTrue(o.validate().contains(issue(.category, .invalidFormat)), "expected \(category) to be rejected")
        }
    }

    func testWellFormedCategoryPasses() {
        for category in ["MP2B/GSCB", "SUPP/SUPP", "OTHR/GDDS", "1234/5678"] {
            var o = validPayment(); o.category = category
            XCTAssertEqual(o.validate(), [], category)
        }
    }

    // Офіційного переліку значень CCCC/PPPP немає, тож вимагати поле 10 від
    // користувача не можна — порожнє значення лишається валідним.
    func testEmptyCategoryPasses() {
        var o = validPayment(); o.category = ""
        XCTAssertEqual(o.validate(), [])
    }

    // Приват24 відхиляє код із порожнім полем 10 (і QR, і посилання), тож порожня
    // категорія кодується як "інше / інше" за ISO 20022, а не лишається порожньою.
    func testEmptyCategoryIsEncodedAsOther() throws {
        var o = validPayment(); o.category = ""
        XCTAssertEqual(try parsedQR(o).category, "OTHR/OTHR")
        let withDefaults = NBUQRPayment(recipient: "К", iban: "UA511234567890123456789012345", recipientCode: "1", purpose: "Ч")
        XCTAssertEqual(try NBUQRDecoder.parse(payload: NBUQRPayload(withDefaults).value).category, "OTHR/OTHR")
    }

    func testTooLongReferenceFails() {
        var o = validPayment(); o.reference = String(repeating: "A", count: 36)
        XCTAssertTrue(o.validate().contains(issue(.reference, .tooLong(max: 35, unit: .characters))))
    }

    func testTooLongPurposeFails() {
        var o = validPayment(); o.purpose = String(repeating: "А", count: 421)
        XCTAssertTrue(o.validate().contains(issue(.purpose, .tooLong(max: 420, unit: .characters))))
    }

    func testTooLongDisplayTextFails() {
        var o = validPayment(); o.displayText = String(repeating: "А", count: 141)
        XCTAssertTrue(o.validate().contains(issue(.displayText, .tooLong(max: 140, unit: .characters))))
    }

    func testAnyEditableFieldsPassValidation() {
        for fields in [nil, [], [.amount], Set(NBUQREditableField.allCases)] as [Set<NBUQREditableField>?] {
            var o = validPayment(); o.editableFields = fields
            XCTAssertEqual(o.validate(), [], "\(String(describing: fields))")
        }
    }

    func testDELCharacterInRecipientFails() {
        var o = validPayment(); o.recipient = "Тест\u{7F}Отримувач"
        XCTAssertTrue(o.validate().contains(issue(.recipient, .forbiddenCharacters)))
    }

    func testNBSPCharacterInPurposeFails() {
        var o = validPayment(); o.purpose = "Оплата\u{A0}товару"
        XCTAssertTrue(o.validate().contains(issue(.purpose, .forbiddenCharacters)))
    }

    // Додаток 1, п. 4 дозволяє символи лише від 32 — усе нижче заборонено.
    // Найнебезпечніший з них — LF: у структурі QR він є роздільником полів.
    func testControlCharactersInTextFieldsFail() {
        let controls: [(String, Unicode.Scalar)] = [
            ("LF", "\u{0A}"), ("CR", "\u{0D}"), ("TAB", "\u{09}"), ("NUL", "\u{00}"),
        ]
        for (name, scalar) in controls {
            var o = validPayment(); o.purpose = "Оплата\(Character(scalar))товару"
            XCTAssertTrue(o.validate().contains(issue(.purpose, .forbiddenCharacters)), "expected \(name) to be rejected")
        }
    }

    // Перенос рядка в призначенні платежу не спотворює значення, а зсуває всю
    // структуру на одне поле — тому кодування має впасти, а не видати "валідний"
    // QR з поїхалими реквізитами.
    func testLineFeedInPurposeCannotShiftStructure() {
        var o = validPayment()
        o.purpose = "За каву\nUA111111111111111111111111111"
        XCTAssertThrowsError(try NBUQRPayload(o))
    }

    func testIBANWithNonBreakingSpacesPasses() throws {
        // Виписки групують цифри IBAN через NBSP (U+00A0) чи вузький NBSP (U+202F).
        var o = validPayment(); o.iban = "UA51\u{A0}1234\u{A0}5678\u{202F}9012\u{A0}3456\u{A0}7890\u{A0}12345"
        XCTAssertEqual(o.validate(), [])
        XCTAssertEqual(try parsedQR(o).iban, "UA511234567890123456789012345")
    }

    func testIBANWithTabIsStillRejected() {
        var o = validPayment(); o.iban = "UA51\t1234567890123456789012345"
        XCTAssertTrue(o.validate().contains(issue(.iban, .forbiddenCharacters)))
    }

    func testControlCharactersAreRejectedInEveryTextField() {
        let cases: [(NBUQRField, WritableKeyPath<NBUQRPayment, String>, String)] = [
            (.recipient, \.recipient, "ТОВ\u{0A}Тест"),
            (.recipientCode, \.recipientCode, "401\u{0A}214"),
            (.reference, \.reference, "REF\u{0A}123"),
            (.displayText, \.displayText, "Текст\u{0A}далі"),
            (.iban, \.iban, "UA51\u{0A}1234567890123456789012345"),
        ]
        for (field, keyPath, value) in cases {
            var o = validPayment(); o[keyPath: keyPath] = value
            XCTAssertTrue(o.validate().contains(issue(field, .forbiddenCharacters)), "\(field)")
        }
    }

    func testPayloadThrowsAllIssuesOnValidationFailure() {
        var o = validPayment(); o.recipient = ""; o.purpose = ""
        XCTAssertThrowsError(try NBUQRPayload(o)) { error in
            XCTAssertEqual(error as? NBUQRError, .invalidPayment([issue(.recipient, .missing), issue(.purpose, .missing)]))
        }
    }

    func testIssueDescriptionNamesFieldAndProblem() {
        XCTAssertEqual(
            issue(.recipientCode, .tooLong(max: 10, unit: .bytes)).description,
            "recipientCode is too long (max 10 bytes)"
        )
    }
}

// Таблиця 1 додатка 4 обмежує довжину самого Base64URL-вмісту (рядок 2, 475 B)
// окремо від загального обсягу даних (п. 8 розділу IV, 507 B). З 23-байтовим
// кодом старту застосунку qr.bank.gov.ua першим настає обмеження таблиці 1.
final class NBUQRPayloadSizeTests: XCTestCase {
    func testPayloadLimitIsTheStricterOfTheTwoStandardLimits() {
        XCTAssertEqual(NBUQRFormat.maxPayloadLength, 475)
        XCTAssertLessThanOrEqual(
            NBUQRFormat.qrAppStartURL.utf8.count + NBUQRFormat.maxPayloadLength,
            NBUQRFormat.maxQRDataLength
        )
    }

    func testLargestAcceptedPaymentFitsBothLimits() throws {
        let payload = try NBUQRPayload(largestQRPayment(from: officialOnlineStorePayment()))
        XCTAssertLessThanOrEqual(payload.value.utf8.count, NBUQRFormat.maxPayloadLength)
        XCTAssertLessThanOrEqual(try payload.qrURL().absoluteString.utf8.count, NBUQRFormat.maxQRDataLength)
    }

    func testOversizedPayloadIsRejectedForQR() throws {
        var o = officialOnlineStorePayment()
        o.purpose = String(repeating: "т", count: 400)
        let payload = try NBUQRPayload(o)
        XCTAssertThrowsError(try payload.qrURL()) { error in
            guard case NBUQRError.qrDataTooLong(let actual, let max) = error else {
                return XCTFail("expected qrDataTooLong, got \(error)")
            }
            XCTAssertGreaterThan(actual, max)
            XCTAssertEqual(max, NBUQRFormat.maxPayloadLength)
        }
    }
}

// `validate()` має бути повною відповіддю на питання "чи закодується платіж":
// порожній результат зобовʼязує `NBUQRPayload(_:)` завершитись успіхом.
final class NBUQRValidationCompletenessTests: XCTestCase {
    func testNonASCIIReferenceIsRejectedByValidation() {
        var o = validPayment(); o.reference = "ЗАМОВЛЕННЯ-1"
        XCTAssertTrue(o.validate().contains(issue(.reference, .unsupportedCharacters)))
    }

    func testCharactersOutsideWindows1251AreRejectedByValidation() {
        var o = validPayment()
        o.encoding = .windows1251
        o.recipient = "株式会社テスト"
        XCTAssertTrue(o.validate().contains(issue(.recipient, .unsupportedCharacters)))
    }

    // Додаток 1, п. 4: UTF-8 дозволяє лише еквіваленти символів Windows-1251, тож
    // зміна кодування не має розширювати набір символів.
    func testCharactersOutsideWindows1251AreRejectedUnderUTF8Encoding() {
        var o = validPayment()
        o.encoding = .utf8
        o.recipient = "株式会社テスト"
        o.purpose = "Оплата 😀"
        let issues = o.validate()
        XCTAssertTrue(issues.contains(issue(.recipient, .unsupportedCharacters)))
        XCTAssertTrue(issues.contains(issue(.purpose, .unsupportedCharacters)))
    }

    func testWindows1251CharactersPassUnderUTF8Encoding() {
        var o = validPayment()
        o.encoding = .utf8
        o.recipient = "ТОВ «Ґрунт» — Київ"
        o.purpose = "Замовлення №15, 20 € ‰"
        XCTAssertEqual(o.validate(), [])
        XCTAssertNoThrow(try qrURL(o))
    }

    // Контрактний тест: порожня валідація ⇔ успішне кодування. Кодування
    // невалідованого значення впало б на precondition, а не кинуло помилку,
    // тож тут перевіряється, що validate() відсіює кожен такий вхід.
    func testValidationAgreesWithPayloadCreation() {
        var probes: [NBUQRPayment] = []
        func probe(_ mutate: (inout NBUQRPayment) -> Void) {
            var o = validPayment(); mutate(&o); probes.append(o)
        }
        probe { $0.reference = "ЗАМОВЛЕННЯ-1" }
        probe { $0.reference = "REF-123" }
        probe { $0.recipient = "株式会社テスト" }
        probe { $0.purpose = "Оплата 😀" }
        probe { $0.displayText = "Тест\u{2028}далі" }
        probe { $0.recipientCode = "Код😀" }
        probe { $0.purpose = String(repeating: "т", count: 400) }
        probe { $0.encoding = .utf8; $0.recipient = "株式会社テスト" }

        for o in probes {
            let valid = o.validate().isEmpty
            let created = (try? NBUQRPayload(o)) != nil
            XCTAssertEqual(valid, created, "\(o)")
        }
    }
}
