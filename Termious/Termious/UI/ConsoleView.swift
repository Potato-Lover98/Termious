import UIKit

public protocol ConsoleViewDelegate: AnyObject {
    func consoleViewDidScrollToBottom(_ view: ConsoleView)
}

/// A scrollable, append-only text console that renders output and prompts with
/// optional ANSI color escape handling (a small subset: 30-37, reset, green, red).
public final class ConsoleView: UIScrollView {
    private let textView = UITextView()
    private let attributedText = NSMutableAttributedString()
    private var lineHeight: CGFloat { Theme.font.lineHeight }

    public weak var delegate2: ConsoleViewDelegate?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        backgroundColor = Theme.background
        showsVerticalScrollIndicator = true
        alwaysBounceVertical = true

        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.font = Theme.font
        textView.textColor = Theme.foreground
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.textContainer.lineFragmentPadding = 0
        addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: contentArea.topAnchor),
            textView.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: contentArea.bottomAnchor),
            textView.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor)
        ])
    }

    public func appendOutput(_ text: String, color: UIColor) {
        let parsed = parseANSI(text, baseColor: color)
        attributedText.append(parsed)
        textView.attributedText = attributedText
        scrollToBottom()
    }

    public func appendPrompt(_ text: String) {
        let attr = NSAttributedString(string: text, attributes: [
            .font: Theme.font,
            .foregroundColor: Theme.prompt
        ])
        attributedText.append(attr)
        textView.attributedText = attributedText
        scrollToBottom()
    }

    public func applyTheme() {
        backgroundColor = Theme.background
        textView.backgroundColor = .clear
        textView.textColor = Theme.foreground
    }

    public func clear() {
        attributedText.deleteCharacters(in: NSRange(location: 0, length: attributedText.length))
        textView.attributedText = nil
    }

    private func scrollToBottom() {
        layoutIfNeeded()
        let bottom = max(0, contentSize.height - bounds.height)
        setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
        delegate2?.consoleViewDidScrollToBottom(self)
    }

    // MARK: - Minimal ANSI parser

    private func parseANSI(_ text: String, baseColor: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var current = ""
        var color = baseColor
        let chars = Array(text)
        var i = 0

        func flush() {
            if !current.isEmpty {
                result.append(NSAttributedString(string: current, attributes: [
                    .font: Theme.font, .foregroundColor: color
                ]))
                current.removeAll()
            }
        }

        while i < chars.count {
            let c = chars[i]
            if c == "\u{001B}", i + 1 < chars.count, chars[i + 1] == "[" {
                flush()
                // Find 'm'
                var j = i + 2
                var codeStr = ""
                while j < chars.count, chars[j] != "m" {
                    codeStr.append(chars[j])
                    j += 1
                }
                let codes = codeStr.split(separator: ";").compactMap { Int($0) }
                for code in codes {
                    switch code {
                    case 0: color = baseColor
                    case 31: color = Theme.error
                    case 32: color = Theme.prompt
                    case 33: color = Theme.accent
                    case 34: color = Theme.accent
                    case 35: color = Theme.accent
                    case 36: color = Theme.prompt
                    case 37: color = Theme.foreground
                    default: break
                    }
                }
                i = j + 1
                continue
            }
            // Also handle OSC sequence for OPEN_PICKER: ESC ] ... BEL
            if c == "\u{001B}", i + 1 < chars.count, chars[i + 1] == "]" {
                flush()
                var j = i + 2
                while j < chars.count, chars[j] != "\u{0007}" { j += 1 }
                i = j + 1
                continue
            }
            // Drop standalone EOT marker
            if c == "\u{0004}" {
                flush()
                i += 1
                continue
            }
            current.append(c)
            i += 1
        }
        flush()
        return result
    }
}