import UIKit
import QuartzCore

/// `tineo` - a built-in text editor with syntax highlighting.
/// Usage: tineo <file>          Open file for editing
///        tineo -n <file>        New file
struct TineoCommand: BuiltinCommand {
    let name = "tineo"
    let summary = "Edit files with syntax highlighting"
    let usage = "tineo [-n] <file>"
    var operands: [Operand] {[
        Operand(name: "file", description: "File to edit or create (with -n)", required: true, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var newFile = false
        var path: String? = nil
        for a in arguments {
            if a == "-n" { newFile = true }
            else if !a.hasPrefix("-") { path = a }
        }
        guard let file = path else {
            context.stderr("tineo: missing file\n"); return 1
        }
        // Check if file exists (unless -n)
        if !newFile {
            guard let url = context.fs.resolve(file) else {
                context.stderr("tineo: cannot resolve '\(file)'\n"); return 1
            }
            let started = context.fs.startRootAccess()
            let exists = FileManager.default.fileExists(atPath: url.path)
            if started { context.fs.stopRootAccess() }
            if !exists {
                context.stderr("tineo: '\(file)' does not exist (use -n to create)\n")
                return 1
            }
        }
        // Emit signal with file path for UI to present editor
        context.stdout("\u{001B}]TINEO_EDIT\u{0007}\(newFile ? "NEW:" : "EDIT:")\(file)\u{0007}")
        return 0
    }
}

// MARK: - Syntax Highlighter

enum SyntaxHighlighter {
    static let keywords: Set<String> = [
        "func", "let", "var", "if", "else", "for", "while", "return", "switch",
        "case", "break", "continue", "struct", "class", "enum", "protocol",
        "extension", "import", "guard", "defer", "do", "try", "catch", "throw",
        "throws", "in", "where", "as", "is", "self", "super", "init", "deinit",
        "public", "private", "internal", "fileprivate", "open", "static",
        "final", "lazy", "weak", "unowned", "optional", "required", "override",
        "mutating", "nonmutating", "convenience", "dynamic", "indirect",
        "true", "false", "nil", "Int", "String", "Double", "Float", "Bool",
        "Array", "Dictionary", "Set", "Data", "URL", "Date", "Void",
        "if", "elif", "else", "then", "fi", "for", "while", "do", "done",
        "case", "esac", "function", "return", "local", "export", "readonly",
        "echo", "printf", "read", "source", "alias", "unalias", "unset"
    ]

    static func highlight(_ text: String, font: UIFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let lines = text.components(separatedBy: "\n")

        for (lineIdx, line) in lines.enumerated() {
            let highlighted = highlightLine(line, font: font)
            result.append(highlighted)
            if lineIdx < lines.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: [
                    .font: font, .foregroundColor: UIColor.white
                ]))
            }
        }
        return result
    }

    private static func highlightLine(_ line: String, font: UIFont) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let chars = Array(line)
        var i = 0
        var current = ""

        func appendWord(_ word: String) {
            if word.isEmpty { return }
            let color: UIColor
            if keywords.contains(word) { color = UIColor(red: 1.0, green: 0.35, blue: 0.50, alpha: 1) }
            else if word.hasPrefix("//") || word.hasPrefix("#") { color = UIColor(red: 0.45, green: 0.55, blue: 0.50, alpha: 1) }
            else if word.first == "\"" || word.first == "'" { color = UIColor(red: 0.75, green: 0.85, blue: 0.45, alpha: 1) }
            else if let _ = Int(word) { color = UIColor(red: 0.70, green: 0.50, blue: 0.90, alpha: 1) }
            else if word.allSatisfy({ $0 == "_" || $0.isLetter }) && (word.first?.isUppercase ?? false) {
                color = UIColor(red: 0.50, green: 0.80, blue: 1.0, alpha: 1)
            } else {
                color = UIColor(red: 0.88, green: 0.90, blue: 0.92, alpha: 1)
            }
            result.append(NSAttributedString(string: word, attributes: [
                .font: font, .foregroundColor: color
            ]))
        }

        // Check for comment lines first
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") || trimmed.hasPrefix("#") {
            result.append(NSAttributedString(string: line, attributes: [
                .font: font, .foregroundColor: UIColor(red: 0.45, green: 0.55, blue: 0.50, alpha: 1)
            ]))
            return result
        }

        while i < chars.count {
            let c = chars[i]

            // String literals
            if c == "\"" || c == "'" {
                var str = String(c); i += 1
                while i < chars.count && chars[i] != c {
                    if chars[i] == "\\" && i + 1 < chars.count {
                        str.append(chars[i]); str.append(chars[i + 1]); i += 2
                    } else {
                        str.append(chars[i]); i += 1
                    }
                }
                if i < chars.count { str.append(chars[i]); i += 1 }
                result.append(NSAttributedString(string: str, attributes: [
                    .font: font, .foregroundColor: UIColor(red: 0.75, green: 0.85, blue: 0.45, alpha: 1)
                ]))
                continue
            }

            // Line comment
            if c == "/" && i + 1 < chars.count && chars[i + 1] == "/" {
                let rest = String(chars[i...])
                result.append(NSAttributedString(string: rest, attributes: [
                    .font: font, .foregroundColor: UIColor(red: 0.45, green: 0.55, blue: 0.50, alpha: 1)
                ]))
                i = chars.count
                continue
            }

            // Numbers
            if c.isNumber {
                var num = ""
                while i < chars.count && (chars[i].isNumber || chars[i] == "." || chars[i] == "x" || chars[i].isHexDigit) {
                    num.append(chars[i]); i += 1
                }
                result.append(NSAttributedString(string: num, attributes: [
                    .font: font, .foregroundColor: UIColor(red: 0.70, green: 0.50, blue: 0.90, alpha: 1)
                ]))
                continue
            }

            // Identifiers / keywords
            if c.isLetter || c == "_" {
                var word = ""
                while i < chars.count && (chars[i].isLetter || chars[i] == "_" || chars[i].isNumber) {
                    word.append(chars[i]); i += 1
                }
                let color: UIColor
                if keywords.contains(word) {
                    color = UIColor(red: 1.0, green: 0.35, blue: 0.50, alpha: 1)
                } else if word.first?.isUppercase == true {
                    color = UIColor(red: 0.50, green: 0.80, blue: 1.0, alpha: 1)
                } else {
                    color = UIColor(red: 0.88, green: 0.90, blue: 0.92, alpha: 1)
                }
                result.append(NSAttributedString(string: word, attributes: [
                    .font: font, .foregroundColor: color
                ]))
                continue
            }

            // Operators and punctuation
            if "+-*/=<>!&|^%~?:;,.(){}[]".contains(c) {
                result.append(NSAttributedString(string: String(c), attributes: [
                    .font: font, .foregroundColor: UIColor(red: 0.90, green: 0.55, blue: 0.30, alpha: 1)
                ]))
                i += 1
                continue
            }

            // Default
            result.append(NSAttributedString(string: String(c), attributes: [
                .font: font, .foregroundColor: UIColor(red: 0.88, green: 0.90, blue: 0.92, alpha: 1)
            ]))
            i += 1
        }
        return result
    }
}

