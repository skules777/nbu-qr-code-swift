# ``NBUQRCodeImage``

Зображення QR-коду НБУ зі знаком ₴ за вимогами додатку 1 Постанови №97.

## Огляд

``NBUQRImageRenderer`` рендерить закодований платіж (`NBUQRPayload` з модуля
`NBUQRCode`) у `CGImage` чи PNG. Рендер сам підбирає рівень корекції й версію
QR-коду в межах 10–17, малює по центру біле коло зі знаком ₴ і, за бажанням,
фарбує акцентом знак і центри шукових візерунків. Лише CoreImage і
CoreGraphics — без UIKit/AppKit і без залежності від шрифтів.

```swift
let renderer = NBUQRImageRenderer(accentColor: .nbuGreen)
let png = try renderer.pngData(for: payload)
let cgImage = try renderer.cgImage(for: payload)
```

У зображення завжди кодується посилання з `qr.bank.gov.ua`: QR-код з кодом
старту застосунку конкретного банку читає лише сканер цього банку.

## Topics

### Рендер

- ``NBUQRImageRenderer``
- ``NBUQRErrorCorrection``
- ``NBUQRErrorCorrectionLevel``
- ``NBUQRColor``

### Помилки

- ``NBUQRImageError``
