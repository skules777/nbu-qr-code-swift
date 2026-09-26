import Foundation

/// Помилки формування платежу. `description` — англійською, для логів і
/// розробника; користувачу показуйте власний текст за кейсом (для
/// `invalidPayment` — за `field` і `problem` кожної проблеми).
public enum NBUQRError: Error, Equatable, LocalizedError, CustomStringConvertible {
    /// Платіж не пройшов `NBUQRPayment.validate()`.
    case invalidPayment([NBUQRValidationIssue])
    /// Base64URL-вміст довший, ніж дозволяють ліміти обсягу даних графічного
    /// QR-коду (таблиця 1 і п. 8 додатка 4). На посилання в застосунок банку не впливає.
    case qrDataTooLong(actual: Int, max: Int)

    public var errorDescription: String? { description }

    public var description: String {
        switch self {
        case .invalidPayment(let issues):
            return "Invalid payment: " + issues.map(\.description).joined(separator: ", ")
        case .qrDataTooLong(let actual, let max):
            return "Encoded payment data (\(actual) bytes) exceeds the QR code maximum of \(max) bytes"
        }
    }
}