// MARK: - Tineo Editor View Controller

public final class TineoEditorViewController: UIViewController {
    private let filePath: String
    private let fs: VirtualFileSystem
    private let textView = UITextView()
    private let statusBar = UILabel()
    private var isModified = false
    private var lineHeight: CGFloat { Theme.font.lineHeight }

    public init(filePath: String, fs: VirtualFileSystem) {
        self.filePath = filePath
        self.fs = fs
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
        title = "Tineo - \(filePath)"
        setupNavBar()
        setupTextView()
        loadFile()
    }

    private func setupNavBar() {
        navigationItem.title = "Tineo"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Save", style: .done, target: self, action: #selector(save))
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Close", style: .plain, target: self, action: #selector(close))
    }

    private func setupTextView() {
        textView.font = UIFont(name: "Menlo", size: 14) ?? UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.backgroundColor = UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1)
        textView.textColor = UIColor(red: 0.88, green: 0.90, blue: 0.92, alpha: 1)
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = self
        view.addSubview(textView)

        statusBar.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        statusBar.textColor = UIColor(red: 0.45, green: 0.55, blue: 0.60, alpha: 1)
        statusBar.backgroundColor = UIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusBar)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 24)
        ])
        updateStatusBar()
    }

    private func loadFile() {
        let started = fs.startRootAccess()
        defer { if started { fs.stopRootAccess() } }
        guard let url = fs.resolve(filePath), let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            textView.text = ""
            return
        }
        let highlighted = SyntaxHighlighter.highlight(content, font: textView.font ?? Theme.font)
        textView.attributedText = highlighted
        updateStatusBar()
    }

    private func updateStatusBar() {
        let text = textView.text ?? ""
        let lines = text.components(separatedBy: "\n").count
        let chars = text.count
        let modified = isModified ? " [MODIFIED]" : ""
        statusBar.text = "  \(filePath)\(modified)  |  \(lines) lines  |  \(chars) chars  |  Tineo"
    }

    @objc private func save() {
        let started = fs.startRootAccess()
        defer { if started { fs.stopRootAccess() } }
        guard let url = fs.resolve(filePath) else { return }
        let text = textView.text ?? ""
        try? text.write(to: url, atomically: true, encoding: .utf8)
        isModified = false
        updateStatusBar()
        let alert = UIAlertController(title: "Saved", message: "\(filePath) saved.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func close() {
        if isModified {
            let alert = UIAlertController(title: "Unsaved changes",
                                          message: "Save before closing?", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
                self?.save()
                self?.dismiss(animated: true)
            })
            alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { [weak self] _ in
                self?.dismiss(animated: true)
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true)
        } else {
            dismiss(animated: true)
        }
    }
}

extension TineoEditorViewController: UITextViewDelegate {
    public func textViewDidChange(_ textView: UITextView) {
        isModified = true
        // Re-highlight (debounced for performance would be better, but simple for now)
        let text = textView.text ?? ""
        let highlighted = SyntaxHighlighter.highlight(text, font: textView.font ?? Theme.font)
        let cursor = textView.selectedRange
        textView.attributedText = highlighted
        textView.selectedRange = cursor
        updateStatusBar()
    }
}