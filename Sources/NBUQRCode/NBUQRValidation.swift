import Foundation

/// Поле платежу, до якого належить `NBUQRValidationIssue`.
public enum NBUQRField: CaseIterable, Sendable {
    /// Поле 6 — Отримувач.
    case recipient
    /// Поле 7 — Рахунок отримувача.
    case iban
    /// Поле 8 — Сума.
    case amount
    /// Поле 9 — Код отримувача.
    case recipientCode
    /// Поле 10 — Категорія / ціль.
    case category
    /// Поле 11 — Reference.
    case reference
    /// Поле 12 — Призначення платежу.
    case purpose
    /// Поле 13 — Відображення (дисплей).
    case displayText
}

/// Одна причина, з якої `NBUQRPayment` не можна закодувати.
public struct NBUQRValidationIssue: Hashable, Sendable, CustomStringConvertible {
    /// Одиниця ліміту довжини: таблиця 2 задає частину полів у символах, частину — в байтах.
    public enum LengthUnit: Hashable, Sendable {
        /// Символи.
        case characters
        /// Байти в обраному кодуванні.
        case bytes
    }

    /// Що саме не так зі значенням поля.
    public enum Problem: Hashable, Sendable {
        /// Обов'язкове поле порожнє.
        case missing
        /// Значення довше за ліміт таблиці 2.
        case tooLong(max: Int, unit: LengthUnit)
        /// Не та форма: IBAN не `UA` + 27 цифр, категорія не `CCCC/PPPP`.
        case invalidFormat
        /// Контрольна сума IBAN (ISO 7064 MOD 97-10) не сходиться.
        case invalidChecksum
        /// Сума поза межами 0…999999999.99.
        case outOfRange
        /// Символи поза набором поля: Windows-1251 для полів "*", ISO 646 для полів "А".
        case unsupportedCharacters
        /// Керуючі символи, DEL чи NBSP (додаток 1, п. 4).
        case forbiddenCharacters
    }

    /// Поле, до якого належить проблема — щоб підсвітити його у формі.
    public let field: NBUQRField
    /// Що не так зі значенням.
    public let problem: Problem

    /// Створює проблему, напр. щоб порівняти з результатом ``NBUQRPayment/validate()``.
    public init(field: NBUQRField, problem: Problem) {
        self.field = field
        self.problem = problem
    }

    public var description: String {
        switch problem {
        case .missing:
            return "\(field) is required"
        case .tooLong(let max, let unit):
            return "\(field) is too long (max \(max) \(unit == .bytes ? "bytes" : "characters"))"
        case .invalidFormat:
            return "\(field) has an invalid format"
        case .invalidChecksum:
            return "\(field) has an invalid checksum"
        case .outOfRange:
            return "\(field) is out of the allowed range"
        case .unsupportedCharacters:
            return "\(field) contains characters outside the set allowed by the standard"
        case .forbiddenCharacters:
            return "\(field) contains a character forbidden by the standard (control character, DEL or NBSP)"
        }
    }
}

extension NBUQRPayment {
    /// Усі причини, з яких платіж не можна закодувати; порожній список означає,
    /// що `NBUQRPayload(_:)` завершиться успіхом. Обсяг даних для графічного
    /// QR-коду тут не перевіряється — він залежить від підсумкового розміру,
    /// тому перевіряється в `NBUQRPayload.qrURL()`.
    public func validate() -> [NBUQRValidationIssue] {
        var issues: [NBUQRValidationIssue] = []
        func report(_ field: NBUQRField, _ problem: NBUQRValidationIssue.Problem) {
            issues.append(NBUQRValidationIssue(field: field, problem: problem))
        }

        if recipient.isEmpty {
            report(.recipient, .missing)
        } else if recipient.count > 140 {
            report(.recipient, .tooLong(max: 140, unit: .characters))
        }

        let iban = normalizedIBAN
        if iban.isEmpty {
            report(.iban, .missing)
        } else if !Self.hasUkrainianIBANShape(iban) {
            report(.iban, .invalidFormat)
        } else if Self.iso7064Mod97(iban) != 1 {
            report(.iban, .invalidChecksum)
        }

        // Діапазон перевіряється на значенні, яке піде в кодування: літерал з плаваючою
        // крапкою на кшталт `999999999.99` потрапляє в Decimal через Double як
        // 999999999.990000009… і інакше не пройшов би перевірку на власному максимумі.
        if let amount, amount < 0 || NBUQRFormat.roundedToKopecks(amount) > NBUQRFormat.maxAmount {
            report(.amount, .outOfRange)
        }

        if recipientCode.isEmpty {
            report(.recipientCode, .missing)
        } else if let byteCount = recipientCode.data(using: encoding.stringEncoding)?.count,
                  // Довжину поля 9 таблиця 2 (додаток 4) задає в *байтах*, на відміну від
                  // символьних лімітів вище, — і, на відміну від них, це поле "*" (може
                  // містити текст у Windows-1251/UTF-8), тож кількість байтів і символів тут
                  // справді може різнитися (10 кириличних символів у UTF-8 — це 20 байтів).
                  byteCount > 10 {
            report(.recipientCode, .tooLong(max: 10, unit: .bytes))
        }

        if !category.isEmpty && !Self.hasCategoryShape(category) {
            report(.category, .invalidFormat)
        }

        if reference.count > 35 {
            report(.reference, .tooLong(max: 35, unit: .characters))
        }
        // Поля з кодуванням "А" в таблиці 2 — тільки ISO 646. IBAN і категорія
        // вже перевірені суворіше вище, маску будує сама бібліотека, тож
        // лишається `reference`.
        if !reference.allSatisfy(\.isASCII) {
            report(.reference, .unsupportedCharacters)
        }

        if purpose.isEmpty {
            report(.purpose, .missing)
        } else if purpose.count > 420 {
            report(.purpose, .tooLong(max: 420, unit: .characters))
        }

        if displayText.count > 140 {
            report(.displayText, .tooLong(max: 140, unit: .characters))
        }

        // Додаток 1, п. 4 задає набір символів через Windows-1251 для обох
        // кодувань: у UTF-8 дозволені лише "еквіваленти цих символів". Тобто
        // UTF-8 змінює спосіб запису, а не розширює набір — емодзі чи ієрогліфи
        // заборонені й там. Перевірка кодованості саме в Windows-1251 заодно
        // гарантує, що кодування в обраному форматі не впаде: будь-який символ
        // Windows-1251 кодується і в UTF-8.
        let encodedTextFields: [(NBUQRField, String)] = [
            (.recipient, recipient), (.recipientCode, recipientCode),
            (.purpose, purpose), (.displayText, displayText),
        ]
        for (field, value) in encodedTextFields where value.data(using: .windowsCP1251) == nil {
            report(field, .unsupportedCharacters)
        }

        let forbiddenCharacterFields: [(NBUQRField, String)] = [
            (.recipient, recipient), (.iban, iban), (.recipientCode, recipientCode),
            (.category, category), (.reference, reference), (.purpose, purpose),
            (.displayText, displayText),
        ]
        for (field, value) in forbiddenCharacterFields where Self.containsForbiddenCharacter(value) {
            report(field, .forbiddenCharacters)
        }

        return issues
    }

