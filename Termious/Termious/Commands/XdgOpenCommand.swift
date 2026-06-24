import Foundation
import UIKit

/// `xdg-open` / `open` - open HTML/XML/files in the default browser (Safari).
/// Usage: xdg-open <url-or-file>
struct XdgOpenCommand: BuiltinCommand {
    let name = "xdg-open"
    let summary = "Open a URL or file in the default browser"
    let usage = "xdg-open <url|file>"
    var operands: [Operand] {[
        Operand(name: "target", description: "URL or file to open in Safari", required: true, type: .string),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let target = arguments.first else {
            context.stderr("xdg-open: missing argument\n"); return 1
        }

        // If it looks like a URL (http://, https://), open directly
        if target.hasPrefix("http://") || target.hasPrefix("https://") {
            context.stdout("\u{001B}]OPEN_URL\u{0007}\(target)\u{0007}")
            return 0
        }

        // If it's a file, resolve and check if it's HTML/XML
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }

        guard let url = context.fs.resolve(target) else {
            context.stderr("xdg-open: cannot resolve '\(target)'\n"); return 1
        }

        let ext = url.pathExtension.lowercased()
        let htmlXmlExts: Set<String> = ["html", "htm", "xml", "xhtml", "svg", "css", "js"]
        let textExts: Set<String> = ["txt", "md", "json", "csv", "log", "swift", "py", "sh",
                                      "yml", "yaml", "plist", "c", "cpp", "h", "java", "rb",
                                      "go", "rs", "ts", "tsx", "jsx", "sql", "conf", "ini"]

        if htmlXmlExts.contains(ext) {
            // Copy to a temp file and open via share/safari
            if let data = try? Data(contentsOf: url) {
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "." + ext)
                try? data.write(to: temp)
                context.stdout("\u{001B}]OPEN_URL\u{0007}\(temp.absoluteString)\u{0007}")
                context.stdout("Opening '\(target)' in Safari...\n")
                return 0
            }
        } else if textExts.contains(ext) {
            // Open in Tineo editor
            context.stdout("\u{001B}]TINEO_EDIT\u{0007}EDIT:\(target)\u{0007}")
            return 0
        }

        // Try to open as URL directly
        if URL(string: target) != nil, target.contains(".") {
            context.stdout("\u{001B}]OPEN_URL\u{0007}\(target)\u{0007}")
            return 0
        }

        context.stderr("xdg-open: don't know how to open '\(target)'\n")
        return 1
    }
}

/// `safari` - alias for xdg-open, opens in Safari explicitly.
struct SafariCommand: BuiltinCommand {
    let name = "safari"
    let summary = "Open a URL in Safari"
    let usage = "safari <url>"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let target = arguments.first else { context.stderr("safari: missing URL\n"); return 1 }
        let urlStr = target.hasPrefix("http") ? target : "https://\(target)"
        context.stdout("\u{001B}]OPEN_URL\u{0007}\(urlStr)\u{0007}")
        return 0
    }
}