# ``NBUQRCode``

Платіжні QR-коди НБУ формату 003: опис платежу, валідація та посилання.

## Огляд

Модуль формує вміст QR-коду для переказів за IBAN згідно з Постановою НБУ
№97. Опишіть платіж у ``NBUQRPayment``, перевірте його через
``NBUQRPayment/validate()`` і закодуйте в ``NBUQRPayload``. З одного
закодованого вмісту беруться і посилання для QR-коду
(``NBUQRPayload/qrURL()``), і deep link у застосунок банку
(``NBUQRPayload/deepLink(for:)``).

```swift
let payment = NBUQRPayment(
    recipient: "ТОВ «Приклад»",
    iban: "UA213223130000026007233566001",
    amount: 150,
    recipientCode: "12345678",
    purpose: "Оплата замовлення №42"
)

let payload = try NBUQRPayload(payment)
let qrURL = try payload.qrURL()
let privat24 = payload.deepLink(for: .privatBank)
```

Зображення QR-коду зі знаком ₴ рендерить модуль `NBUQRCodeImage`.

Підтримку банків описано в
[README](https://github.com/skules777/nbu-qr-code-swift#банки), а
те, як бібліотека виконує вимоги Постанови, — у
[docs/NBU-COMPLIANCE.md](https://github.com/skules777/nbu-qr-code-swift/blob/main/docs/NBU-COMPLIANCE.md).

## Topics

### Платіж

- ``NBUQRPayment``
- ``NBUQRPaymentFunction``
- ``NBUQRTextEncoding``
- ``NBUQREditableField``

### Валідація

- ``NBUQRValidationIssue``
- ``NBUQRField``

### Кодування й посилання

- ``NBUQRPayload``
- ``NBUQRBank``

### Помилки

- ``NBUQRError``
