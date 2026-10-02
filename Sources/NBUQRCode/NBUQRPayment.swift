import Foundation

/// Функція платежу згідно з Правилами НБУ (додаток 4, п. 4.4).
public enum NBUQRPaymentFunction: String, Sendable {
    /// Кредитовий переказ (Ukrainian Credit Transfer).
    case uct = "UCT"
    /// Миттєвий кредитовий переказ (Instant Credit Transfer).
    case ict = "ICT"
    /// Миттєвий або кредитовий переказ.
    case xct = "XCT"
}

/// Кодування кириличних полів структури даних QR-коду (додаток 4, п. 4.3).
public enum NBUQRTextEncoding: String, Sendable {
    /// UTF-8: кирилиця займає 2 байти, тож у QR-код вміщується майже вдвічі
    /// менше тексту.
    case utf8 = "1"
    /// Windows-1251 (за замовчуванням): 1 байт на символ — найкомпактніше, як і
    /// вимагає додаток 1, п. 3.
    case windows1251 = "2"

    var stringEncoding: String.Encoding {
        switch self {
        case .utf8: return .utf8
        case .windows1251: return .windowsCP1251
        }
    }
}

/// Дані для формування рахунку/платежу відповідно до таблиці 2 додатка 4
/// Правил формування, передачі та обробки структури даних і графічного
/// зображення QR-коду для здійснення кредитових та миттєвих кредитових
/// переказів (версія формату QR-коду 003).
///
/// Сама модель нічого не гарантує — перевірку робить `validate()`, а
/// `NBUQRPayload(_:)` приймає лише платіж, що її пройшов.
public struct NBUQRPayment: Hashable, Sendable {
    /// Функція платежу (поле 4). За замовчуванням ``NBUQRPaymentFunction/ict``.
    public var function: NBUQRPaymentFunction
    /// Кодування полів "*" (поле 3). За замовчуванням ``NBUQRTextEncoding/windows1251``.
    public var encoding: NBUQRTextEncoding
    /// Прізвище, ім'я, по батькові або найменування отримувача (поле 6, до 140 символів).
    public var recipient: String
    /// IBAN отримувача, напр. "UA123456789012345678901234567" (поле 7, рівно 29
    /// символів; пробіли, якими IBAN групують у виписках, ігноруються).
    public var iban: String
    /// Сума платежу; nil = сума заповнюється платником (поле 8).
    public var amount: Decimal?
    /// Код отримувача коштів (поле 9, до 10 байтів в обраному кодуванні).
    public var recipientCode: String
    /// Код категорії/цілі у форматі CCCC/PPPP за ISO 20022 (поле 10). Порожнє значення
    /// в QR-код потрапляє як `OTHR/OTHR` ("інше / інше"): поле 10 обовʼязкове, і Приват24
    /// код із порожнім полем відхиляє.
    public var category: String
    /// Ідентифікатор рахунку на оплату отримувача (поле 11, до 35 символів ASCII).
    public var reference: String
    /// Призначення платежу (поле 12, до 420 символів).
    public var purpose: String
    /// Додатковий текст для відображення (поле 13, до 140 символів).
    public var displayText: String
    /// Поля, які платник може змінити у своєму застосунку (поле 14, "Код заборони
    /// зміни полів"). `nil` лишає поле 14 порожнім — обмеження не встановлюється;
    /// порожня множина блокує все, що стандарт дозволяє блокувати.
    public var editableFields: Set<NBUQREditableField>?
    /// Дата/час дії рахунку на оплату (поле 15).
    public var validUntil: Date?
    /// Дата/час формування рахунку на оплату (поле 16).
    public var createdAt: Date?

    /// Створює платіж; параметри відповідають однойменним властивостям.
    ///
    /// Значення тут не перевіряються — для цього є ``validate()``, а
    /// ``NBUQRPayload/init(_:)`` приймає лише платіж, що її пройшов.
    public init(
        function: NBUQRPaymentFunction = .ict,
        encoding: NBUQRTextEncoding = .windows1251,
        recipient: String,
        iban: String,
        amount: Decimal? = nil,
        recipientCode: String,
        category: String = "",
        reference: String = "",
        purpose: String,
        displayText: String = "",
        editableFields: Set<NBUQREditableField>? = nil,
        validUntil: Date? = nil,
        createdAt: Date? = nil
    ) {
        self.function = function
        self.encoding = encoding
        self.recipient = recipient
        self.iban = iban
        self.amount = amount
        self.recipientCode = recipientCode
        self.category = category
        self.reference = reference
        self.purpose = purpose
        self.displayText = displayText
        self.editableFields = editableFields
        self.validUntil = validUntil
        self.createdAt = createdAt
    }
}
