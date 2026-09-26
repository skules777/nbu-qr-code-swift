import Foundation

/// Константи й байтове кодування формату 003 (додаток 4 до Правил).
enum NBUQRFormat {
    static let version = "003"
    static let serviceTag = "BCD"
    /// Єдиний код старту застосунку для графічного QR-коду. Постанова дозволяє
    /// й персоніфікований код старту застосунку банку, але такий QR читає лише сканер цього
    /// банку (docs/NBU-COMPLIANCE.md, "QR-код і deep link").
    static let qrAppStartURL = "https://qr.bank.gov.ua/"
    /// Версія формату 003 передбачає єдину валюту — гривню, тож валюта є
    /// константою формату, а не параметром платежу.
    static let currencyCode = "UAH"
    /// Максимальний обсяг даних, які кодуються в графічний QR-код
    /// (додаток 4, п. 8 розділу IV). Обмеження стосується саме зображення,
    /// тому на посилання (`deepLink`) не поширюється.
    static let maxQRDataLength = 507
    /// Максимальна довжина Base64URL-вмісту. Постанова задає два обмеження, які
    /// не узгоджені між собою: довжину елемента "Закодовані елементи структури
    /// даних" (таблиця 1, рядок 2 — 475 B) і загальний обсяг даних (п. 8 —
    /// 507 B, хоча 50 B коду старту застосунку плюс 475 B вмісту дають 525). Сумісний генератор
    /// має задовольняти обидва, тож береться менше — з 23-байтовим кодом старту застосунку
    /// `qr.bank.gov.ua` першим настає обмеження таблиці 1.
    static let maxPayloadLength = min(475, maxQRDataLength - qrAppStartURL.utf8.count)

    static let maxAmount = Decimal(string: "999999999.99")!

    /// Часовий пояс, у якому інтерпретуються `validUntil`/`createdAt`.
    /// Поля 15–16 кодуються як 12 цифр `РРММДДГГХХСС` без будь-якої позначки
    /// часового поясу, тож обидві сторони мусять мовчки припускати один і той
    /// самий пояс. Для внутрішньоукраїнського стандарту це київський час —
    /// і це не налаштування, а частина інтерпретації формату.
    ///
    /// `TimeZone.current` тут був би пасткою: бекенд у Docker (типово UTC)
    /// записав би термін дії на 2–3 години раніше, ніж задумав отримувач, а
    /// QR при цьому лишався б валідним на вигляд. Перевірено сканером —
    /// monobank і Sense Bank справді відхиляють протермінований код.
    static let timeZone: TimeZone = {
        // "Europe/Kyiv" зʼявився лише в tzdata 2022b; на системах зі старішою
        // базою (а ми підтримуємо iOS 15, що вийшла 2021 року) лишається тільки
        // колишня назва. Останній запасний варіант губить літній час, але
        // недосяжний: без обох ідентифікаторів зламана вся часова база системи.
        TimeZone(identifier: "Europe/Kyiv")
            ?? TimeZone(identifier: "Europe/Kiev")
            ?? TimeZone(secondsFromGMT: 2 * 3600)!
    }()

    // Base64URL містить лише URL-безпечні символи, тож дописаний до коду старту застосунку,
    // який сам є валідною адресою, він завжди дає валідну адресу.
    // На "=" закінчується код старту застосунку з параметром запиту (Raiffeisen: `?payload=`):
    // слеш там зіпсував би значення параметра.
    static func join(appStartURL: String, payload: String) -> URL {
        let separator = appStartURL.hasSuffix("/") || appStartURL.hasSuffix("=") ? "" : "/"
        return URL(string: appStartURL + separator + payload)!
    }

    /// Байтова структура даних QR-коду (таблиця 2 додатка 4), до Base64URL-кодування.
    /// Поля, позначені в Правилах символом "*", кодуються обраним у `encoding`
    /// способом (UTF-8 або Windows-1251); решта полів — символи ISO 646 (ASCII).
    static func data(for payment: NBUQRPayment) -> Data {
        // Сюди доходять лише значення, що пройшли `validate()`, а вона відхиляє саме
        // ті рядки, яких ці енкодери не можуть подати, тож збій тут — баг валідації.
        func encode(_ value: String, _ encoding: String.Encoding) -> Data {
            guard let data = value.data(using: encoding) else {
                preconditionFailure("A validated NBUQRPayment field is not encodable: \(value)")
            }
            return data
        }
        func ascii(_ value: String) -> Data { encode(value, .ascii) }
        func text(_ value: String) -> Data { encode(value, payment.encoding.stringEncoding) }

        let parts: [Data] = [
            ascii(serviceTag),
            ascii(version),
            ascii(payment.encoding.rawValue),
            ascii(payment.function.rawValue),
            Data(), // unique_id — RFU
            text(payment.recipient),
            ascii(payment.normalizedIBAN),
            ascii(formatAmount(payment.amount)),
            text(payment.recipientCode),
            ascii(payment.category),
            ascii(payment.reference),
            text(payment.purpose),
            text(payment.displayText),
            ascii(payment.editableFields.map(NBUQRLockMask.hex(editable:)) ?? ""),
            ascii(formatDateTime(payment.validUntil)),
            ascii(formatDateTime(payment.createdAt)),
            // Поле 17 лишається порожнім, хоча всі чотири офіційні приклади формату 003
            // мають у ньому "RFU": це позначка з колонки таблиці "Наповнення / зміст", а не
            // значення — поле 5, зарезервоване так само, у тих самих прикладах порожнє.
            // До того ж "RFU" зашкодив би: за п. 4.16 непорожнє поле 17 робить поле 16
            // (created_at) обов'язковим, а тут воно опціональне. Ціна — згенеровані байти
            // не можуть дослівно збігтися з прикладами.
            Data(), // signature
        ]

        return parts.reduce(Data()) { result, part in
            result.isEmpty ? part : result + Data([0x0A]) + part
        }
    }

    static func roundedToKopecks(_ amount: Decimal) -> Decimal {
        var rounded = Decimal()
        var value = amount
        NSDecimalRound(&rounded, &value, 2, .plain)
        return rounded
    }

    private static func formatAmount(_ amount: Decimal?) -> String {
        guard let amount else { return "" }

        let rounded = roundedToKopecks(amount)

        // Додаток 4, п. 4.8: дрібна частина або відсутня повністю (краще "UAH3",
        // ніж "UAH3.00"), або складається рівно з двох цифр. Тобто кінцевий нуль
        // можна зрізати лише разом з усією дрібною частиною: "UAH100.5" неприпустиме,
        // тоді як і "UAH100", і "UAH100.50" — коректні.
        var scaled = rounded * 100
        var scaledRounded = Decimal()
        NSDecimalRound(&scaledRounded, &scaled, 0, .plain)
        let cents = NSDecimalNumber(decimal: scaledRounded).intValue

        let major = cents / 100
        let minor = cents % 100
        let formatted = minor == 0 ? String(major) : String(major) + "." + String(format: "%02d", minor)

        return currencyCode + formatted
    }

    /// Формат "РРММДДГГХХСС" (рік-місяць-день-година-хвилина-секунда), кожна
    /// пара — 2 цифри.
    private static func formatDateTime(_ date: Date?) -> String {
        guard let date else { return "" }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        func pad2(_ value: Int?) -> String {
            String(format: "%02d", (value ?? 0))
        }

        let year = (c.year ?? 0) % 100
        return pad2(year) + pad2(c.month) + pad2(c.day) + pad2(c.hour) + pad2(c.minute) + pad2(c.second)
    }

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }
}
