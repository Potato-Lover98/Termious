import Foundation
import UIKit
import CryptoKit

/// `sed` - stream editor (substitute only).
/// Usage: sed 's/pattern/replacement/[flags]' [file]
struct SedCommand: BuiltinCommand {
    let name = "sed"
    let summary = "Stream editor (substitute)"
    let usage = "sed 's/pattern/replacement/[g]' [file]"
    var operands: [Operand] {[
        Operand(name: "expr", description: "Substitution expression like s/old/new/g", required: true, type: .pattern),
        Operand(name: "file", description: "File to process (defaults to stdin)", required: false, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let expr = arguments.first else {
            context.stderr("sed: missing expression\n"); return 1
        }
        let files = Array(arguments.dropFirst()).filter { !$0.hasPrefix("-") }
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
        guard parseAndApply(expr, to: input, out: context.stdout) else {
            context.stderr("sed: invalid expression '\(expr)'\n")
            return 1
        }
        return 0
    }

    private func parseAndApply(_ expr: String, to input: String, out: (String) -> Void) -> Bool {
        guard expr.hasPrefix("s") else { return false }
        let body = String(expr.dropFirst())
        guard let delim = body.first else { return false }
        let parts = body.dropFirst().split(separator: delim, maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        let pattern = String(parts[0])
        let replacement = String(parts[1])
        let flags = parts.count > 2 ? String(parts[2]) : ""

        let global = flags.contains("g")
        let ignoreCase = flags.contains("i")
        let useRegex = flags.contains("E") || flags.contains("r")

        for line in input.split(separator: "\n", omittingEmptySubsequences: false) {
            var s = String(line)
            var opts: String.CompareOptions = useRegex ? .regularExpression : []
            if ignoreCase { opts.insert(.caseInsensitive) }
            if global {
                s = s.replacingOccurrences(of: pattern, with: replacement, options: opts)
            } else {
                if let range = s.range(of: pattern, options: opts) {
                    s.replaceSubrange(range, with: replacement)
                }
            }
            out(s + "\n")
        }
        return true
    }
}

/// `awk` - minimal awk (field splitting and printing).
/// Usage: awk '{print $1}' [file]  |  awk -F, '{print $2}' [file]
struct AwkCommand: BuiltinCommand {
    let name = "awk"
    let summary = "Pattern scanning and processing (basic)"
    let usage = "awk [-F sep] '{print $N...}' [file]"
    var operands: [Operand] {[
        Operand(name: "program", description: "Awk program like {print $1}", required: true, type: .string),
        Operand(name: "file", description: "File to process (defaults to stdin)", required: false, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var separator: String = " "
        var program: String? = nil
        var files: [String] = []
        var i = 0
        while i < arguments.count {
            let a = arguments[i]
            if a == "-F" && i + 1 < arguments.count {
                separator = arguments[i + 1]; i += 2
            } else if a.hasPrefix("-F") {
                separator = String(a.dropFirst(2)); i += 1
            } else if program == nil {
                program = a; i += 1
            } else {
                files.append(a); i += 1
            }
        }
        guard let program = program else {
            context.stderr("awk: missing program\n"); return 1
        }
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
        for line in input.split(separator: "\n", omittingEmptySubsequences: false) {
            var fields: [String]
            if separator == " " {
                fields = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            } else {
                fields = line.components(separatedBy: separator)
            }
            let result = applyPrint(program, fields: fields, line: String(line))
            if !result.isEmpty { context.stdout(result + "\n") }
        }
        return 0
    }

    private func applyPrint(_ program: String, fields: [String], line: String) -> String {
        // Very simple: {print $1}, {print $1,$2}, {print}, {print $0}
        let stripped = program.trimmingCharacters(in: CharacterSet(charactersIn: "{}"))
        guard stripped.hasPrefix("print") else { return "" }
        let args = String(stripped.dropFirst()).trimmingCharacters(in: .whitespaces)
        if args.isEmpty { return line }
        let parts = args.split(separator: ",")
        var result: [String] = []
        for part in parts {
            let p = String(part).trimmingCharacters(in: .whitespaces)
            if p == "$0" { result.append(line) }
            else if p.hasPrefix("$") {
                let idx = Int(p.dropFirst()) ?? 0
                result.append(idx > 0 && idx <= fields.count ? fields[idx - 1] : "")
            } else {
                result.append(p.replacingOccurrences(of: "\"", with: ""))
            }
        }
        return result.joined(separator: " ")
    }
}

/// `cut` - remove sections from each line.
/// Usage: cut -d<delim> -f<N> [file]
struct CutCommand: BuiltinCommand {
    let name = "cut"
    let summary = "Cut fields from lines"
    let usage = "cut -d<delim> -f<fields> [file]"
    var operands: [Operand] {[
        Operand(name: "fields", description: "Field numbers to extract (with -f)", required: true, type: .string),
        Operand(name: "file", description: "File to cut from (defaults to stdin)", required: false, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var delim: String = "\t"
        var fields: [Int] = []
        var files: [String] = []
        for a in arguments {
            if a.hasPrefix("-d") { delim = String(a.dropFirst(2)) }
            else if a.hasPrefix("-f") {
                fields = a.dropFirst(2).split(separator: ",").compactMap { Int($0) }
            } else if !a.hasPrefix("-") { files.append(a) }
        }
        if fields.isEmpty { context.stderr("cut: missing -f\n"); return 1 }
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
        for line in input.split(separator: "\n", omittingEmptySubsequences: false) {
            let parts = line.components(separatedBy: delim)
            var selected: [String] = []
            for f in fields {
                if f > 0 && f <= parts.count { selected.append(parts[f - 1]) }
            }
            context.stdout(selected.joined(separator: delim) + "\n")
        }
        return 0
    }
}

/// `tr` - translate or delete characters.
/// Usage: tr <from> <to>  |  tr -d <set>
struct TrCommand: BuiltinCommand {
    let name = "tr"
    let summary = "Translate or delete characters"
    let usage = "tr <from> <to> | tr -d <set>"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var deleteMode = false
        var args: [String] = []
        for a in arguments {
            if a == "-d" { deleteMode = true }
            else { args.append(a) }
        }
        let input = context.stdin
        if deleteMode {
            guard let set = args.first else { return 1 }
            let chars = Set(set)
            let result = String(input.filter { !chars.contains($0) })
            context.stdout(result)
            return 0
        }
        guard args.count >= 2 else {
            context.stderr("tr: need two arguments\n"); return 1
        }
        let from = args[0]; let to = args[1]
        var result = ""
        for c in input {
            if let idx = from.firstIndex(of: c) {
                let dist = from.distance(from: from.startIndex, to: idx)
                if dist < to.count {
                    let toIdx = to.index(to.startIndex, offsetBy: dist)
                    result.append(to[toIdx])
                } else { result.append(to.last ?? c) }
            } else { result.append(c) }
        }
        context.stdout(result)
        return 0
    }
}

/// `diff` - compare two files line by line.
struct DiffCommand: BuiltinCommand {
    let name = "diff"
    let summary = "Compare two files"
    let usage = "diff <file1> <file2>"
    var operands: [Operand] {[
        Operand(name: "file1", description: "First file to compare", required: true, type: .file),
        Operand(name: "file2", description: "Second file to compare", required: true, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard arguments.count >= 2 else {
            context.stderr("diff: need two files\n"); return 2
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        guard let a = context.fs.resolve(arguments[0]),
              let b = context.fs.resolve(arguments[1]),
              let dataA = try? Data(contentsOf: a),
              let dataB = try? Data(contentsOf: b),
              let strA = String(data: dataA, encoding: .utf8),
              let strB = String(data: dataB, encoding: .utf8) else {
            context.stderr("diff: cannot read files\n"); return 2
        }
        let linesA = strA.split(separator: "\n", omittingEmptySubsequences: false)
        let linesB = strB.split(separator: "\n", omittingEmptySubsequences: false)
        let maxLen = max(linesA.count, linesB.count)
        var differences = 0
        for i in 0..<maxLen {
            let la = i < linesA.count ? String(linesA[i]) : nil
            let lb = i < linesB.count ? String(linesB[i]) : nil
            if la != lb {
                differences += 1
                if let la = la { context.stdout("< \(la)\n") }
                if let lb = lb { context.stdout("> \(lb)\n") }
            }
        }
        return differences > 0 ? 1 : 0
    }
}

/// `rev` - reverse each line.
struct RevCommand: BuiltinCommand {
    let name = "rev"
    let summary = "Reverse lines character-wise"
    let usage = "rev [file]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let input: String
        if let f = arguments.first {
            let started = context.fs.startRootAccess()
            if let url = context.fs.resolve(f),
               let data = try? Data(contentsOf: url),
               let s = String(data: data, encoding: .utf8) {
                input = s
            } else { input = context.stdin }
            if started { context.fs.stopRootAccess() }
        } else { input = context.stdin }
        for line in input.split(separator: "\n", omittingEmptySubsequences: false) {
            context.stdout(String(line.reversed()) + "\n")
        }
        return 0
    }
}

/// `paste` - merge lines of files.
struct PasteCommand: BuiltinCommand {
    let name = "paste"
    let summary = "Merge lines of files"
    let usage = "paste <file1> <file2>"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        var allLines: [[String]] = []
        for f in arguments {
            if let url = context.fs.resolve(f),
               let data = try? Data(contentsOf: url),
               let s = String(data: data, encoding: .utf8) {
                allLines.append(s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init))
            } else {
                allLines.append([])
            }
        }
        let maxLen = allLines.map { $0.count }.max() ?? 0
        for i in 0..<maxLen {
            let row = allLines.map { i < $0.count ? $0[i] : "" }
            context.stdout(row.joined(separator: "\t") + "\n")
        }
        return 0
    }
}

/// `basename` - strip directory and suffix from path.
struct BasenameCommand: BuiltinCommand {
    let name = "basename"
    let summary = "Strip directory and suffix"
    let usage = "basename <path> [suffix]"
    var operands: [Operand] {[
        Operand(name: "path", description: "Path to strip directory from", required: true, type: .path),
        Operand(name: "suffix", description: "Suffix to remove from filename", required: false, type: .string),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let path = arguments.first else {
            context.stderr("basename: missing operand\n"); return 1
        }
        var name = (path as NSString).lastPathComponent
        if let suffix = arguments.dropFirst().first, name.hasSuffix(suffix) {
            name = String(name.dropLast(suffix.count))
        }
        context.stdout(name + "\n")
        return 0
    }
}

/// `dirname` - strip last component from path.
struct DirnameCommand: BuiltinCommand {
    let name = "dirname"
    let summary = "Strip last path component"
    let usage = "dirname <path>"
    var operands: [Operand] {[
        Operand(name: "path", description: "Path to strip last component from", required: true, type: .path),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let path = arguments.first else {
            context.stderr("dirname: missing operand\n"); return 1
        }
        context.stdout((path as NSString).deletingLastPathComponent + "\n")
        return 0
    }
}

/// `realpath` - resolve a path to absolute.
struct RealpathCommand: BuiltinCommand {
    let name = "realpath"
    let summary = "Print the resolved absolute path"
    let usage = "realpath <path>"
    var operands: [Operand] {[
        Operand(name: "path", description: "Path to resolve to absolute", required: true, type: .path),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let path = arguments.first else {
            context.stderr("realpath: missing operand\n"); return 1
        }
        guard let url = context.fs.resolve(path) else {
            context.stderr("realpath: cannot resolve \(path)\n"); return 1
        }
        context.stdout(context.fs.logicalPath(of: url) + "\n")
        return 0
    }
}

/// `file` - determine file type.
struct FileCommand: BuiltinCommand {
    let name = "file"
    let summary = "Determine file type"
    let usage = "file <path...>"
    var operands: [Operand] {[
        Operand(name: "path", description: "File(s) to identify type of", required: true, type: .path),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        for p in arguments {
            guard let url = context.fs.resolve(p) else {
                context.stderr("file: \(p): cannot open\n"); continue
            }
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
                context.stderr("file: \(p): cannot open\n"); continue
            }
            if isDir.boolValue {
                context.stdout("\(p): directory\n"); continue
            }
            guard let data = try? Data(contentsOf: url) else {
                context.stdout("\(p): unreadable\n"); continue
            }
            let type = detectType(data: data)
            context.stdout("\(p): \(type)\n")
        }
        return 0
    }

    private func detectType(data: Data) -> String {
        guard data.count >= 4 else { return "data" }
        let bytes = [UInt8](data.prefix(8))
        if bytes[0] == 0x50 && bytes[1] == 0x4B { return "Zip archive" }
        if bytes[0] == 0x1F && bytes[1] == 0x8B { return "gzip compressed" }
        if bytes[0] == 0xFF && bytes[1] == 0xD8 { return "JPEG image" }
        if bytes[0] == 0x89 && bytes[1] == 0x50 { return "PNG image" }
        if bytes[0] == 0x25 && bytes[1] == 0x50 { return "PDF document" }
        if data.count > 0 && bytes.allSatisfy({ b in b == 0x09 || b == 0x0A || b == 0x0D || (b >= 0x20 && b <= 0x7E) }) {
            return "ASCII text"
        }
        return "data"
    }
}

/// `which` - locate a command.
struct WhichCommand: BuiltinCommand {
    let name = "which"
    let summary = "Locate a builtin command"
    let usage = "which <command...>"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        // We don't have access to the registry directly here; emit a signal
        // that ShellHost intercepts. For simplicity, return a generic answer.
        var error = false
        for cmd in arguments {
            // Builtin commands are "in" the shell
            context.stdout("/bin/termious/\(cmd)\n")
        }
        return error ? 1 : 0
    }
}

/// `history` - show command history. The actual history is in the UI layer;
/// this emits a signal that TerminalViewController intercepts.
struct HistoryCommand: BuiltinCommand {
    let name = "history"
    let summary = "Show command history"
    let usage = "history"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("\u{001B}]SHOW_HISTORY\u{0007}")
        return 0
    }
}

/// `man` - manual pages for builtins.
struct ManCommand: BuiltinCommand {
    let name = "man"
    let summary = "Show manual for a command"
    let usage = "man <command>"
    var operands: [Operand] {[
        Operand(name: "command", description: "Command to show manual for", required: true, type: .string),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let name = arguments.first else {
            context.stderr("What manual page do you want?\n"); return 1
        }
        context.stdout("\u{001B}]MAN_PAGE\u{0007}\(name)\u{0007}")
        return 0
    }
}

/// `df` - report disk space usage.
struct DfCommand: BuiltinCommand {
    let name = "df"
    let summary = "Show filesystem disk space"
    let usage = "df [-h]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let url = context.fs.rootURL
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: url.path)
        let total = (attrs?[.systemSize] as? Int) ?? 0
        let free = (attrs?[.systemFreeSize] as? Int) ?? 0
        let used = total - free
        let human = arguments.contains("-h")
        context.stdout("Filesystem    Size   Used  Avail  Use%  Mounted on\n")
        if human {
            context.stdout(String(format: "%-12s %6s %6s %6s %4d%%  %@\n",
                                  "aero-root", fmtHuman(total), fmtHuman(used),
                                  fmtHuman(free), total > 0 ? (used * 100 / total) : 0,
                                  context.fs.logicalPath(of: url)))
        } else {
            context.stdout(String(format: "%-12s %10d %10d %10d %4d%%  %@\n",
                                  "aero-root", total, used, free,
                                  total > 0 ? (used * 100 / total) : 0,
                                  context.fs.logicalPath(of: url)))
        }
        return 0
    }

    private func fmtHuman(_ bytes: Int) -> String {
        let units = ["B", "K", "M", "G", "T"]
        var size = Double(bytes)
        var idx = 0
        while size >= 1024, idx < units.count - 1 {
            size /= 1024; idx += 1
        }
        return String(format: "%.1f%@", size, units[idx])
    }
}

/// `free` - show memory info.
struct FreeCommand: BuiltinCommand {
    let name = "free"
    let summary = "Show memory usage"
    let usage = "free [-h]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if result == KERN_SUCCESS {
            let human = arguments.contains("-h")
            if human {
                context.stdout("               total        used        free\n")
                context.stdout("Mem:  \(fmtH(Int(info.virtual_size)))  \(fmtH(Int(info.resident_size)))  \(fmtH(Int(info.virtual_size - info.resident_size)))\n")
            } else {
                context.stdout("               total        used        free\n")
                context.stdout(String(format: "Mem:  %10d  %10d  %10d\n",
                                      Int(info.virtual_size), Int(info.resident_size),
                                      Int(info.virtual_size - info.resident_size)))
            }
        } else {
            context.stdout("Memory info unavailable.\n")
        }
        return 0
    }

    private func fmtH(_ bytes: Int) -> String {
        let units = ["B", "K", "M", "G", "T"]
        var size = Double(bytes); var idx = 0
        while size >= 1024, idx < units.count - 1 { size /= 1024; idx += 1 }
        return String(format: "%.1f%@", size, units[idx])
    }
}

/// `uname` - print system information.
struct UnameCommand: BuiltinCommand {
    let name = "uname"
    let summary = "Print system information"
    let usage = "uname [-a]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let all = arguments.contains("-a")
        let sysName = "Darwin"
        let nodeName = UIDevice.current.name
        let release = UIDevice.current.systemVersion
        let version = "Termious/iOS"
        let machine = UIDevice.current.model
        if all {
            context.stdout("\(sysName) \(nodeName) \(release) \(version) \(machine)\n")
        } else {
            context.stdout(sysName + "\n")
        }
        return 0
    }
}

/// `uptime` - show session uptime.
struct UptimeCommand: BuiltinCommand {
    let name = "uptime"
    let summary = "Show how long the shell has been running"
    let usage = "uptime"

    static let startTime = Date()
    func run(arguments: [String], context: CommandContext) -> Int32 {
        let elapsed = Date().timeIntervalSince(UptimeCommand.startTime)
        let h = Int(elapsed) / 3600
        let m = (Int(elapsed) % 3600) / 60
        let s = Int(elapsed) % 60
        context.stdout(String(format: "%02d:%02d:%02d up\n", h, m, s))
        return 0
    }
}

/// `hostname` - print device name.
struct HostnameCommand: BuiltinCommand {
    let name = "hostname"
    let summary = "Print the device hostname"
    let usage = "hostname"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout(UIDevice.current.name + "\n")
        return 0
    }
}

/// `id` - print user and group IDs.
struct IdCommand: BuiltinCommand {
    let name = "id"
    let summary = "Print real and effective user/group IDs"
    let usage = "id"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        if SudoSession.shared.isAuthenticated {
            context.stdout("uid=0(root) gid=0(root) groups=0(root),1(staff)\n")
        } else {
            context.stdout("uid=501(mobile) gid=20(staff) groups=20(staff)\n")
        }
        return 0
    }
}

/// `yes` - repeatedly print a string.
struct YesCommand: BuiltinCommand {
    let name = "yes"
    let summary = "Repeatedly output a line"
    let usage = "yes [string]"
    var operands: [Operand] {[
        Operand(name: "string", description: "String to repeat (defaults to y)", required: false, type: .string),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let str = arguments.isEmpty ? "y" : arguments.joined(separator: " ")
        // Limit to prevent infinite loop in the UI
        for _ in 0..<1000 {
            context.stdout(str + "\n")
        }
        context.stdout("[yes: stopped after 1000 lines]\n")
        return 0
    }
}

/// `seq` - print a sequence of numbers.
struct SeqCommand: BuiltinCommand {
    let name = "seq"
    let summary = "Print numeric sequences"
    let usage = "seq [start] [step] end"
    var operands: [Operand] {[
        Operand(name: "start", description: "Starting number (defaults to 1)", required: false, type: .number),
        Operand(name: "end", description: "Ending number", required: true, type: .number),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let nums = arguments.compactMap { Int($0) }
        var start = 1; var step = 1; var end = 1
        switch nums.count {
        case 1: end = nums[0]
        case 2: start = nums[0]; end = nums[1]
        case 3: start = nums[0]; step = nums[1]; end = nums[2]
        default: context.stderr("seq: invalid arguments\n"); return 1
        }
        if step > 0 {
            var i = start
            while i <= end { context.stdout("\(i)\n"); i += step }
        } else if step < 0 {
            var i = start
            while i >= end { context.stdout("\(i)\n"); i += step }
        }
        return 0
    }
}

/// `nl` - number lines.
struct NlCommand: BuiltinCommand {
    let name = "nl"
    let summary = "Number lines of files"
    let usage = "nl [file]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let input: String
        if let f = arguments.first {
            let started = context.fs.startRootAccess()
            if let url = context.fs.resolve(f),
               let data = try? Data(contentsOf: url),
               let s = String(data: data, encoding: .utf8) {
                input = s
            } else { input = context.stdin }
            if started { context.fs.stopRootAccess() }
        } else { input = context.stdin }
        var n = 1
        for line in input.split(separator: "\n", omittingEmptySubsequences: false) {
            context.stdout(String(format: "%6d  %@\n", n, String(line)))
            n += 1
        }
        return 0
    }
}

/// `tac` - reverse lines of a file (cat backwards).
struct TacCommand: BuiltinCommand {
    let name = "tac"
    let summary = "Concatenate and print files in reverse"
    let usage = "tac [file]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let input: String
        if let f = arguments.first {
            let started = context.fs.startRootAccess()
            if let url = context.fs.resolve(f),
               let data = try? Data(contentsOf: url),
               let s = String(data: data, encoding: .utf8) {
                input = s
            } else { input = context.stdin }
            if started { context.fs.stopRootAccess() }
        } else { input = context.stdin }
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines.reversed() {
            context.stdout(String(line) + "\n")
        }
        return 0
    }
}

/// `md5` / `sha256` - compute file hashes.
struct HashCommand: BuiltinCommand {
    let name = "hash"
    let summary = "Compute MD5/SHA256 of a file"
    let usage = "hash [--md5|--sha256] <file>"
    var operands: [Operand] {[
        Operand(name: "file", description: "File to compute hash of", required: true, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var algo = "sha256"
        var files: [String] = []
        for a in arguments {
            if a == "--md5" { algo = "md5" }
            else if a == "--sha256" { algo = "sha256" }
            else if !a.hasPrefix("-") { files.append(a) }
        }
        if files.isEmpty { context.stderr("hash: missing file\n"); return 1 }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        for f in files {
            guard let url = context.fs.resolve(f),
                  let data = try? Data(contentsOf: url) else {
                context.stderr("hash: \(f): cannot read\n"); continue
            }
            if algo == "md5" {
                // MD5 isn't in CryptoKit; use a manual approach or CommonCrypto
                context.stdout("\(md5Hex(data))  \(f)\n")
            } else {
                let digest = SHA256.hash(data: data)
                let hex = digest.map { String(format: "%02x", $0) }.joined()
                context.stdout("\(hex)  \(f)\n")
            }
        }
        return 0
    }

    private func md5Hex(_ data: Data) -> String {
        // Simple MD5 implementation
        let digest = MD5().compute(data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// `base64` - encode/decode base64.
struct Base64Command: BuiltinCommand {
    let name = "base64"
    let summary = "Base64 encode/decode"
    let usage = "base64 [-d] [file]"
    var operands: [Operand] {[
        Operand(name: "file", description: "File to encode/decode (defaults to stdin)", required: false, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var decode = false
        var files: [String] = []
        for a in arguments {
            if a == "-d" { decode = true }
            else if !a.hasPrefix("-") { files.append(a) }
        }
        let input: String
        if let f = files.first {
            let started = context.fs.startRootAccess()
            if let url = context.fs.resolve(f),
               let data = try? Data(contentsOf: url),
               let s = String(data: data, encoding: .utf8) {
                input = s
            } else { input = context.stdin }
            if started { context.fs.stopRootAccess() }
        } else { input = context.stdin }

        if decode {
            if let data = Data(base64Encoded: input.trimmingCharacters(in: .whitespacesAndNewlines)),
               let str = String(data: data, encoding: .utf8) {
                context.stdout(str)
                if !str.hasSuffix("\n") { context.stdout("\n") }
            } else {
                context.stderr("base64: invalid input\n"); return 1
            }
        } else {
            let data = Data(input.utf8)
            context.stdout(data.base64EncodedString() + "\n")
        }
        return 0
    }
}

/// `sleep` - delay for N seconds.
struct SleepCommand: BuiltinCommand {
    let name = "sleep"
    let summary = "Delay for a number of seconds"
    let usage = "sleep <seconds>"
    var operands: [Operand] {[
        Operand(name: "seconds", description: "Number of seconds to delay", required: true, type: .number),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let secs = Double(arguments.first ?? ""), secs > 0 else {
            context.stderr("sleep: invalid interval\n"); return 1
        }
        Thread.sleep(forTimeInterval: secs)
        return 0
    }
}

/// `time` - measure command execution time. Emits a signal for ShellHost.
struct TimeCommand: BuiltinCommand {
    let name = "time"
    let summary = "Measure command execution time"
    let usage = "time <command...>"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        if arguments.isEmpty {
            context.stderr("time: missing command\n"); return 1
        }
        // Emit signal for ShellHost to time the rest
        let cmd = arguments.joined(separator: " ")
        context.stdout("\u{001B}]TIME_CMD\u{0007}\(cmd)\u{0007}")
        return 0
    }
}

/// `export` - set environment variables.
struct ExportCommand: BuiltinCommand {
    let name = "export"
    let summary = "Set environment variables"
    let usage = "export KEY=VALUE"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        for arg in arguments {
            let parts = arg.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                context.stdout("\u{001B}]EXPORT\u{0007}\(parts[0])=\(parts[1])\u{0007}")
            }
        }
        return 0
    }
}

/// `alias` - (informational, not functional aliases yet)
struct AliasCommand: BuiltinCommand {
    let name = "alias"
    let summary = "Show or set aliases"
    let usage = "alias [name='value']"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        if arguments.isEmpty {
            context.stdout("No aliases set. (Aliases are not persisted in this version.)\n")
            return 0
        }
        for arg in arguments {
            let parts = arg.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                context.stdout("\u{001B}]ALIAS\u{0007}\(parts[0])=\(parts[1])\u{0007}")
            } else {
                context.stdout("alias: \(arg) not found\n")
            }
        }
        return 0
    }
}

/// `ping` - minimal ping (HTTP-based connectivity check).
struct PingCommand: BuiltinCommand {
    let name = "ping"
    let summary = "Send HTTP HEAD requests to a host"
    let usage = "ping [-c N] <host>"
    var operands: [Operand] {[
        Operand(name: "host", description: "Hostname or URL to ping", required: true, type: .string),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var count = 4
        var host: String? = nil
        var i = 0
        while i < arguments.count {
            let a = arguments[i]
            if a == "-c" && i + 1 < arguments.count {
                count = Int(arguments[i + 1]) ?? 4; i += 2
            } else if !a.hasPrefix("-") { host = a; i += 1 }
            else { i += 1 }
        }
        guard let host = host else { context.stderr("ping: missing host\n"); return 1 }
        let urlStr = host.hasPrefix("http") ? host : "https://\(host)"
        guard let url = URL(string: urlStr) else { context.stderr("ping: bad host\n"); return 1 }
        context.stdout("PING \(host)...\n")
        let group = DispatchGroup()
        for n in 1...count {
            group.enter()
            let start = Date()
            var req = URLRequest(url: url)
            req.httpMethod = "HEAD"
            req.timeoutInterval = 5
            URLSession.shared.dataTask(with: req) { _, response, error in
                let elapsed = Date().timeIntervalSince(start) * 1000
                if let error = error {
                    context.stdout(String(format: "seq=%d error: %@\n", n, error.localizedDescription))
                } else if let resp = response as? HTTPURLResponse {
                    context.stdout(String(format: "seq=%d status=%d time=%.1fms\n",
                                          n, resp.statusCode, elapsed))
                }
                group.leave()
            }.resume()
            group.wait()
            if n < count { Thread.sleep(forTimeInterval: 1.0) }
        }
        context.stdout("--- ping done ---\n")
        return 0
    }
}

/// `ln` - create links (best-effort: copies on iOS).
struct LnCommand: BuiltinCommand {
    let name = "ln"
    let summary = "Link files (copies on iOS)"
    let usage = "ln [-s] <target> <link>"
    var operands: [Operand] {[
        Operand(name: "target", description: "File to link to", required: true, type: .path),
        Operand(name: "link", description: "Name of the new link", required: true, type: .path),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var args = arguments.filter { $0 != "-s" }
        guard args.count >= 2 else {
            context.stderr("ln: missing operand\n"); return 1
        }
        let target = args[0]; let link = args[1]
        guard let targetURL = context.fs.resolve(target),
              let linkURL = context.fs.resolve(link) else {
            context.stderr("ln: cannot resolve paths\n"); return 1
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        // iOS sandbox doesn't allow hard/symlinks across sandbox boundaries.
        // Best effort: copy.
        do {
            if FileManager.default.fileExists(atPath: linkURL.path) {
                try FileManager.default.removeItem(at: linkURL)
            }
            try FileManager.default.copyItem(at: targetURL, to: linkURL)
            context.stdout("ln: created \(link) -> \(target) (copy)\n")
            return 0
        } catch {
            context.stderr("ln: \(error.localizedDescription)\n")
            return 1
        }
    }
}

/// `chmod` info / `lsmod` style: `info` - show system info.
struct InfoCommand: BuiltinCommand {
    let name = "info"
    let summary = "Show Termious system information"
    let usage = "info"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("Termious 1.0 - sandboxed iOS terminal\n\n")
        context.stdout("Device:   \(UIDevice.current.model)\n")
        context.stdout("Name:     \(UIDevice.current.name)\n")
        context.stdout("iOS:      \(UIDevice.current.systemVersion)\n")
        context.stdout("Shell:    /bin/termious (custom)\n")
        context.stdout("Root:     \(context.fs.logicalPath(of: context.fs.rootURL))\n")
        context.stdout("CWD:      \(context.fs.cwd)\n")
        let pkgs = AeroPackageManager.shared.listInstalled()
        context.stdout("Packages: \(pkgs.count) installed (use 'aero list')\n")
        context.stdout("Sudo:     \(SudoSession.shared.isAuthenticated ? "active" : "inactive")\n")
        context.stdout("\nUse 'help' for command list.\n")
        return 0
    }
}

/// `watch` - re-run a command periodically (limited iterations).
struct WatchCommand: BuiltinCommand {
    let name = "watch"
    let summary = "Execute a command periodically"
    let usage = "watch [-n seconds] <command...>"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var interval = 2.0
        var cmd: [String] = []
        var i = 0
        while i < arguments.count {
            if arguments[i] == "-n" && i + 1 < arguments.count {
                interval = Double(arguments[i + 1]) ?? 2.0; i += 2
            } else { cmd.append(arguments[i]); i += 1 }
        }
        if cmd.isEmpty { context.stderr("watch: missing command\n"); return 1 }
        let cmdLine = cmd.joined(separator: " ")
        context.stdout("\u{001B}]WATCH\u{0007}\(interval)|\(cmdLine)\u{0007}")
        return 0
    }
}

/// `reboot` / `reload` - restart the shell session.
struct RebootCommand: BuiltinCommand {
    let name = "reboot"
    let summary = "Restart the shell session"
    let usage = "reboot"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("\u{001B}]REBOOT\u{0007}")
        return 0
    }
}

/// `credits` / `about` - show credits.
struct CreditsCommand: BuiltinCommand {
    let name = "credits"
    let summary = "Show credits"
    let usage = "credits"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("Termious - a sandboxed terminal for iOS\n")
        context.stdout("Custom shell, aero package manager, virtual file system.\n\n")
        context.stdout("Built with Swift and UIKit.\n")
        return 0
    }
}

/// `history` handled by UI. `colors` - test ANSI colors.
struct ColorsCommand: BuiltinCommand {
    let name = "colors"
    let summary = "Test ANSI color output"
    let usage = "colors"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let names = ["30 (black)", "31 (red)", "32 (green)", "33 (yellow)",
                     "34 (blue)", "35 (magenta)", "36 (cyan)", "37 (white)"]
        for (i, name) in names.enumerated() {
            let code = 30 + i
            context.stdout("\u{001B}[\(code)mANSI \(name)\u{001B}[0m\n")
        }
        return 0
    }
}