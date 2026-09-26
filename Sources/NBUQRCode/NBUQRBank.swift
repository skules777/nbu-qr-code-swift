import Foundation

/// Банк зі своїм персоніфікованим "кодом старту застосунку" (додаток 4,
/// таблиця 1, рядок 1; п. 2 пп. 1): посилання з таким кодом старту застосунку відкриває
/// платіж напряму в застосунку цього банку замість узагальненого
/// `https://qr.bank.gov.ua/`.
///
/// Це struct, а не enum, щоб новий банк у бібліотеці не ламав клієнтський `switch`,
/// а банк, якого тут немає, можна було описати самому через `init(name:appStartURL:)`.
public struct NBUQRBank: Hashable, Sendable {
    /// Назва для кнопки "Оплатити через ...".
    public let name: String
    /// Персоніфікований "код старту застосунку" — адреса, до якої дописується
    /// закодований платіж: https-адреса банку (`https://www.privat24.ua/rd/send_qr/nbu/`)
    /// або власна схема застосунку (`abank24://bank.gov.ua/qr/`). Якщо адреса
    /// закінчується на `/` чи `=` (параметр запиту, як `?payload=`), платіж
    /// дописується як є, інакше між ними додається `/`.
    public let appStartURL: URL

    /// Описує банк, якого немає серед вбудованих.
    ///
    /// - Parameters:
    ///   - name: Назва для кнопки "Оплатити через ...".
    ///   - appStartURL: Персоніфікований код старту застосунку банку.
    public init(name: String, appStartURL: URL) {
        self.name = name
        self.appStartURL = appStartURL
    }

    /// Deep link перевірено оплатою на пристрої.
    public static let privatBank = NBUQRBank(name: "Приват24", appStartURL: URL(string: "https://www.privat24.ua/rd/send_qr/nbu/")!)
    /// Deep link перевірено оплатою на пристрої.
    public static let monobank = NBUQRBank(name: "monobank", appStartURL: URL(string: "https://mbnk.app/qr/")!)
    /// Deep link з форматом 003 не перевірено — на розсуд клієнта.
    public static let privat24Business = NBUQRBank(name: "Privat24 for business", appStartURL: URL(string: "p24business://bank.gov.ua/qr/")!)
    /// Deep link з форматом 003 не перевірено — на розсуд клієнта.
    public static let abank = NBUQRBank(name: "Абанк", appStartURL: URL(string: "abank24://bank.gov.ua/qr/")!)
    /// Deep link з форматом 003 не перевірено — на розсуд клієнта.
    public static let pumb = NBUQRBank(name: "ПУМБ", appStartURL: URL(string: "https://mobile-app.pumb.ua/bank.gov.ua/qr/")!)
    /// Deep link з форматом 003 не перевірено — на розсуд клієнта.
    public static let raiffeisen = NBUQRBank(name: "Райффайзен Банк", appStartURL: URL(string: "https://my-raif.apps.raiffeisen.ua/qr?payload=")!)
    /// Deep link з форматом 003 не перевірено — на розсуд клієнта.
    public static let ukrsibbank = NBUQRBank(name: "UKRSIBBANK", appStartURL: URL(string: "com.ukrsibbank.ukrsibonline.new://bank.gov.ua/qr/")!)
    /// Deep link з форматом 003 не перевірено — на розсуд клієнта.
    public static let ukrgasbank = NBUQRBank(name: "Укргазбанк", appStartURL: URL(string: "ecobank://bank.gov.ua/qr/")!)
    /// Deep link з форматом 003 не перевірено — на розсуд клієнта.
    public static let otpBank = NBUQRBank(name: "ОТП БАНК", appStartURL: URL(string: "otpbankua://payment/qr/")!)
    /// Deep link з форматом 003 не перевірено — на розсуд клієнта.
    public static let creditAgricole = NBUQRBank(name: "Креді Агріколь Банк", appStartURL: URL(string: "https://caplusapp.credit-agricole.ua/qr/")!)
    /// Deep link з форматом 003 не перевірено — на розсуд клієнта.
    public static let radabank = NBUQRBank(name: "РАДАБАНК", appStartURL: URL(string: "https://radabank.com.ua/qr_code/")!)
    /// Deep link з форматом 003 не перевірено — на розсуд клієнта.
    public static let vstBank = NBUQRBank(name: "VST BANK", appStartURL: URL(string: "vostok://bank.gov.ua/qr/")!)

    /// Усі вбудовані банки. Deep link перевірено оплатою лише для Приват24 і
    /// monobank; решту надано як є, на розсуд клієнта (README, "Банки").
    /// Список поповнюється в мінорних версіях бібліотеки, тож кому потрібен
    /// фіксований набір кнопок, збирає його сам, напр. `[.privatBank, .monobank]`.
    public static let all: [NBUQRBank] = [
        .privatBank, .monobank, .privat24Business, .abank, .pumb, .raiffeisen,
        .ukrsibbank, .ukrgasbank, .otpBank, .creditAgricole, .radabank, .vstBank,
    ]
}
