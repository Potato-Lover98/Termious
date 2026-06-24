import UIKit
import QuartzCore

/// Manages terminal background styles: 5 gradients, 5 solids, 5 animated.
/// Each style is rendered on a dedicated CALayer inserted behind the console.
public final class BackgroundManager {
    public static let shared = BackgroundManager()

    public enum StyleKind: String { case gradient, solid, animated, off }

    public struct Style: Equatable {
        public let name: String
        public let kind: StyleKind
        public let colors: [UIColor]
        public let description: String
    }

    public let styles: [Style] = [
        // 5 gradients
        Style(name: "ocean", kind: .gradient, colors: [
            UIColor(red: 0.01, green: 0.05, blue: 0.12, alpha: 1),
            UIColor(red: 0.02, green: 0.15, blue: 0.30, alpha: 1),
            UIColor(red: 0.01, green: 0.08, blue: 0.20, alpha: 1)
        ], description: "Deep ocean blue gradient"),
        Style(name: "sunset", kind: .gradient, colors: [
            UIColor(red: 0.25, green: 0.06, blue: 0.20, alpha: 1),
            UIColor(red: 0.50, green: 0.15, blue: 0.10, alpha: 1),
            UIColor(red: 0.15, green: 0.05, blue: 0.12, alpha: 1)
        ], description: "Warm sunset purple-orange"),
        Style(name: "forest", kind: .gradient, colors: [
            UIColor(red: 0.01, green: 0.08, blue: 0.03, alpha: 1),
            UIColor(red: 0.03, green: 0.18, blue: 0.06, alpha: 1),
            UIColor(red: 0.01, green: 0.06, blue: 0.02, alpha: 1)
        ], description: "Deep forest green gradient"),
        Style(name: "cosmic", kind: .gradient, colors: [
            UIColor(red: 0.06, green: 0.01, blue: 0.12, alpha: 1),
            UIColor(red: 0.15, green: 0.02, blue: 0.30, alpha: 1),
            UIColor(red: 0.03, green: 0.01, blue: 0.08, alpha: 1)
        ], description: "Cosmic purple gradient"),
        Style(name: "candy", kind: .gradient, colors: [
            UIColor(red: 0.95, green: 0.60, blue: 0.70, alpha: 1),
            UIColor(red: 0.70, green: 0.80, blue: 0.95, alpha: 1),
            UIColor(red: 0.85, green: 0.65, blue: 0.90, alpha: 1)
        ], description: "Candy pink-blue gradient"),

        // 5 solids
        Style(name: "noir", kind: .solid, colors: [
            UIColor(red: 0.02, green: 0.02, blue: 0.02, alpha: 1)
        ], description: "Pure black noir"),
        Style(name: "carbon", kind: .solid, colors: [
            UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)
        ], description: "Dark carbon grey"),
        Style(name: "midnight", kind: .solid, colors: [
            UIColor(red: 0.01, green: 0.02, blue: 0.06, alpha: 1)
        ], description: "Midnight navy"),
        Style(name: "ivory", kind: .solid, colors: [
            UIColor(red: 0.96, green: 0.95, blue: 0.92, alpha: 1)
        ], description: "Light ivory white"),
        Style(name: "matrix", kind: .solid, colors: [
            UIColor(red: 0.0, green: 0.06, blue: 0.0, alpha: 1)
        ], description: "Matrix black-green"),

