import Foundation

struct HeadCommand: BuiltinCommand {
    let name = "head"
    let summary = "Print first lines of a file"
    let usage = "head [-n N] [file]"
    var operands: [Operand] {[
        Operand(name: "file", description: "File to read from (defaults to stdin)", required: false, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var n = 10
        var paths: [String] = []
        var i = 0
        while i < arguments.count {
            let a = arguments[i]
            if a == "-n" && i + 1 < arguments.count {
                n = Int(arguments[i + 1]) ?? 10
                i += 2
            } else if a.hasPrefix("-n") {
                n = Int(a.dropFirst(2)) ?? 10
                i += 1
            } else {
                paths.append(a)
                i += 1
            }
        }

        let input: String
        if paths.isEmpty {
            input = context.stdin
        } else {
            let started = context.fs.startRootAccess()
            var combined = ""
            for p in paths {
                guard let url = context.fs.resolve(p),
                      let data = try? Data(contentsOf: url),
                      let s = String(data: data, encoding: .utf8) else {
                    context.stderr("head: cannot read \(p)\n")
                    continue
                }
                combined += s
            }
            if started { context.fs.stopRootAccess() }
            input = combined
        }
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false)
        let taken = lines.prefix(n)
        context.stdout(taken.joined(separator: "\n") + "\n")
        return 0
    }
}

struct TailCommand: BuiltinCommand {
    let name = "tail"
    let summary = "Print last lines of a file"
    let usage = "tail [-n N] [file]"
    var operands: [Operand] {[
        Operand(name: "file", description: "File to read from (defaults to stdin)", required: false, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var n = 10
        var paths: [String] = []
        var i = 0
        while i < arguments.count {
            let a = arguments[i]
            if a == "-n" && i + 1 < arguments.count {
                n = Int(arguments[i + 1]) ?? 10
                i += 2
            } else if a.hasPrefix("-n") {
                n = Int(a.dropFirst(2)) ?? 10
                i += 1
            } else {
                paths.append(a)
                i += 1
            }
        }

        let input: String
        if paths.isEmpty {
            input = context.stdin
        } else {
            let started = context.fs.startRootAccess()
            var combined = ""
            for p in paths {
                guard let url = context.fs.resolve(p),
                      let data = try? Data(contentsOf: url),
                      let s = String(data: data, encoding: .utf8) else {
                    context.stderr("tail: cannot read \(p)\n")
                    continue
                }
                combined += s
            }
            if started { context.fs.stopRootAccess() }
            input = combined
        }
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false)
        let suffix = lines.suffix(n)
        context.stdout(suffix.joined(separator: "\n") + "\n")
        return 0
    }
}

struct WcCommand: BuiltinCommand {
    let name = "wc"
    let summary = "Count lines, words, and bytes"
    let usage = "wc [-l] [-w] [-c] [file]"
    var operands: [Operand] {[
        Operand(name: "file", description: "File to count (defaults to stdin)", required: false, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var countLines = false
        var countWords = false
        var countBytes = false
        var paths: [String] = []
        for a in arguments {
            if a.hasPrefix("-") {
                for f in a.dropFirst() {
                    if f == "l" { countLines = true }
                    else if f == "w" { countWords = true }
                    else if f == "c" { countBytes = true }
                }
            } else {
                paths.append(a)
            }
        }
        if !countLines && !countWords && !countBytes {
            countLines = true; countWords = true; countBytes = true
        }

        let input: String
        if paths.isEmpty {
            input = context.stdin
        } else {
            let started = context.fs.startRootAccess()
            var combined = ""
            for p in paths {
                if let url = context.fs.resolve(p),
                   let data = try? Data(contentsOf: url),
                   let s = String(data: data, encoding: .utf8) {
                    combined += s
                }
            }
            if started { context.fs.stopRootAccess() }
            input = combined
        }

        let lines = input.split(separator: "\n").count
        let words = input.split(whereSeparator: { $0.isWhitespace }).count
        let bytes = input.utf8.count
        var parts: [String] = []
        if countLines { parts.append("\(lines)") }
        if countWords { parts.append("\(words)") }
        if countBytes { parts.append("\(bytes)") }
        context.stdout(parts.joined(separator: " ") + "\n")
        return 0
    }
}

struct GrepCommand: BuiltinCommand {
    let name = "grep"
    let summary = "Search for a pattern in text"
    let usage = "grep [-i] pattern [file...]"
    var operands: [Operand] {[
        Operand(name: "pattern", description: "Text pattern to search for", required: true, type: .pattern),
        Operand(name: "file", description: "File(s) to search in (defaults to stdin)", required: false, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var ignoreCase = false
        var args: [String] = []
        for a in arguments {
            if a.hasPrefix("-") {
                for f in a.dropFirst() { if f == "i" { ignoreCase = true } }
            } else {
                args.append(a)
            }
        }
        guard let pattern = args.first else {
            context.stderr("grep: missing pattern\n")
            return 2
        }
        let files = Array(args.dropFirst())
        let input: String
        if files.isEmpty {
            input = context.stdin
        } else {
            let started = context.fs.startRootAccess()
            var combined = ""
            for f in files {
                if let url = context.fs.resolve(f),
                   let data = try? Data(contentsOf: url),
                   let s = String(data: data, encoding: .utf8) {
                    combined += s
                }
            }
            if started { context.fs.stopRootAccess() }
            input = combined
        }

        let search = ignoreCase ? pattern.lowercased() : pattern
        var matched = 0
        for line in input.split(separator: "\n", omittingEmptySubsequences: false) {
            let target = ignoreCase ? line.lowercased() : String(line)
            if target.contains(search) {
                context.stdout(String(line) + "\n")
                matched += 1
            }
        }
        return matched > 0 ? 0 : 1
    }
}

struct SortCommand: BuiltinCommand {
    let name = "sort"
    let summary = "Sort lines of text"
    let usage = "sort [-r] [file]"
    var operands: [Operand] {[
        Operand(name: "file", description: "File to sort (defaults to stdin)", required: false, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var reverse = false
        var paths: [String] = []
        for a in arguments {
            if a.hasPrefix("-") {
                for f in a.dropFirst() { if f == "r" { reverse = true } }
            } else { paths.append(a) }
        }
        let input: String
        if paths.isEmpty {
            input = context.stdin
        } else {
            let started = context.fs.startRootAccess()
            var combined = ""
            for p in paths {
                if let url = context.fs.resolve(p),
                   let data = try? Data(contentsOf: url),
                   let s = String(data: data, encoding: .utf8) {
                    combined += s
                }
            }
            if started { context.fs.stopRootAccess() }
            input = combined
        }
        var lines = input.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines.sort()
        if reverse { lines.reverse() }
        context.stdout(lines.joined(separator: "\n") + "\n")
        return 0
    }
}

struct UniqCommand: BuiltinCommand {
    let name = "uniq"
    let summary = "Remove adjacent duplicate lines"
    let usage = "uniq [file]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let input: String
        if let p = arguments.first {
            let started = context.fs.startRootAccess()
            if let url = context.fs.resolve(p),
               let data = try? Data(contentsOf: url),
               let s = String(data: data, encoding: .utf8) {
                input = s
            } else {
                input = context.stdin
            }
            if started { context.fs.stopRootAccess() }
        } else {
            input = context.stdin
        }
        var last: String? = nil
        for line in input.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if s != last {
                context.stdout(s + "\n")
                last = s
            }
        }
        return 0
    }
}

struct FindCommand: BuiltinCommand {
    let name = "find"
    let summary = "Find files under a directory"
    let usage = "find [path] [-name pattern]"
    var operands: [Operand] {[
        Operand(name: "path", description: "Starting directory to search from", required: false, type: .directory),
        Operand(name: "pattern", description: "Name pattern to match (with -name)", required: false, type: .pattern),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var startPath = "."
        var namePattern: String? = nil
        var i = 0
        while i < arguments.count {
            let a = arguments[i]
            if a == "-name" && i + 1 < arguments.count {
                namePattern = arguments[i + 1]
                i += 2
            } else if a.hasPrefix("-") {
                i += 1
            } else {
                startPath = a
                i += 1
            }
        }
        guard let rootURL = context.fs.resolve(startPath) else {
            context.stderr("find: cannot resolve \(startPath)\n")
            return 1
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let fm = FileManager.default
        var results: [String] = []
        let enumerator = fm.enumerator(atPath: rootURL.path)
        while let element = enumerator?.nextObject() as? String {
            if let pattern = namePattern {
                if !matchesSimple(element, pattern: pattern) { continue }
            }
            let logical = context.fs.logicalPath(of: rootURL.appendingPathComponent(element))
            results.append(logical)
        }
        // Include the start dir itself
        let rootLogical = context.fs.logicalPath(of: rootURL)
        context.stdout(rootLogical + "\n")
        for r in results.sorted() {
            context.stdout(r + "\n")
        }
        return 0
    }

    private func matchesSimple(_ name: String, pattern: String) -> Bool {
        // Convert shell glob to regex: '*' -> '.*', '?' -> '.'
        var regex = "^"
        for c in pattern {
            switch c {
            case "*": regex += ".*"
            case "?": regex += "."
            default:
                if "[](){}.+^$|\\".contains(c) { regex += "\\" + String(c) }
                else { regex.append(c) }
            }
        }
        regex += "$"
        return name.range(of: regex, options: .regularExpression) != nil
    }
}

struct TreeCommand: BuiltinCommand {
    let name = "tree"
    let summary = "List contents in a tree"
    let usage = "tree [path]"
    var operands: [Operand] {[
        Operand(name: "path", description: "Directory to tree from", required: false, type: .directory),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let startPath = arguments.first ?? "."
        guard let rootURL = context.fs.resolve(startPath) else {
            context.stderr("tree: cannot resolve \(startPath)\n")
            return 1
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let fm = FileManager.default
        context.stdout(context.fs.logicalPath(of: rootURL) + "\n")
        walk(url: rootURL, prefix: "", fs: context.fs, fm: fm, out: context.stdout)
        return 0
    }

    private func walk(url: URL, prefix: String, fs: VirtualFileSystem,
                      fm: FileManager, out: (String) -> Void) {
        guard let entries = try? fm.contentsOfDirectory(atPath: url.path).filter({ !$0.hasPrefix(".") }).sorted() else { return }
        for (idx, entry) in entries.enumerated() {
            let last = idx == entries.count - 1
            let branch = last ? "└── " : "├── "
            out(prefix + branch + entry + "\n")
            let entryURL = url.appendingPathComponent(entry)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: entryURL.path, isDirectory: &isDir), isDir.boolValue {
                let newPrefix = prefix + (last ? "    " : "│   ")
                walk(url: entryURL, prefix: newPrefix, fs: fs, fm: fm, out: out)
            }
        }
    }
}

struct StatCommand: BuiltinCommand {
    let name = "stat"
    let summary = "Show file metadata"
    let usage = "stat file..."
    var operands: [Operand] {[
        Operand(name: "file", description: "File(s) to show metadata for", required: true, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        if arguments.isEmpty {
            context.stderr("stat: missing operand\n")
            return 1
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let fm = FileManager.default
        var hadError = false
        for p in arguments {
            guard let url = context.fs.resolve(p) else {
                context.stderr("stat: \(p): no such file\n")
                hadError = true
                continue
            }
            guard let attrs = try? fm.attributesOfItem(atPath: url.path) else {
                context.stderr("stat: \(p): cannot stat\n")
                hadError = true
                continue
            }
            let size = (attrs[.size] as? Int) ?? 0
            let type = (attrs[.type] as? FileAttributeType) ?? .typeUnknown
            let mod = (attrs[.modificationDate] as? Date) ?? Date()
            let created = (attrs[.creationDate] as? Date) ?? Date()
            var out = "File: \(p)\n"
            out += "Size: \(size)    Type: \(type.rawValue)\n"
            out += "Modified: \(ISO8601DateFormatter().string(from: mod))\n"
            out += "Created:  \(ISO8601DateFormatter().string(from: created))\n\n"
            context.stdout(out)
        }
        return hadError ? 1 : 0
    }
}

struct DuCommand: BuiltinCommand {
    let name = "du"
    let summary = "Estimate file space usage"
    let usage = "du [path]"
    var operands: [Operand] {[
        Operand(name: "path", description: "Directory to estimate size of", required: false, type: .path),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let startPath = arguments.first ?? "."
        guard let rootURL = context.fs.resolve(startPath) else {
            context.stderr("du: cannot resolve \(startPath)\n")
            return 1
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let fm = FileManager.default
        var total = 0
        let enumerator = fm.enumerator(atPath: rootURL.path)
        while let element = enumerator?.nextObject() as? String {
            let url = rootURL.appendingPathComponent(element)
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? Int {
                total += size
            }
        }
        context.stdout("\(total)\t\(context.fs.logicalPath(of: rootURL))\n")
        return 0
    }
}

struct WriteCommand: BuiltinCommand {
    let name = "write"
    let summary = "Write stdin to a file (overwrite)"
    let usage = "write [-a] file"
    var operands: [Operand] {[
        Operand(name: "file", description: "File to write to (use -a to append)", required: true, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var append = false
        var target: String?
        for a in arguments {
            if a == "-a" { append = true }
            else if !a.hasPrefix("-") { target = a }
        }
        guard let path = target else {
            context.stderr("write: missing file operand\n")
            return 1
        }
        guard let url = context.fs.resolve(path) else {
            context.stderr("write: cannot resolve \(path)\n")
            return 1
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let data = Data(context.stdin.utf8)
        do {
            if append && FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try data.write(to: url)
            }
        } catch {
            context.stderr("write: \(error.localizedDescription)\n")
            return 1
        }
        return 0
    }
}

struct OpenCommand: BuiltinCommand {
    let name = "open"
    let summary = "Open the Files app picker to grant access to a folder"
    let usage = "open   (then pick a folder in the Files app)"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        // Signals the UI to present UIDocumentPicker. Emitted via stdout marker.
        context.stdout("\u{001B}]OPEN_PICKER\u{0007}")
        return 0
    }
}

struct BookmarksCommand: BuiltinCommand {
    let name = "bookmarks"
    let summary = "List or remove saved folder grants from the Files app"
    let usage = "bookmarks [rm <id>]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        if arguments.first == "rm", let id = arguments.dropFirst().first {
            context.fs.removeBookmark(id)
            context.stdout("removed \(id)\n")
            return 0
        }
        if context.fs.bookmarks.isEmpty {
            context.stdout("No saved folders. Run 'open' to grant access to a Files app folder.\n")
            return 0
        }
        for id in context.fs.bookmarks.keys.sorted() {
            let marker = (context.fs.rootKind == .bookmark(id)) ? " *" : ""
            context.stdout("\(id)\(marker)\n")
        }
        return 0
    }
}