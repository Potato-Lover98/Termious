import UIKit

enum Theme {
    static var background = UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1.0)
    static var foreground = UIColor(red: 0.88, green: 0.90, blue: 0.92, alpha: 1.0)
    static var prompt     = UIColor(red: 0.30, green: 0.85, blue: 0.55, alpha: 1.0)
    static var accent     = UIColor(red: 0.40, green: 0.66, blue: 0.95, alpha: 1.0)
    static var error      = UIColor(red: 0.95, green: 0.45, blue: 0.45, alpha: 1.0)
    static var dim        = UIColor(red: 0.55, green: 0.58, blue: 0.62, alpha: 1.0)
    static var selection  = UIColor(red: 0.20, green: 0.40, blue: 0.65, alpha: 0.6)

    static let fontName = "Menlo"
    static let fontSize: CGFloat = 14
    static var font: UIFont = UIFont(name: fontName, size: fontSize) ??
        UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

    static func apply(background: UIColor, foreground: UIColor, prompt: UIColor) {
        Theme.background = background
        Theme.foreground = foreground
        Theme.prompt = prompt
    }
}