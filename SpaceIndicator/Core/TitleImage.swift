import AppKit

enum TitleImage {
    /// Renders `title` with tabular-digit system font as a template image, because
    /// the SwiftUI MenuBarExtra label ignores font modifiers.
    static func make(_ title: String) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let text = NSAttributedString(string: title, attributes: attributes)
        let size = text.size()
        let image = NSImage(size: NSSize(width: ceil(size.width), height: ceil(size.height)), flipped: false) { _ in
            text.draw(at: .zero)
            return true
        }
        image.isTemplate = true
        // VoiceOver reads this from the status button even if the SwiftUI label's isn't passed on.
        image.accessibilityDescription = title
        return image
    }
}
