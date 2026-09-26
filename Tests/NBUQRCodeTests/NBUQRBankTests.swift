import XCTest
@testable import NBUQRCode

// Персоніфіковані коди старту застосунку банків (додаток 4, п. 2 пп. 1) існують
// тільки для посилань: той самий Base64URL-payload, інший код старту застосунку перед ним.
// У графічний QR-код такий код старту застосунку не потрапляє ніколи.
final class NBUQRBankTests: XCTestCase {
    private func payload() throws -> NBUQRPayload {
        try NBUQRPayload(officialOnlineStorePayment())
    }

    func testPrivatBankDeepLinkHasCorrectPrefix() throws {
        let url = try payload().deepLink(for: .privatBank)
        XCTAssertTrue(url.absoluteString.hasPrefix("https://www.privat24.ua/rd/send_qr/nbu/"))
    }

    func testMonobankDeepLinkHasCorrectPrefix() throws {
        let url = try payload().deepLink(for: .monobank)
        XCTAssertTrue(url.absoluteString.hasPrefix("https://mbnk.app/qr/"))
    }

    func testCustomBankAppStartURLWithoutTrailingSlash() throws {
        let bank = NBUQRBank(name: "Example", appStartURL: URL(string: "https://bank.example/pay")!)
        let payload = try payload()
        XCTAssertEqual(payload.deepLink(for: bank).absoluteString, "https://bank.example/pay/" + payload.value)
    }

    func testCustomBankAppStartURLWithTrailingSlash() throws {
        let bank = NBUQRBank(name: "Example", appStartURL: URL(string: "https://bank.example/pay/")!)
        let payload = try payload()
        XCTAssertEqual(payload.deepLink(for: bank).absoluteString, "https://bank.example/pay/" + payload.value)
    }

    func testAllListsEveryBuiltInBankWithAName() {
        XCTAssertEqual(NBUQRBank.all, [
            .privatBank, .monobank, .privat24Business, .abank, .pumb, .raiffeisen,
            .ukrsibbank, .ukrgasbank, .otpBank, .creditAgricole, .radabank, .vstBank,
        ])
        XCTAssertEqual(NBUQRBank.privatBank.name, "Приват24")
        XCTAssertEqual(NBUQRBank.monobank.name, "monobank")
        XCTAssertFalse(NBUQRBank.all.contains { $0.name.isEmpty })
    }

    // Кнопки "Оплатити через ..." розрізняються за назвою, а посилання — за кодом
    // старту: дубль означав би дві однакові кнопки або дві назви одного застосунку.
    func testBuiltInBanksHaveDistinctNamesAndAppStartURLs() {
        XCTAssertEqual(Set(NBUQRBank.all.map(\.name)).count, NBUQRBank.all.count)
        XCTAssertEqual(Set(NBUQRBank.all.map(\.appStartURL)).count, NBUQRBank.all.count)
    }

    // Коди старту застосунку вбудованих банків закінчуються на "/" або "=", тож платіж
    // дописується до них дослівно — без жодного вставленого роздільника.
    func testEveryBuiltInDeepLinkIsAppStartURLFollowedByPayload() throws {
        let payload = try payload()
        for bank in NBUQRBank.all {
            XCTAssertEqual(
                payload.deepLink(for: bank).absoluteString,
                bank.appStartURL.absoluteString + payload.value,
                bank.name
            )
        }
    }

    // Raiffeisen приймає платіж у параметрі запиту: слеш після "=" потрапив би
    // в саме значення й зіпсував payload.
    func testRaiffeisenPayloadIsTheQueryParameterValue() throws {
        let payload = try payload()
        let components = try XCTUnwrap(URLComponents(url: payload.deepLink(for: .raiffeisen), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first { $0.name == "payload" }?.value, payload.value)
    }

    func testCustomAppStartURLEndingWithEqualsSignGetsNoSlash() throws {
        let bank = NBUQRBank(name: "Example", appStartURL: URL(string: "https://bank.example/pay?qr=")!)
        let payload = try payload()
        XCTAssertEqual(payload.deepLink(for: bank).absoluteString, "https://bank.example/pay?qr=" + payload.value)
    }

    func testCustomSchemeAppStartURL() throws {
        let bank = NBUQRBank(name: "Example", appStartURL: URL(string: "examplebank://pay/qr/")!)
        let payload = try payload()
        XCTAssertEqual(payload.deepLink(for: bank).absoluteString, "examplebank://pay/qr/" + payload.value)
    }

    func testDecoderRecognizesBankAppStartURLs() throws {
        let payment = officialOnlineStorePayment()
        let payload = try NBUQRPayload(payment)
        for bank in NBUQRBank.all {
            XCTAssertEqual(try NBUQRDecoder.parse(payload.deepLink(for: bank)).recipient, payment.recipient, bank.name)
        }
    }

    func testQRURLAlwaysUsesOfficialAppStartURL() throws {
        let url = try payload().qrURL()
        XCTAssertTrue(url.absoluteString.hasPrefix("https://qr.bank.gov.ua/"))
        XCTAssertEqual(NBUQRFormat.qrAppStartURL, "https://qr.bank.gov.ua/")
    }

    func testQRURLAndDeepLinksShareTheSamePayload() throws {
        let payload = try payload()
        XCTAssertTrue(try payload.qrURL().absoluteString.hasSuffix(payload.value))
        for bank in NBUQRBank.all {
            XCTAssertTrue(payload.deepLink(for: bank).absoluteString.hasSuffix(payload.value), bank.name)
        }
    }

    // Ліміт 507 байтів обмежує обсяг даних, що кодуються в зображення
    // (додаток 4, п. 8). Перехід за посиланням зображення не потребує, тому
    // довший код старту застосунку Приват24 (39 байтів проти 23) не робить посилання невалідним.
    func testDeepLinkIsNotLimitedByQRDataSize() throws {
        let payload = try NBUQRPayload(largestQRPayment(from: officialOnlineStorePayment()))
        XCTAssertGreaterThan(payload.value.utf8.count, NBUQRFormat.maxPayloadLength - 8)

        // Код старту застосунку Приват24 на 16 байтів довший за qr.bank.gov.ua, тож посилання виходить
        // за 507 байтів — і саме це не має заважати його побудувати.
        let privatURL = payload.deepLink(for: .privatBank).absoluteString
        XCTAssertGreaterThan(privatURL.utf8.count, NBUQRFormat.maxQRDataLength)
        XCTAssertTrue(privatURL.hasPrefix("https://www.privat24.ua/"))
    }

    // Посилання будується навіть тоді, коли для графічного QR-коду даних уже забагато.
    func testDeepLinkWorksWhereQRURLThrows() throws {
        var payment = officialOnlineStorePayment()
        payment.purpose = String(repeating: "т", count: 400)
        let payload = try NBUQRPayload(payment)

        XCTAssertThrowsError(try payload.qrURL())
        XCTAssertTrue(payload.deepLink(for: .monobank).absoluteString.hasSuffix(payload.value))
    }
}
