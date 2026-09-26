import Foundation

/// Провалідований і закодований платіж: Base64URL-вміст структури даних QR-коду
/// версії формату 003 (таблиця 2 додатка 4), без "Коду старту застосунку".
///
/// Створюється лише з платежу, що пройшов `NBUQRPayment.validate()`, тож усе,
/// що з нього будується, — посилання для QR-коду, посилання в застосунок банку,
/// графічне зображення — вже не може впасти на валідації.
public struct NBUQRPayload: Hashable, Sendable {
    /// Base64URL-вміст, спільний для QR-коду й усіх посилань — різниться лише код старту застосунку.
    public let value: String

    /// Кидає `NBUQRError.invalidPayment`, якщо `payment.validate()` не порожній.
    public init(_ payment: NBUQRPayment) throws {
        let issues = payment.validate()
        guard issues.isEmpty else {
            throw NBUQRError.invalidPayment(issues)
        }
        value = NBUQRFormat.base64URLEncode(NBUQRFormat.data(for: payment))
    }

    /// Посилання, яке кодується в графічний QR-код. Код старту застосунку
    /// завжди `https://qr.bank.gov.ua/` — лише такий QR читають сканери всіх банків
    /// (docs/NBU-COMPLIANCE.md, "QR-код і deep link").
    ///
    /// Кидає `NBUQRError.qrDataTooLong`, якщо вміст не вміщується в ліміти
    /// обсягу даних графічного QR-коду.
    public func qrURL() throws -> URL {
        guard value.utf8.count <= NBUQRFormat.maxPayloadLength else {
            throw NBUQRError.qrDataTooLong(actual: value.utf8.count, max: NBUQRFormat.maxPayloadLength)
        }
        return NBUQRFormat.join(appStartURL: NBUQRFormat.qrAppStartURL, payload: value)
    }

    /// Посилання, що відкриває платіж напряму в застосунку банку (додаток 4,
    /// п. 2 пп. 1) — для кнопки "Оплатити через ...", не для QR-коду.
    ///
    /// Ліміти обсягу даних тут не застосовуються: вони обмежують дані, які
    /// кодуються в зображення, а перехід за посиланням зображення не потребує.
    /// Тому посилання лишається робочим навіть там, де `qrURL()` уже кидає.
    public func deepLink(for bank: NBUQRBank) -> URL {
        NBUQRFormat.join(appStartURL: bank.appStartURL.absoluteString, payload: value)
    }
}
