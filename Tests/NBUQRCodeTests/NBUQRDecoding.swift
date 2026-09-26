import Foundation
@testable import NBUQRCode

// Розбір QR-посилання свідомо живе в тестах, а не в бібліотеці: завдання
// фреймворку — генерувати QR-код і платіжні посилання, а не обробляти
// відскановані чужі. Декодер — лише інструмент перевірки енкодера, тому й не
// зобовʼязаний захищатись від зловмисного вводу.

enum NBUQRDecodingError: Error, Equatable {
    case invalidURL
    case invalidDataStructure
}

/// Розібрана структура даних QR-коду версії формату 003 (17 полів таблиці 2 додатка 4).
struct NBUQRParsedData: Equatable, Sendable {
    let serviceTag: String
    let version: String
    let encoding: String
    let function: String
    let uniqueId: String
    let recipient: String
    let iban: String
    let amount: String
    let recipientCode: String
    let category: String
    let reference: String
    let purpose: String
    let displayText: String
    /// Сирий hex поля 14 — розкодуйте через `NBUQRLockMask.editableFields(fromHex:)`,
    /// якщо потрібні саме дозволені поля.
    let lockMask: String
    let validUntil: String
    let createdAt: String
    let signature: String
}

enum NBUQRDecoder {

    /// Розбирає посилання незалежно від коду старту застосунку — узагальненого
    /// `qr.bank.gov.ua` або будь-якого з `NBUQRBank.all`.
    static func parse(_ url: URL) throws -> NBUQRParsedData {
        let string = url.absoluteString
        let knownAppStartURLs = [NBUQRFormat.qrAppStartURL] + NBUQRBank.all.map(\.appStartURL.absoluteString)
        guard let matchedAppStartURL = knownAppStartURLs.first(where: string.hasPrefix) else {
            throw NBUQRDecodingError.invalidURL
        }
        return try parse(payload: String(string.dropFirst(matchedAppStartURL.count)))
    }

    /// Розбирає чистий Base64URL-вміст (без коду старту застосунку), тобто `NBUQRPayload.value`.
    static func parse(payload encoded: String) throws -> NBUQRParsedData {
        guard let decoded = base64URLDecode(encoded) else {
            throw NBUQRDecodingError.invalidDataStructure
        }

        let rawParts = splitByLineFeed(decoded)
        guard rawParts.count >= 17 else {
            throw NBUQRDecodingError.invalidDataStructure
        }

        let encodingTag = String(data: rawParts[2], encoding: .ascii) ?? ""
        let textEncoding: NBUQRTextEncoding = (encodingTag == NBUQRTextEncoding.utf8.rawValue) ? .utf8 : .windows1251

        func ascii(_ index: Int) -> String {
            String(data: rawParts[index], encoding: .ascii) ?? ""
        }

        func text(_ index: Int) -> String {
            String(data: rawParts[index], encoding: textEncoding.stringEncoding) ?? ""
        }

        return NBUQRParsedData(
            serviceTag: ascii(0),
            version: ascii(1),
            encoding: ascii(2),
            function: ascii(3),
            uniqueId: ascii(4),
            recipient: text(5),
            iban: ascii(6),
            amount: ascii(7),
            recipientCode: text(8),
            category: ascii(9),
            reference: ascii(10),
            purpose: text(11),
            displayText: text(12),
            lockMask: ascii(13),
            validUntil: ascii(14),
            createdAt: ascii(15),
            signature: ascii(16)
        )
    }

    // Явний перебір байтів замість `split(separator:)`: на новіших тулчейнах
    // перевантаження `split` з Collection і Sequence для `Data` неоднозначні.
    private static func splitByLineFeed(_ data: Data) -> [Data] {
        var parts: [Data] = []
        var start = data.startIndex
        var index = data.startIndex
        while index < data.endIndex {
            if data[index] == 0x0A {
                parts.append(data.subdata(in: start..<index))
                start = data.index(after: index)
            }
            index = data.index(after: index)
        }
        parts.append(data.subdata(in: start..<data.endIndex))
        return parts
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}

extension NBUQRLockMask {
    /// Біти полів 1–5, 11, 14 і 15, які п. 4.14 вимагає блокувати в кожній масці.
    /// Полям 16–17 потрібно те саме, але біта для них немає.
    static let alwaysLockedBits: UInt16 = 0b1100_1000_0011_1110

    /// Поле 14 — "число від 0 до FFFF (hex)" змінної довжини до 4 B (таблиця 2),
    /// тож "FF", "0" і "feff" у нижньому регістрі — усі валідні значення.
    static func parse(_ hex: String) -> UInt16? {
        // `isHexDigit` приймає й повноширинні цифри (U+FF10…), які не кодуються
        // в ISO 646, а сам `UInt16(_:radix:)` приймає знак "+".
        guard (1...4).contains(hex.count), hex.allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            return nil
        }
        return UInt16(hex, radix: 16)
    }

    /// Розкодовує сирий `lock_mask` у поля, які він дозволяє змінювати. Невідомі
    /// та RFU-біти ігноруються. Повертає `nil`, якщо `hex` не є hex-числом з 1–4 цифр.
    static func editableFields(fromHex hex: String) -> Set<NBUQREditableField>? {
        guard let mask = parse(hex) else { return nil }
        return Set(NBUQREditableField.allCases.filter { mask & $0.bit == 0 })
    }
}