        // 5 animated
        Style(name: "aurora", kind: .animated, colors: [
            UIColor(red: 0.02, green: 0.10, blue: 0.15, alpha: 1),
            UIColor(red: 0.05, green: 0.25, blue: 0.20, alpha: 1),
            UIColor(red: 0.10, green: 0.15, blue: 0.30, alpha: 1),
            UIColor(red: 0.02, green: 0.10, blue: 0.15, alpha: 1)
        ], description: "Animated aurora borealis"),
        Style(name: "lava", kind: .animated, colors: [
            UIColor(red: 0.10, green: 0.01, blue: 0.0, alpha: 1),
            UIColor(red: 0.35, green: 0.05, blue: 0.01, alpha: 1),
            UIColor(red: 0.50, green: 0.15, blue: 0.02, alpha: 1),
            UIColor(red: 0.10, green: 0.01, blue: 0.0, alpha: 1)
        ], description: "Animated flowing lava"),
        Style(name: "plasma", kind: .animated, colors: [
            UIColor(red: 0.12, green: 0.02, blue: 0.15, alpha: 1),
            UIColor(red: 0.20, green: 0.05, blue: 0.30, alpha: 1),
            UIColor(red: 0.05, green: 0.10, blue: 0.25, alpha: 1),
            UIColor(red: 0.12, green: 0.02, blue: 0.15, alpha: 1)
        ], description: "Animated plasma field"),
        Style(name: "rainbow", kind: .animated, colors: [
            UIColor(red: 0.50, green: 0.0, blue: 0.0, alpha: 1),
            UIColor(red: 0.50, green: 0.25, blue: 0.0, alpha: 1),
            UIColor(red: 0.0, green: 0.40, blue: 0.0, alpha: 1),
            UIColor(red: 0.0, green: 0.25, blue: 0.50, alpha: 1),
            UIColor(red: 0.30, green: 0.0, blue: 0.50, alpha: 1),
            UIColor(red: 0.50, green: 0.0, blue: 0.0, alpha: 1)
        ], description: "Animated rainbow shift"),
        Style(name: "digitalrain", kind: .animated, colors: [
            UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1),
            UIColor(red: 0.0, green: 0.08, blue: 0.0, alpha: 1),
            UIColor(red: 0.0, green: 0.15, blue: 0.02, alpha: 1),
            UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1)
        ], description: "Animated digital rain"),
    ]

    private(set) var currentStyleName: String? = nil
    private var bgLayer: CALayer? = nil
    private weak var container: UIView? = nil

    // MARK: - Apply

    public func attach(to view: UIView) {
        container = view
        loadSaved()
    }

    public func apply(_ name: String, to view: UIView) -> Bool {
        guard let style = styles.first(where: { $0.name == name }) else { return false }
        removeCurrent()
        currentStyleName = name
        save(name: name)

        let layer = makeLayer(for: style, frame: view.bounds)
        layer.name = "termious.bg"
        view.layer.insertSublayer(layer, at: 0)
        bgLayer = layer
        return true
    }

    public func clear() {
        removeCurrent()
        currentStyleName = nil
        save(name: nil)
    }

    public func resize(to size: CGRect) {
        bgLayer?.frame = size
        if let grad = bgLayer as? CAGradientLayer {
            grad.frame = size
        }
    }

    // MARK: - Layer creation

    private func makeLayer(for style: Style, frame: CGRect) -> CALayer {
        switch style.kind {
        case .solid:
            let l = CALayer()
            l.frame = frame
            l.backgroundColor = style.colors[0].cgColor
            return l
        case .gradient:
            let l = CAGradientLayer()
            l.frame = frame
            l.colors = style.colors.map { $0.cgColor }
            l.startPoint = CGPoint(x: 0, y: 0)
            l.endPoint = CGPoint(x: 0, y: 1)
            return l
        case .animated:
            let l = CAGradientLayer()
            l.frame = frame
            l.colors = style.colors.map { $0.cgColor }
            l.startPoint = CGPoint(x: 0, y: 0)
            l.endPoint = CGPoint(x: 1, y: 1)
            animateGradient(l, style: style)
            return l
        case .off:
            let l = CALayer()
            l.frame = frame
            l.backgroundColor = UIColor.clear.cgColor
            return l
        }
    }

    private func animateGradient(_ layer: CAGradientLayer, style: Style) {
        let anim = CABasicAnimation(keyPath: "colors")
        anim.fromValue = style.colors.map { $0.cgColor }
        // Reverse the color array for a smooth loop back
        var toColors = style.colors
        toColors.reverse()
        anim.toValue = toColors.map { $0.cgColor }
        anim.duration = style.name == "rainbow" ? 8.0 : 6.0
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.isRemovedOnCompletion = false
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        // Also animate the start/end points for a flowing effect
        let ptAnim = CABasicAnimation(keyPath: "startPoint")
        ptAnim.fromValue = CGPoint(x: 0, y: 0)
        ptAnim.toValue = CGPoint(x: 1, y: 1)
        ptAnim.duration = 10.0
        ptAnim.autoreverses = true
        ptAnim.repeatCount = .infinity
        ptAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        let ptAnim2 = CABasicAnimation(keyPath: "endPoint")
        ptAnim2.fromValue = CGPoint(x: 1, y: 1)
        ptAnim2.toValue = CGPoint(x: 0, y: 0)
        ptAnim2.duration = 10.0
        ptAnim2.autoreverses = true
        ptAnim2.repeatCount = .infinity
        ptAnim2.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        layer.add(anim, forKey: "colorsAnim")
        layer.add(ptAnim, forKey: "startAnim")
        layer.add(ptAnim2, forKey: "endAnim")
    }

    // MARK: - Cleanup

    private func removeCurrent() {
        bgLayer?.removeFromSuperlayer()
        bgLayer = nil
    }

    // MARK: - Persistence

    private let savedKey = "Termious.bg.style.v1"

    private func save(name: String?) {
        UserDefaults.standard.set(name, forKey: savedKey)
    }

    private func loadSaved() {
        guard let name = UserDefaults.standard.string(forKey: savedKey),
              let container = container else { return }
        _ = apply(name, to: container)
    }
}