    // Саме ASCII-цифри, а не `isNumber`: той приймає й арабсько-індійські, повноширинні
    // та інші Unicode-цифри, які дійшли б до `iso7064Mod97` як символи без ваги — і
    // однаково були б відхилені ASCII-енкодером пізніше.
    // Відкидаються лише пробільні роздільники (пробіл, NBSP, вузький NBSP…): виписки
    // й банківські застосунки групують ними цифри IBAN, тож вони потрапляють у
    // скопійований рахунок. Переноси рядків і табуляції лишаються й репортуються як
    // заборонені символи.
    var normalizedIBAN: String {
        String(String.UnicodeScalarView(iban.unicodeScalars.filter {
            $0.properties.generalCategory != .spaceSeparator
        }))
    }

    private static func hasUkrainianIBANShape(_ iban: String) -> Bool {
        guard iban.hasPrefix("UA"), iban.count == 29 else { return false }
        return iban.dropFirst(2).allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Контрольна сума IBAN за ISO 7064 MOD 97-10 (ISO 13616): для валідного
    /// рахунку залишок дорівнює 1. Без цієї перевірки будь-які 27 цифр після "UA"
    /// вважались би рахунком, а помилку в реквізитах платник побачив би вже у
    /// банківському застосунку.
    static func iso7064Mod97(_ iban: String) -> Int {
        var remainder = 0
        // ISO 13616: перші чотири символи переносяться в кінець, літери важать
        // A = 10 ... Z = 35, тобто дають два десяткові розряди замість одного.
        for character in iban.dropFirst(4) + iban.prefix(4) {
            guard let ascii = character.asciiValue else { return -1 }
            switch ascii {
            case 0x30...0x39:
                remainder = (remainder * 10 + Int(ascii - 0x30)) % 97
            case 0x41...0x5A:
                remainder = (remainder * 100 + Int(ascii - 0x41) + 10) % 97
            default:
                return -1
            }
        }
        return remainder
    }

    // Перевіряється лише форма, а не самі коди: НБУ не публікує переліку допустимих
    // значень CCCC/PPPP, тож відхиляти незнайомий код означало б блокувати платежі,
    // які банки приймають. Порожнє поле 10 валідне, його обробляє викликач.
    private static func hasCategoryShape(_ category: String) -> Bool {
        let parts = category.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        return parts.allSatisfy { part in
            part.count == 4 && part.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber) }
        }
    }

    // Додаток 1, п. 4: елемент даних може містити символи від 32 до 255, крім 127
    // (DEL), 152 і 160 (NBSP) — у Windows-1251 чи еквіваленті в UTF-8; DEL і NBSP
    // мають однакові кодові точки Unicode незалежно від кодування.
    //
    // Нижня межа (усе до 32) важить не менше за іменовані винятки: LF (0x0A) у цьому
    // форматі є роздільником полів, тож неперевірений перенос рядка всередині тексту
    // не псує саме значення, а зсуває решту структури на одне поле — призначення
    // платежу потрапляє у "Відображення", маска — в дату тощо. Реквізити при цьому
    // лишаються валідними на вигляд, але поїдуть мовчки, тому такий текст
    // відхиляється тут.
    //
    // Третій заборонений байт, 152 (0x98) у Windows-1251, окремої перевірки не
    // потребує: жоден символ Unicode на нього не мапиться через стандартний енкодер,
    // тобто рядок, який успішно закодується, фізично не може містити цей байт.
    private static func containsForbiddenCharacter(_ value: String) -> Bool {
        value.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F || $0.value == 0xA0 }
    }
}
