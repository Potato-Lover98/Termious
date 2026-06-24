import Foundation
import CryptoKit
import UIKit
import os.log

/// `tee` - read from stdin and write to stdout and files.
/// Usage: tee [-a] file...
struct TeeCommand: BuiltinCommand {
    let name = "tee"
    let summary = "Read stdin and write to stdout and files"
    let usage = "tee [-a] file..."
    var operands: [Operand] {[
        Operand(name: "file", description: "File(s) to write to (use -a to append)", required: true, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var append = false
        var files: [String] = []
        for a in arguments {
            if a == "-a" { append = true }
            else if a.hasPrefix("-") {
                for f in a.dropFirst() { if f == "a" { append = true } }
            } else { files.append(a) }
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let data = context.stdin
        context.stdout(data)
        for f in files {
            guard let url = context.fs.resolve(f) else { continue }
            let bytes = Data(data.utf8)
            if append && FileManager.default.fileExists(atPath: url.path) {
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(bytes)
                    handle.closeFile()
                }
            } else {
                try? bytes.write(to: url)
            }
        }
        return 0
    }
}

/// `xargs` - build arguments from stdin and run a command.
/// Usage: xargs [-n N] [-I {}] [command [initial-args...]]
struct XargsCommand: BuiltinCommand {
    let name = "xargs"
    let summary = "Build arguments from stdin and execute a command"
    let usage = "xargs [-n N] [-I {}] [command [args...]]"
    var operands: [Operand] {[
        Operand(name: "command", description: "Command to run with stdin args (defaults to echo)", required: false, type: .string),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var maxArgs = 0
        var placeholder: String? = nil
        var cmdArgs: [String] = []
        var i = 0
        while i < arguments.count {
            let a = arguments[i]
            if a == "-n" && i + 1 < arguments.count {
                maxArgs = Int(arguments[i + 1]) ?? 0; i += 2
            } else if a.hasPrefix("-n") {
                maxArgs = Int(a.dropFirst(2)) ?? 0; i += 1
            } else if a == "-I" && i + 1 < arguments.count {
                placeholder = arguments[i + 1]; i += 2
            } else if a.hasPrefix("-I") {
                placeholder = String(a.dropFirst(2)); i += 1
            } else { cmdArgs.append(a); i += 1 }
        }
        let cmdName = cmdArgs.first ?? "echo"
        let baseArgs = Array(cmdArgs.dropFirst())
        let items = context.stdin.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if items.isEmpty { return 0 }

        if let ph = placeholder {
            for item in items {
                var args = baseArgs.map { $0.replacingOccurrences(of: ph, with: item) }
                if !baseArgs.contains(where: { $0.contains(ph) }) { args.append(item) }
                emit(cmdName, args, context)
            }
            return 0
        }
        if maxArgs > 0 {
            var idx = 0
            while idx < items.count {
                let chunk = Array(items[idx..<(min(idx + maxArgs, items.count))])
                emit(cmdName, baseArgs + chunk, context)
                idx += maxArgs
            }
        } else {
            emit(cmdName, baseArgs + items, context)
        }
        return 0
    }

    private func emit(_ cmd: String, _ args: [String], _ context: CommandContext) {
        context.stdout("\u{001B}]XARGS\u{0007}\(cmd) \(args.joined(separator: " "))\u{0007}")
    }
}

/// `printf` - format and print data.
/// Usage: printf <format> [args...]
struct PrintfCommand: BuiltinCommand {
    let name = "printf"
    let summary = "Format and print data"
    let usage = "printf <format> [args...]"
    var operands: [Operand] {[
        Operand(name: "format", description: "Format string with %s %d %f etc.", required: true, type: .string),
        Operand(name: "args", description: "Arguments for the format string", required: false, type: .string),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let format = arguments.first else {
            context.stderr("printf: missing format\n"); return 1
        }
        let args = Array(arguments.dropFirst())
        var result = ""
        var argIdx = 0
        var i = format.startIndex
        while i < format.endIndex {
            let c = format[i]
            if c == "\\" {
                let next = format.index(after: i)
                if next < format.endIndex {
                    let n = format[next]
                    switch n {
                    case "n": result.append("\n")
                    case "t": result.append("\t")
                    case "r": result.append("\r")
                    case "\\": result.append("\\")
                    case "0": result.append("\0")
                    default: result.append(n)
                    }
                    i = format.index(after: next)
                    continue
                }
            }
            if c == "%" {
                let next = format.index(after: i)
                if next < format.endIndex {
                    let n = format[next]
                    switch n {
                    case "s": result.append(argIdx < args.count ? args[argIdx] : ""); argIdx += 1
                    case "d", "i":
                        let val = Int(argIdx < args.count ? args[argIdx] : "0") ?? 0
                        result.append(String(val)); argIdx += 1
                    case "f":
                        let val = Double(argIdx < args.count ? args[argIdx] : "0") ?? 0.0
                        result.append(String(val)); argIdx += 1
                    case "x":
                        let val = Int(argIdx < args.count ? args[argIdx] : "0") ?? 0
                        result.append(String(val, radix: 16)); argIdx += 1
                    case "o":
                        let val = Int(argIdx < args.count ? args[argIdx] : "0") ?? 0
                        result.append(String(val, radix: 8)); argIdx += 1
                    case "%": result.append("%")
                    default: result.append("%"); result.append(n)
                    }
                    i = format.index(after: next)
                    continue
                }
            }
            result.append(c)
            i = format.index(after: i)
        }
        context.stdout(result)
        return 0
    }
}

/// `test` / `[` - evaluate conditional expressions.
/// Usage: test <expr>  |  [ <expr> ]
struct TestCommand: BuiltinCommand {
    let name = "test"
    let summary = "Evaluate a conditional expression"
    let usage = "test <expr> | [ <expr> ]"
    var operands: [Operand] {[
        Operand(name: "expr", description: "Expression like -f file, a = b, -z str", required: true, type: .string),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var args = arguments
        // Support `[ ... ]` form (last arg should be `]`)
        if args.last == "]" { args.removeLast() }
        if args.isEmpty { return 1 }

        // File tests
        if args.count == 2 && args[0].hasPrefix("-") {
            let flag = args[1]
            guard let url = context.fs.resolve(args[1]) else { return 1 }
            let started = context.fs.startRootAccess()
            defer { if started { context.fs.stopRootAccess() } }
            let fm = FileManager.default
            let exists = fm.fileExists(atPath: url.path)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            switch args[0] {
            case "-e": return exists ? 0 : 1
            case "-f": return (exists && !isDir.boolValue) ? 0 : 1
            case "-d": return (exists && isDir.boolValue) ? 0 : 1
            case "-s":
                if exists, let attrs = try? fm.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? Int, size > 0 { return 0 }
                return 1
            case "-r": return exists ? 0 : 1
            case "-w": return exists ? 0 : 1
            case "-x":
                let meta = FileMetadataStore.shared.get(context.fs.logicalPath(of: url))
                let perms = Int(meta.permissions, radix: 8) ?? 0
                return (perms & 1) != 0 ? 0 : 1
            default: break
            }
            _ = flag
        }

        // String comparisons: -z, -n, =, !=
        if args.count == 2 && args[0] == "-z" { return args[1].isEmpty ? 0 : 1 }
        if args.count == 2 && args[0] == "-n" { return !args[1].isEmpty ? 0 : 1 }

        if args.count == 3 {
            let a = args[0]; let op = args[1]; let b = args[2]
            switch op {
            case "=": return a == b ? 0 : 1
            case "!=": return a != b ? 0 : 1
            case "==": return a == b ? 0 : 1
            case "-eq": return (Int(a) ?? 0) == (Int(b) ?? 0) ? 0 : 1
            case "-ne": return (Int(a) ?? 0) != (Int(b) ?? 0) ? 0 : 1
            case "-lt": return (Int(a) ?? 0) < (Int(b) ?? 0) ? 0 : 1
            case "-le": return (Int(a) ?? 0) <= (Int(b) ?? 0) ? 0 : 1
            case "-gt": return (Int(a) ?? 0) > (Int(b) ?? 0) ? 0 : 1
            case "-ge": return (Int(a) ?? 0) >= (Int(b) ?? 0) ? 0 : 1
            default: break
            }
        }
        // Single arg: true if non-empty
        if args.count == 1 { return args[0].isEmpty ? 1 : 0 }
        return 1
    }
}

/// `expr` - evaluate expressions.
/// Usage: expr <arg1> <op> <arg2>
struct ExprCommand: BuiltinCommand {
    let name = "expr"
    let summary = "Evaluate arithmetic expressions"
    let usage = "expr <arg1> <op> <arg2>"
    var operands: [Operand] {[
        Operand(name: "arg1", description: "First operand", required: true, type: .string),
        Operand(name: "op", description: "Operator: + - * / % = != < >", required: true, type: .string),
        Operand(name: "arg2", description: "Second operand", required: true, type: .string),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        if arguments.count == 1 {
            context.stdout(arguments[0] + "\n")
            return 0
        }
        if arguments.count == 3 {
            let a = arguments[0]; let op = arguments[1]; let b = arguments[2]
            if let x = Int(a), let y = Int(b) {
                let result: Int
                switch op {
                case "+": result = x + y
                case "-": result = x - y
                case "*": result = x * y
                case "/": result = y == 0 ? 0 : x / y
                case "%": result = y == 0 ? 0 : x % y
                default:
                    // String comparison
                    switch op {
                    case "=": context.stdout((a == b ? "1" : "0") + "\n"); return a == b ? 0 : 1
                    case "!=": context.stdout((a != b ? "1" : "0") + "\n"); return a != b ? 0 : 1
                    case "<": context.stdout((a < b ? "1" : "0") + "\n"); return a < b ? 0 : 1
                    case ">": context.stdout((a > b ? "1" : "0") + "\n"); return a > b ? 0 : 1
                    default: context.stderr("expr: invalid operator\n"); return 2
                    }
                }
                context.stdout("\(result)\n")
                return result == 0 ? 1 : 0
            }
        }
        context.stderr("expr: syntax error\n")
        return 2
    }
}

/// `bc` - basic calculator.
/// Usage: echo "1+2" | bc  |  bc "1+2*3"
struct BcCommand: BuiltinCommand {
    let name = "bc"
    let summary = "Basic calculator"
    let usage = "bc [expression]"
    var operands: [Operand] {[
        Operand(name: "expression", description: "Math expression like 1+2*3 (defaults to stdin)", required: false, type: .string),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let input: String
        if !arguments.isEmpty {
            input = arguments.joined(separator: " ")
        } else {
            input = context.stdin.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let result = evaluate(input)
        context.stdout(result + "\n")
        return 0
    }

    private func evaluate(_ expr: String) -> String {
        let cleaned = expr.replacingOccurrences(of: " ", with: "")
        return String(evalExpr(cleaned) ?? 0)
    }

    private func evalExpr(_ s: String) -> Double? {
        var idx = s.startIndex
        return parseExpr(s, &idx)
    }

    private func parseExpr(_ s: String, _ idx: inout String.Index) -> Double? {
        var value = parseTerm(s, &idx) ?? 0
        while idx < s.endIndex {
            let op = s[idx]
            if op == "+" {
                idx = s.index(after: idx)
                value += parseTerm(s, &idx) ?? 0
            } else if op == "-" {
                idx = s.index(after: idx)
                value -= parseTerm(s, &idx) ?? 0
            } else { break }
        }
        return value
    }

    private func parseTerm(_ s: String, _ idx: inout String.Index) -> Double? {
        var value = parseFactor(s, &idx) ?? 0
        while idx < s.endIndex {
            let op = s[idx]
            if op == "*" {
                idx = s.index(after: idx)
                value *= parseFactor(s, &idx) ?? 0
            } else if op == "/" {
                idx = s.index(after: idx)
                let d = parseFactor(s, &idx) ?? 0
                value = d == 0 ? 0 : value / d
            } else if op == "%" {
                idx = s.index(after: idx)
                let d = parseFactor(s, &idx) ?? 0
                value = d == 0 ? 0 : value.truncatingRemainder(dividingBy: d)
            } else { break }
        }
        return value
    }

    private func parseFactor(_ s: String, _ idx: inout String.Index) -> Double? {
        if idx >= s.endIndex { return nil }
        if s[idx] == "(" {
            idx = s.index(after: idx)
            let value = parseExpr(s, &idx) ?? 0
            if idx < s.endIndex, s[idx] == ")" { idx = s.index(after: idx) }
            return value
        }
        var num = ""
        while idx < s.endIndex, s[idx].isNumber || s[idx] == "." {
            num.append(s[idx])
            idx = s.index(after: idx)
        }
        return Double(num)
    }
}

/// `cal` - display a calendar.
/// Usage: cal [[month] year]
struct CalCommand: BuiltinCommand {
    let name = "cal"
    let summary = "Display a calendar"
    let usage = "cal [[month] year]"
    var operands: [Operand] {[
        Operand(name: "month", description: "Month number 1-12 (optional)", required: false, type: .number),
        Operand(name: "year", description: "Year number", required: false, type: .number),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let now = Date()
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "UTC") ?? TimeZone.current
        let comps = cal.dateComponents([.year, .month], from: now)
        var year = comps.year ?? 2026
        var month = comps.month ?? 1

        if arguments.count == 1 {
            year = Int(arguments[0]) ?? year
        } else if arguments.count >= 2 {
            month = Int(arguments[0]) ?? month
            year = Int(arguments[1]) ?? year
        }

        guard month >= 1 && month <= 12 else {
            context.stderr("cal: invalid month\n"); return 1
        }

        let months = ["", "January", "February", "March", "April", "May", "June",
                      "July", "August", "September", "October", "November", "December"]
        context.stdout("    \(months[month]) \(year)\n")
        context.stdout("Su Mo Tu We Th Fr Sa\n")

        var firstComps = DateComponents()
        firstComps.year = year
        firstComps.month = month
        firstComps.day = 1
        guard let firstDay = cal.date(from: firstComps) else { return 1 }
        let weekday = cal.component(.weekday, from: firstDay)
        let daysInMonth = cal.range(of: .day, in: .month, for: firstDay)?.count ?? 30

        var line = String(repeating: "   ", count: weekday - 1)
        for day in 1...daysInMonth {
            line += String(format: "%2d ", day)
            if (day + weekday - 1) % 7 == 0 || day == daysInMonth {
                context.stdout(line.trimmingCharacters(in: CharacterSet(charactersIn: " ")) + "\n")
                line = ""
            }
        }
        return 0
    }
}

/// `shuf` - generate random permutations.
/// Usage: shuf [-n N] [file]  |  echo "a b c" | shuf
struct ShufCommand: BuiltinCommand {
    let name = "shuf"
    let summary = "Shuffle input lines"
    let usage = "shuf [-n N] [file]"
    var operands: [Operand] {[
        Operand(name: "file", description: "File to shuffle (defaults to stdin)", required: false, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var limit = 0
        var paths: [String] = []
        for a in arguments {
            if a == "-n" { /* needs next arg */ }
            else if a.hasPrefix("-n") { limit = Int(a.dropFirst(2)) ?? 0 }
            else if !a.hasPrefix("-") { paths.append(a) }
        }
        var n = 0
        for (i, a) in arguments.enumerated() {
            if a == "-n" && i + 1 < arguments.count {
                n = Int(arguments[i + 1]) ?? 0; limit = n
            }
        }
        let input: String
        if let p = paths.first {
            let started = context.fs.startRootAccess()
            if let url = context.fs.resolve(p),
               let data = try? Data(contentsOf: url),
               let s = String(data: data, encoding: .utf8) {
                input = s
            } else { input = context.stdin }
            if started { context.fs.stopRootAccess() }
        } else { input = context.stdin }
        var lines = input.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines.shuffle()
        if limit > 0 { lines = Array(lines.prefix(limit)) }
        for line in lines { context.stdout(line + "\n") }
        return 0
    }
}

/// `factor` - print prime factors.
/// Usage: factor <number...>
struct FactorCommand: BuiltinCommand {
    let name = "factor"
    let summary = "Print prime factors of numbers"
    let usage = "factor <number...>"
    var operands: [Operand] {[
        Operand(name: "number", description: "Number(s) to factorize", required: true, type: .number),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        for arg in arguments {
            guard let n = Int(arg), n > 0 else {
                context.stderr("factor: '\(arg)' is not a valid positive integer\n")
                continue
            }
            var factors: [Int] = []
            var num = n
            var d = 2
            while d * d <= num {
                while num % d == 0 { factors.append(d); num /= d }
                d += d == 2 ? 1 : 2
            }
            if num > 1 { factors.append(num) }
            context.stdout("\(n): " + factors.map(String.init).joined(separator: " ") + "\n")
        }
        return 0
    }
}

/// `comm` - compare two sorted files line by line.
/// Usage: comm [-123] file1 file2
struct CommCommand: BuiltinCommand {
    let name = "comm"
    let summary = "Compare two sorted files line by line"
    let usage = "comm [-123] file1 file2"
    var operands: [Operand] {[
        Operand(name: "file1", description: "First sorted file", required: true, type: .file),
        Operand(name: "file2", description: "Second sorted file", required: true, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var suppress1 = false, suppress2 = false, suppress3 = false
        var files: [String] = []
        for a in arguments {
            if a.hasPrefix("-") {
                for f in a.dropFirst() {
                    if f == "1" { suppress1 = true }
                    else if f == "2" { suppress2 = true }
                    else if f == "3" { suppress3 = true }
                }
            } else { files.append(a) }
        }
        guard files.count >= 2 else {
            context.stderr("comm: need two files\n"); return 1
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        func readLines(_ path: String) -> [String] {
            guard let url = context.fs.resolve(path),
                  let data = try? Data(contentsOf: url),
                  let s = String(data: data, encoding: .utf8) else { return [] }
            return s.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        }
        let a = readLines(files[0])
        let b = readLines(files[1])
        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count && (j >= b.count || a[i] < b[j]) {
                if !suppress1 { context.stdout("      \(a[i])\n") }
                i += 1
            } else if j < b.count && (i >= a.count || a[i] > b[j]) {
                if !suppress2 { context.stdout("            \(b[j])\n") }
                j += 1
            } else {
                if !suppress3 { context.stdout("            \(a[i])\n") }
                i += 1; j += 1
            }
        }
        return 0
    }
}

/// `join` - join lines of two sorted files on a common field.
/// Usage: join file1 file2
struct JoinCommand: BuiltinCommand {
    let name = "join"
    let summary = "Join lines of two files on first field"
    let usage = "join file1 file2"
    var operands: [Operand] {[
        Operand(name: "file1", description: "First file to join", required: true, type: .file),
        Operand(name: "file2", description: "Second file to join", required: true, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard arguments.count >= 2 else {
            context.stderr("join: need two files\n"); return 1
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        func readLines(_ path: String) -> [[String]] {
            guard let url = context.fs.resolve(path),
                  let data = try? Data(contentsOf: url),
                  let s = String(data: data, encoding: .utf8) else { return [] }
            return s.split(separator: "\n").map { $0.split(separator: " ", omittingEmptySubsequences: true).map(String.init) }
        }
        let a = readLines(arguments[0])
        let b = readLines(arguments[1])
        var i = 0, j = 0
        while i < a.count && j < b.count {
            let ka = a[i].first ?? ""
            let kb = b[j].first ?? ""
            if ka == kb {
                let rest = Array(a[i].dropFirst()) + Array(b[j].dropFirst())
                context.stdout(([ka] + rest).joined(separator: " ") + "\n")
                i += 1; j += 1
            } else if ka < kb { i += 1 } else { j += 1 }
        }
        return 0
    }
}

/// `fmt` - simple text formatter (word-wrap to width).
/// Usage: fmt [-w width] [file]
struct FmtCommand: BuiltinCommand {
    let name = "fmt"
    let summary = "Reformat paragraph text"
    let usage = "fmt [-w width] [file]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var width = 75
        var paths: [String] = []
        for a in arguments {
            if a == "-w" { /* needs next */ }
            else if a.hasPrefix("-w") { width = Int(a.dropFirst(2)) ?? 75 }
            else if !a.hasPrefix("-") { paths.append(a) }
        }
        for (i, a) in arguments.enumerated() {
            if a == "-w" && i + 1 < arguments.count {
                width = Int(arguments[i + 1]) ?? 75
            }
        }
        let input: String
        if let p = paths.first {
            let started = context.fs.startRootAccess()
            if let url = context.fs.resolve(p),
               let data = try? Data(contentsOf: url),
               let s = String(data: data, encoding: .utf8) {
                input = s
            } else { input = context.stdin }
            if started { context.fs.stopRootAccess() }
        } else { input = context.stdin }
        let words = input.split(whereSeparator: { $0.isWhitespace })
        var line = ""
        for word in words {
            if line.count + word.count + 1 > width {
                context.stdout(line + "\n")
                line = String(word)
            } else {
                line += line.isEmpty ? String(word) : " " + String(word)
            }
        }
        if !line.isEmpty { context.stdout(line + "\n") }
        return 0
    }
}

/// `fold` - fold lines to width.
/// Usage: fold [-w width] [file]
struct FoldCommand: BuiltinCommand {
    let name = "fold"
    let summary = "Fold each line to a specified width"
    let usage = "fold [-w width] [file]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var width = 80
        var paths: [String] = []
        for a in arguments {
            if a.hasPrefix("-w") { width = Int(a.dropFirst(2)) ?? 80 }
            else if !a.hasPrefix("-") { paths.append(a) }
        }
        for (i, a) in arguments.enumerated() {
            if a == "-w" && i + 1 < arguments.count { width = Int(arguments[i + 1]) ?? 80 }
        }
        let input: String
        if let p = paths.first {
            let started = context.fs.startRootAccess()
            if let url = context.fs.resolve(p),
               let data = try? Data(contentsOf: url),
               let s = String(data: data, encoding: .utf8) {
                input = s
            } else { input = context.stdin }
            if started { context.fs.stopRootAccess() }
        } else { input = context.stdin }
        for line in input.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            var i = 0
            while i < s.count {
                let end = min(i + width, s.count)
                let startIdx = s.index(s.startIndex, offsetBy: i)
                let endIdx = s.index(s.startIndex, offsetBy: end)
                context.stdout(String(s[startIdx..<endIdx]) + "\n")
                i += width
            }
        }
        return 0
    }
}

/// `expand` - convert tabs to spaces.
/// Usage: expand [-t N] [file]
struct ExpandCommand: BuiltinCommand {
    let name = "expand"
    let summary = "Convert tabs to spaces"
    let usage = "expand [-t N] [file]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var tabSize = 8
        var paths: [String] = []
        for a in arguments {
            if a.hasPrefix("-t") { tabSize = Int(a.dropFirst(2)) ?? 8 }
            else if !a.hasPrefix("-") { paths.append(a) }
        }
        for (i, a) in arguments.enumerated() {
            if a == "-t" && i + 1 < arguments.count { tabSize = Int(arguments[i + 1]) ?? 8 }
        }
        let input: String
        if let p = paths.first {
            let started = context.fs.startRootAccess()
            if let url = context.fs.resolve(p),
               let data = try? Data(contentsOf: url),
               let s = String(data: data, encoding: .utf8) {
                input = s
            } else { input = context.stdin }
            if started { context.fs.stopRootAccess() }
        } else { input = context.stdin }
        for line in input.split(separator: "\n", omittingEmptySubsequences: false) {
            context.stdout(String(line).replacingOccurrences(of: "\t", with: String(repeating: " ", count: tabSize)) + "\n")
        }
        return 0
    }
}

/// `column` - columnate lists.
/// Usage: column [-t -s sep] [file]
struct ColumnCommand: BuiltinCommand {
    let name = "column"
    let summary = "Columnate a list"
    let usage = "column [-t -s sep] [file]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var table = false
        var sep: String = " "
        var paths: [String] = []
        var i = 0
        while i < arguments.count {
            let a = arguments[i]
            if a == "-t" { table = true; i += 1 }
            else if a == "-s" && i + 1 < arguments.count { sep = arguments[i + 1]; i += 2 }
            else if !a.hasPrefix("-") { paths.append(a); i += 1 }
            else { i += 1 }
        }
        let input: String
        if let p = paths.first {
            let started = context.fs.startRootAccess()
            if let url = context.fs.resolve(p),
               let data = try? Data(contentsOf: url),
               let s = String(data: data, encoding: .utf8) {
                input = s
            } else { input = context.stdin }
            if started { context.fs.stopRootAccess() }
        } else { input = context.stdin }
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false)
        if !table {
            context.stdout(lines.joined(separator: "  ") + "\n")
            return 0
        }
        let rows = lines.map { $0.components(separatedBy: sep).filter { !$0.isEmpty } }
        let maxCols = rows.map { $0.count }.max() ?? 0
        var widths = Array(repeating: 0, count: maxCols)
        for row in rows {
            for (i, cell) in row.enumerated() where i < maxCols {
                widths[i] = max(widths[i], cell.count)
            }
        }
        for row in rows {
            var line = ""
            for (i, cell) in row.enumerated() where i < maxCols {
                line += cell.padding(toLength: widths[i] + 2, withPad: " ", startingAt: 0)
            }
            context.stdout(line.trimmingCharacters(in: .whitespaces) + "\n")
        }
        return 0
    }
}

/// `tsort` - topological sort.
/// Usage: tsort [file]
struct TsortCommand: BuiltinCommand {
    let name = "tsort"
    let summary = "Topological sort of a directed graph"
    let usage = "tsort [file]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let input: String
        if let p = arguments.first {
            let started = context.fs.startRootAccess()
            if let url = context.fs.resolve(p),
               let data = try? Data(contentsOf: url),
               let s = String(data: data, encoding: .utf8) {
                input = s
            } else { input = context.stdin }
            if started { context.fs.stopRootAccess() }
        } else { input = context.stdin }
        let pairs = input.split(whereSeparator: { $0.isWhitespace })
        var graph: [String: Set<String>] = [:]
        var inDegree: [String: Int] = [:]
        for i in stride(from: 0, to: pairs.count - 1, by: 2) {
            let a = String(pairs[i]); let b = String(pairs[i + 1])
            if a != b {
                graph[a, default: []].insert(b)
                inDegree[b, default: 0] += 1
                inDegree[a, default: 0]
            }
        }
        var queue = inDegree.filter { $0.value == 0 }.keys.sorted()
        var result: [String] = []
        while !queue.isEmpty {
            let node = queue.removeFirst()
            result.append(node)
            for neighbor in graph[node] ?? [] {
                inDegree[neighbor, default: 0] -= 1
                if inDegree[neighbor] == 0 { queue.append(neighbor); queue.sort() }
            }
        }
        for n in result { context.stdout(n + "\n") }
        return 0
    }
}

/// `split` - split a file into pieces.
/// Usage: split [-l lines] [-b bytes] file [prefix]
struct SplitCommand: BuiltinCommand {
    let name = "split"
    let summary = "Split a file into pieces"
    let usage = "split [-l lines] file [prefix]"
    var operands: [Operand] {[
        Operand(name: "file", description: "File to split", required: true, type: .file),
        Operand(name: "prefix", description: "Output filename prefix (defaults to x)", required: false, type: .string),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var lineCount = 1000
        var paths: [String] = []
        var i = 0
        while i < arguments.count {
            let a = arguments[i]
            if a == "-l" && i + 1 < arguments.count {
                lineCount = Int(arguments[i + 1]) ?? 1000; i += 2
            } else if a.hasPrefix("-l") {
                lineCount = Int(a.dropFirst(2)) ?? 1000; i += 1
            } else if !a.hasPrefix("-") {
                paths.append(a); i += 1
            } else { i += 1 }
        }
        guard let inputFile = paths.first else {
            context.stderr("split: missing file\n"); return 1
        }
        let prefix = paths.count > 1 ? paths[1] : "x"
        guard let url = context.fs.resolve(inputFile),
              let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8) else {
            context.stderr("split: cannot read file\n"); return 1
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        var fileNum = 0
        var idx = 0
        while idx < lines.count {
            let end = min(idx + lineCount, lines.count)
            let chunk = lines[idx..<end].joined(separator: "\n")
            let name = String(format: "\(prefix)%02d", fileNum)
            if let outURL = context.fs.resolve(name) {
                try? Data((chunk + "\n").utf8).write(to: outURL)
            }
            context.stdout("Created \(name) (\(end - idx) lines)\n")
            idx += lineCount
            fileNum += 1
        }
        return 0
    }
}

/// `dd` - convert and copy files (basic).
/// Usage: dd if=<input> of=<output> [bs=N] [count=N]
struct DdCommand: BuiltinCommand {
    let name = "dd"
    let summary = "Convert and copy files"
    let usage = "dd if=<input> of=<output> [bs=N] [count=N]"
    var operands: [Operand] {[
        Operand(name: "if", description: "Input file path (if=path)", required: true, type: .file),
        Operand(name: "of", description: "Output file path (of=path)", required: true, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var inputFile: String? = nil
        var outputFile: String? = nil
        var bs = 512
        var count = 0
        for a in arguments {
            let parts = a.split(separator: "=", maxSplits: 1)
            let key = String(parts[0]); let val = parts.count > 1 ? String(parts[1]) : ""
            switch key {
            case "if": inputFile = val
            case "of": outputFile = val
            case "bs": bs = Int(val) ?? 512
            case "count": count = Int(val) ?? 0
            default: break
            }
        }
        guard let input = inputFile, let output = outputFile,
              let inURL = context.fs.resolve(input),
              let outURL = context.fs.resolve(output),
              let data = try? Data(contentsOf: inURL) else {
            context.stderr("dd: invalid operands\n"); return 1
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let limit = count > 0 ? min(count * bs, data.count) : data.count
        let outData = data.prefix(limit)
        try? outData.write(to: outURL)
        context.stdout("\(outData.count) bytes copied\n")
        return 0
    }
}

/// `truncate` - shrink or extend a file to a size.
/// Usage: truncate -s <size> file...
struct TruncateCommand: BuiltinCommand {
    let name = "truncate"
    let summary = "Shrink or extend a file"
    let usage = "truncate -s <size> file..."
    var operands: [Operand] {[
        Operand(name: "size", description: "Target file size in bytes (with -s)", required: true, type: .number),
        Operand(name: "file", description: "File(s) to resize", required: true, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var size: Int? = nil
        var files: [String] = []
        for a in arguments {
            if a == "-s" { /* needs next */ }
            else if a.hasPrefix("-s") { size = Int(a.dropFirst(2)) }
            else if !a.hasPrefix("-") { files.append(a) }
        }
        for (i, a) in arguments.enumerated() {
            if a == "-s" && i + 1 < arguments.count { size = Int(arguments[i + 1]) }
        }
        guard let sz = size, !files.isEmpty else {
            context.stderr("truncate: need -s <size> and file(s)\n"); return 1
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        for f in files {
            guard let url = context.fs.resolve(f) else { continue }
            let fm = FileManager.default
            if fm.fileExists(atPath: url.path),
               let existing = try? Data(contentsOf: url) {
                if existing.count >= sz {
                    try? existing.prefix(sz).write(to: url)
                } else {
                    var grown = existing
                    grown.append(Data(repeating: 0, count: sz - existing.count))
                    try? grown.write(to: url)
                }
            } else {
                try? Data(repeating: 0, count: sz).write(to: url)
            }
        }
        return 0
    }
}

/// `mktemp` - create a temporary file or directory.
/// Usage: mktemp [-d] [template]
struct MktempCommand: BuiltinCommand {
    let name = "mktemp"
    let summary = "Create a temporary file or directory"
    let usage = "mktemp [-d] [template]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var makeDir = false
        var template = "tmp.XXXXXX"
        for a in arguments {
            if a == "-d" { makeDir = true }
            else if !a.hasPrefix("-") { template = a }
        }
        let suffix = String(UUID().uuidString.prefix(8))
        let name = template.replacingOccurrences(of: "XXXXXX", with: suffix)
        guard let url = context.fs.resolve(name) else {
            context.stderr("mktemp: cannot create\n"); return 1
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        if makeDir {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } else {
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        context.stdout(context.fs.logicalPath(of: url) + "\n")
        return 0
    }
}

/// `shred` - overwrite a file to hide its contents, then optionally delete.
/// Usage: shred [-u] [-n N] file...
struct ShredCommand: BuiltinCommand {
    let name = "shred"
    let summary = "Overwrite and optionally delete a file"
    let usage = "shred [-u] [-n N] file..."
    var operands: [Operand] {[
        Operand(name: "file", description: "File(s) to securely overwrite", required: true, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var remove = false
        var passes = 3
        var files: [String] = []
        var i = 0
        while i < arguments.count {
            let a = arguments[i]
            if a == "-u" { remove = true; i += 1 }
            else if a == "-n" && i + 1 < arguments.count { passes = Int(arguments[i + 1]) ?? 3; i += 2 }
            else if !a.hasPrefix("-") { files.append(a); i += 1 }
            else { i += 1 }
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        var hadError = false
        for f in files {
            guard let url = context.fs.resolve(f) else { hadError = true; continue }
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let size = attrs[.size] as? Int else { hadError = true; continue }
            for _ in 0..<passes {
                let random = Data((0..<size).map { _ in UInt8.random(in: 0...255) })
                try? random.write(to: url)
            }
            if remove { try? FileManager.default.removeItem(at: url) }
        }
        return hadError ? 1 : 0
    }
}

/// `install` - copy files and set attributes.
/// Usage: install [-m mode] [-o owner] source dest
struct InstallCommand: BuiltinCommand {
    let name = "install"
    let summary = "Copy files and set attributes"
    let usage = "install [-m mode] [-o owner] source dest"
    var operands: [Operand] {[
        Operand(name: "source", description: "Source file to copy", required: true, type: .file),
        Operand(name: "dest", description: "Destination path", required: true, type: .path),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var mode: String? = nil
        var owner: String? = nil
        var paths: [String] = []
        var i = 0
        while i < arguments.count {
            let a = arguments[i]
            if a == "-m" && i + 1 < arguments.count { mode = arguments[i + 1]; i += 2 }
            else if a == "-o" && i + 1 < arguments.count { owner = arguments[i + 1]; i += 2 }
            else if !a.hasPrefix("-") { paths.append(a); i += 1 }
            else { i += 1 }
        }
        guard paths.count >= 2 else {
            context.stderr("install: need source and dest\n"); return 1
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let dest = paths.removeLast()
        guard let destURL = context.fs.resolve(dest) else {
            context.stderr("install: cannot resolve dest\n"); return 1
        }
        for src in paths {
            guard let srcURL = context.fs.resolve(src) else { continue }
            if FileManager.default.fileExists(atPath: destURL.path) {
                try? FileManager.default.removeItem(at: destURL)
            }
            try? FileManager.default.copyItem(at: srcURL, to: destURL)
            let logical = context.fs.logicalPath(of: destURL)
            if let m = mode { FileMetadataStore.shared.update(logical, permissions: m) }
            if let o = owner { FileMetadataStore.shared.update(logical, owner: o) }
        }
        return 0
    }
}

/// `true` - do nothing, successfully.
struct TrueCommand: BuiltinCommand {
    let name = "true"
    let summary = "Do nothing, successfully"
    let usage = "true"
    func run(arguments: [String], context: CommandContext) -> Int32 { 0 }
}

/// `false` - do nothing, unsuccessfully.
struct FalseCommand: BuiltinCommand {
    let name = "false"
    let summary = "Do nothing, unsuccessfully"
    let usage = "false"
    func run(arguments: [String], context: CommandContext) -> Int32 { 1 }
}

/// `yes` (re-registered with limit) - keep as is.

/// `cal` already done. `look` - display lines beginning with prefix.
struct LookCommand: BuiltinCommand {
    let name = "look"
    let summary = "Display lines beginning with a prefix"
    let usage = "look <prefix> [file]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let prefix = arguments.first else { return 1 }
        let input: String
        if arguments.count > 1 {
            let started = context.fs.startRootAccess()
            if let url = context.fs.resolve(arguments[1]),
               let data = try? Data(contentsOf: url),
               let s = String(data: data, encoding: .utf8) {
                input = s
            } else { input = context.stdin }
            if started { context.fs.stopRootAccess() }
        } else { input = context.stdin }
        for line in input.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(prefix) { context.stdout(String(line) + "\n") }
        }
        return 0
    }
}

/// `cksum` - checksum and count bytes in a file.
struct CksumCommand: BuiltinCommand {
    let name = "cksum"
    let summary = "Compute CRC checksum and byte count"
    let usage = "cksum [file...]"
    var operands: [Operand] {[
        Operand(name: "file", description: "File(s) to checksum (defaults to stdin)", required: false, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let files = arguments.isEmpty ? ["-"] : arguments
        for f in files {
            let data: Data
            if f == "-" { data = Data(context.stdin.utf8) }
            else if let url = context.fs.resolve(f), let d = try? Data(contentsOf: url) { data = d }
            else { context.stderr("cksum: \(f): cannot read\n"); continue }
            let crc = crc32IEEE(data)
            context.stdout(String(format: "%d %d %@\n", crc, data.count, f == "-" ? "-" : f))
        }
        return 0
    }

    private func crc32IEEE(_ data: Data) -> UInt32 {
        var table: [UInt32] = []
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                if c & 1 != 0 { c = 0xEDB88320 ^ (c >> 1) } else { c >>= 1 }
            }
            table.append(c)
        }
        var crc: UInt32 = 0
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

/// `sum` - checksum and block count.
struct SumCommand: BuiltinCommand {
    let name = "sum"
    let summary = "Compute simple checksum and block count"
    let usage = "sum [file...]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let files = arguments.isEmpty ? ["-"] : arguments
        for f in files {
            let data: Data
            if f == "-" { data = Data(context.stdin.utf8) }
            else if let url = context.fs.resolve(f), let d = try? Data(contentsOf: url) { data = d }
            else { context.stderr("sum: \(f): cannot read\n"); continue }
            var checksum: UInt32 = 0
            for byte in data { checksum = (checksum &+ UInt32(byte)) & 0xFFFF }
            let blocks = (data.count + 511) / 512
            context.stdout("\(blocks) \(checksum) \(f == "-" ? "-" : f)\n")
        }
        return 0
    }
}

/// `sha1sum` - compute SHA1 hash.
struct Sha1sumCommand: BuiltinCommand {
    let name = "sha1sum"
    let summary = "Compute SHA1 hash of files"
    let usage = "sha1sum [file...]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let files = arguments.isEmpty ? ["-"] : arguments
        for f in files {
            let data: Data
            if f == "-" { data = Data(context.stdin.utf8) }
            else if let url = context.fs.resolve(f), let d = try? Data(contentsOf: url) { data = d }
            else { context.stderr("sha1sum: \(f): cannot read\n"); continue }
            let digest = Insecure.SHA1.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            context.stdout("\(hex)  \(f == "-" ? "-" : f)\n")
        }
        return 0
    }
}

/// `sha256sum` - compute SHA256 hash.
struct Sha256sumCommand: BuiltinCommand {
    let name = "sha256sum"
    let summary = "Compute SHA256 hash of files"
    let usage = "sha256sum [file...]"
    var operands: [Operand] {[
        Operand(name: "file", description: "File(s) to hash (defaults to stdin)", required: false, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let files = arguments.isEmpty ? ["-"] : arguments
        for f in files {
            let data: Data
            if f == "-" { data = Data(context.stdin.utf8) }
            else if let url = context.fs.resolve(f), let d = try? Data(contentsOf: url) { data = d }
            else { context.stderr("sha256sum: \(f): cannot read\n"); continue }
            let digest = SHA256.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            context.stdout("\(hex)  \(f == "-" ? "-" : f)\n")
        }
        return 0
    }
}

/// `sha512sum` - compute SHA512 hash.
struct Sha512sumCommand: BuiltinCommand {
    let name = "sha512sum"
    let summary = "Compute SHA512 hash of files"
    let usage = "sha512sum [file...]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let files = arguments.isEmpty ? ["-"] : arguments
        for f in files {
            let data: Data
            if f == "-" { data = Data(context.stdin.utf8) }
            else if let url = context.fs.resolve(f), let d = try? Data(contentsOf: url) { data = d }
            else { context.stderr("sha512sum: \(f): cannot read\n"); continue }
            let digest = SHA512.hash(data: data)
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            context.stdout("\(hex)  \(f == "-" ? "-" : f)\n")
        }
        return 0
    }
}

/// `base32` - base32 encode/decode.
struct Base32Command: BuiltinCommand {
    let name = "base32"
    let summary = "Base32 encode/decode"
    let usage = "base32 [-d] [file]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var decode = false
        var paths: [String] = []
        for a in arguments {
            if a == "-d" { decode = true }
            else if !a.hasPrefix("-") { paths.append(a) }
        }
        let input: String
        if let f = paths.first {
            let started = context.fs.startRootAccess()
            if let url = context.fs.resolve(f),
               let data = try? Data(contentsOf: url),
               let s = String(data: data, encoding: .utf8) { input = s }
            else { input = context.stdin }
            if started { context.fs.stopRootAccess() }
        } else { input = context.stdin }
        if decode {
            if let decoded = base32Decode(input.trimmingCharacters(in: .whitespacesAndNewlines)) {
                context.stdout(String(data: decoded, encoding: .utf8) ?? "[binary data]")
            } else { context.stderr("base32: invalid input\n"); return 1 }
        } else {
            context.stdout(base32Encode(Data(input.utf8)) + "\n")
        }
        return 0
    }

    private let alphabet: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    private func base32Encode(_ data: Data) -> String {
        var result = ""
        var bits = 0; var value = 0
        for byte in data {
            value = (value << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                bits -= 5
                result.append(alphabet[(value >> bits) & 0x1F])
            }
        }
        if bits > 0 {
            result.append(alphabet[(value << (5 - bits)) & 0x1F])
        }
        while result.count % 8 != 0 { result.append("=") }
        return result
    }

    private func base32Decode(_ str: String) -> Data? {
        var bits = 0; var value = 0
        var result = Data()
        for c in str {
            if c == "=" { break }
            guard let idx = alphabet.firstIndex(of: c) else { return nil }
            value = (value << 5) | idx
            bits += 5
            if bits >= 8 {
                bits -= 8
                result.append(UInt8((value >> bits) & 0xFF))
            }
        }
        return result
    }
}

/// `strings` - print printable strings in a binary file.
struct StringsCommand: BuiltinCommand {
    let name = "strings"
    let summary = "Print printable strings from a file"
    let usage = "strings [-n minlen] [file...]"
    var operands: [Operand] {[
        Operand(name: "file", description: "File(s) to extract strings from", required: true, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var minLen = 4
        var paths: [String] = []
        for a in arguments {
            if a == "-n" { /* next */ }
            else if a.hasPrefix("-n") { minLen = Int(a.dropFirst(2)) ?? 4 }
            else if !a.hasPrefix("-") { paths.append(a) }
        }
        for (i, a) in arguments.enumerated() {
            if a == "-n" && i + 1 < arguments.count { minLen = Int(arguments[i + 1]) ?? 4 }
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        for f in paths {
            guard let url = context.fs.resolve(f), let data = try? Data(contentsOf: url) else { continue }
            var current = ""
            for byte in data {
                if (0x20...0x7E).contains(byte) {
                    current.append(Character(UnicodeScalar(byte)))
                } else {
                    if current.count >= minLen { context.stdout(current + "\n") }
                    current = ""
                }
            }
            if current.count >= minLen { context.stdout(current + "\n") }
        }
        return 0
    }
}

/// `od` / `hexdump` / `xxd` - dump file in hex.
struct OdCommand: BuiltinCommand {
    let name = "od"
    let summary = "Dump file in octal/hex"
    let usage = "od [-x] [-A d] [file]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var hex = false
        var paths: [String] = []
        for a in arguments {
            if a == "-x" { hex = true }
            else if !a.hasPrefix("-") { paths.append(a) }
        }
        let input: String
        if let f = paths.first {
            let started = context.fs.startRootAccess()
            if let url = context.fs.resolve(f),
               let data = try? Data(contentsOf: url) {
                input = String(data: data, encoding: .isoLatin1) ?? ""
            } else { input = context.stdin }
            if started { context.fs.stopRootAccess() }
        } else { input = context.stdin }
        let bytes = [UInt8](input.utf8)
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + 16, bytes.count)
            let format = hex ? "%07x" : "%07o"
            context.stdout(String(format: format, offset) + "  ")
            for i in offset..<end {
                if hex { context.stdout(String(format: "%02x ", bytes[i])) }
                else { context.stdout(String(format: "%03o ", bytes[i])) }
            }
            context.stdout("\n")
            offset += 16
        }
        return 0
    }
}

/// `xxd` - hex dump with ASCII.
struct XxdCommand: BuiltinCommand {
    let name = "xxd"
    let summary = "Hex dump with ASCII view"
    let usage = "xxd [file]"
    var operands: [Operand] {[
        Operand(name: "file", description: "File to hex dump", required: false, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let input: String
        if let f = arguments.first {
            let started = context.fs.startRootAccess()
            if let url = context.fs.resolve(f),
               let data = try? Data(contentsOf: url) {
                input = String(data: data, encoding: .isoLatin1) ?? ""
            } else { input = context.stdin }
            if started { context.fs.stopRootAccess() }
        } else { input = context.stdin }
        let bytes = [UInt8](input.utf8)
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + 16, bytes.count)
            context.stdout(String(format: "%08x: ", offset))
            var hexPart = ""; var ascii = ""
            for i in offset..<end {
                hexPart += String(format: "%02x", bytes[i])
                if (i - offset) % 2 == 1 { hexPart += " " }
                ascii += (0x20...0x7E).contains(bytes[i]) ? String(Character(UnicodeScalar(bytes[i]))) : "."
            }
            let padding = (16 - (end - offset)) * 2 + ((16 - (end - offset)) / 2)
            context.stdout(hexPart + String(repeating: " ", count: padding) + " " + ascii + "\n")
            offset += 16
        }
        return 0
    }
}

/// `readlink` - print resolved symlink (returns the path as-is on iOS).
struct ReadlinkCommand: BuiltinCommand {
    let name = "readlink"
    let summary = "Print the target of a symbolic link"
    let usage = "readlink <path>"
    var operands: [Operand] {[
        Operand(name: "path", description: "Link path to resolve", required: true, type: .path),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        for p in arguments {
            if let url = context.fs.resolve(p) {
                context.stdout(context.fs.logicalPath(of: url) + "\n")
            } else {
                context.stderr("readlink: \(p): no such file\n"); return 1
            }
        }
        return 0
    }
}

/// `nproc` - print the number of available processors.
struct NprocCommand: BuiltinCommand {
    let name = "nproc"
    let summary = "Print the number of available processors"
    let usage = "nproc"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("\(ProcessInfo.processInfo.processorCount)\n")
        return 0
    }
}

/// `lscpu` - display CPU information.
struct LscpuCommand: BuiltinCommand {
    let name = "lscpu"
    let summary = "Display CPU architecture info"
    let usage = "lscpu"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let info = ProcessInfo.processInfo
        context.stdout("Architecture:     \(uname_machine())\n")
        context.stdout("CPU(s):           \(info.processorCount)\n")
        context.stdout("OS:               \(info.operatingSystemVersionString)\n")
        context.stdout("Model:            \(UIDevice.current.model)\n")
        context.stdout("System name:      \(info.hostName)\n")
        return 0
    }

    private func uname_machine() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.machine) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}

/// `getconf` - get configuration values.
struct GetconfCommand: BuiltinCommand {
    let name = "getconf"
    let summary = "Get system configuration values"
    let usage = "getconf <variable>"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let varName = arguments.first else {
            context.stderr("getconf: missing variable\n"); return 1
        }
        switch varName {
        case "PATH_MAX": context.stdout("\(Int(PATH_MAX))\n")
        case "NAME_MAX": context.stdout("255\n")
        case "OPEN_MAX": context.stdout("1024\n")
        case "CLK_TCK": context.stdout("100\n")
        case "LINE_MAX": context.stdout("4096\n")
        case "NGROUPS_MAX": context.stdout("16\n")
        case "_POSIX_VERSION": context.stdout("200809\n")
        default: context.stderr("getconf: unknown variable '\(varName)'\n"); return 1
        }
        return 0
    }
}

/// `umask` - set or print the file mode creation mask.
struct UmaskCommand: BuiltinCommand {
    let name = "umask"
    let summary = "Set or print the file mode creation mask"
    let usage = "umask [mode]"
    static var mask: UInt8 = 0o022

    func run(arguments: [String], context: CommandContext) -> Int32 {
        if let arg = arguments.first, let m = UInt8(arg, radix: 8) {
            UmaskCommand.mask = m
        } else {
            context.stdout(String(format: "%03o\n", UmaskCommand.mask))
        }
        return 0
    }
}

/// `ulimit` - set or print resource limits (informational on iOS).
struct UlimitCommand: BuiltinCommand {
    let name = "ulimit"
    let summary = "Print resource limits (informational)"
    let usage = "ulimit [-a]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        if arguments.contains("-a") {
            context.stdout("core file size        (blocks) unlimited\n")
            context.stdout("data seg size         (kbytes) unlimited\n")
            context.stdout("file size             (blocks) unlimited\n")
            context.stdout("open files                    1024\n")
            context.stdout("pipe size          (512 bytes) 8\n")
            context.stdout("stack size            (kbytes) 8192\n")
            context.stdout("cpu time             (seconds) unlimited\n")
            context.stdout("max user processes             256\n")
            context.stdout("virtual memory        (kbytes) unlimited\n")
        } else {
            context.stdout("unlimited\n")
        }
        return 0
    }
}

/// `tput` - terminal capability (limited: colors, cup, clear).
struct TputCommand: BuiltinCommand {
    let name = "tput"
    let summary = "Terminal capability operations"
    let usage = "tput <capability> [args]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let cap = arguments.first else { return 1 }
        switch cap {
        case "clear": context.stdout("\u{001B}[2J\u{001B}[H")
        case "colors": context.stdout("256\n")
        case "cols": context.stdout("80\n")
        case "lines": context.stdout("40\n")
        case "cup":
            if arguments.count >= 3 {
                context.stdout("\u{001B}[\(arguments[1]);\(arguments[2])H")
            }
        case "bold": context.stdout("\u{001B}[1m")
        case "sgr0": context.stdout("\u{001B}[0m")
        case "setaf":
            if arguments.count >= 2 { context.stdout("\u{001B}[3\(arguments[1])m") }
        case "setab":
            if arguments.count >= 2 { context.stdout("\u{001B}[4\(arguments[1])m") }
        default: break
        }
        return 0
    }
}

/// `stty` - terminal settings (informational).
struct SttyCommand: BuiltinCommand {
    let name = "stty"
    let summary = "Print or change terminal settings"
    let usage = "stty [-a]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        if arguments.contains("-a") || arguments.isEmpty {
            context.stdout("speed 38400 baud; rows 40; columns 80; line = 0;\n")
            context.stdout("intr = ^C; quit = ^\\; erase = ^?; kill = ^U; eof = ^D;\n")
            context.stdout("eol = <undef>; eol2 = <undef>; swtch = <undef>;\n")
        }
        return 0
    }
}

/// `apropos` / `whatis` - search command summaries.
struct AproposCommand: BuiltinCommand {
    let name = "apropos"
    let summary = "Search command summaries"
    let usage = "apropos <keyword>"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let query = arguments.joined(separator: " ").lowercased()
        if query.isEmpty { context.stderr("apropos: missing keyword\n"); return 1 }
        context.stdout("\u{001B}]APROPOS\u{0007}\(query)\u{0007}")
        return 0
    }
}

/// `type` - describe a command.
struct TypeCommand: BuiltinCommand {
    let name = "type"
    let summary = "Describe a command type"
    let usage = "type <command...>"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("\u{001B}]TYPE_CMD\u{0007}\(arguments.joined(separator: " "))\u{0007}")
        return 0
    }
}

/// `command` - identify or run a command.
struct CommandCommand: BuiltinCommand {
    let name = "command"
    let summary = "Identify or run a command"
    let usage = "command [-v] <name>"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        if arguments.first == "-v" {
            context.stdout("\u{001B}]TYPE_CMD\u{0007}\(arguments.dropFirst().joined(separator: " "))\u{0007}")
        } else {
            context.stdout("\u{001B}]XARGS\u{0007}\(arguments.joined(separator: " "))\u{0007}")
        }
        return 0
    }
}

/// `printenv` - print environment variables.
struct PrintenvCommand: BuiltinCommand {
    let name = "printenv"
    let summary = "Print environment variables"
    let usage = "printenv [VAR...]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        if arguments.isEmpty {
            for (k, v) in context.env.sorted(by: { $0.key < $1.key }) {
                context.stdout("\(k)=\(v)\n")
            }
        } else {
            for name in arguments {
                if let v = context.env[name] { context.stdout(v + "\n") }
                else { return 1 }
            }
        }
        return 0
    }
}

/// `unset` - unset environment variables.
struct UnsetCommand: BuiltinCommand {
    let name = "unset"
    let summary = "Unset environment variables"
    let usage = "unset <VAR...>"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        for name in arguments {
            context.stdout("\u{001B}]UNSET\u{0007}\(name)\u{0007}")
        }
        return 0
    }
}

/// `pushd` / `popd` / `dirs` - directory stack.
struct DirsCommand: BuiltinCommand {
    let name = "dirs"
    let summary = "Show the directory stack"
    let usage = "dirs [-c]"
    static var stack: [String] = []

    func run(arguments: [String], context: CommandContext) -> Int32 {
        if arguments.contains("-c") { DirsCommand.stack.removeAll(); return 0 }
        let display = (DirsCommand.stack + [context.fs.cwd]).joined(separator: " ")
        context.stdout(display + "\n")
        return 0
    }
}

/// `pushd` - push directory onto stack and cd.
struct PushdCommand: BuiltinCommand {
    let name = "pushd"
    let summary = "Push directory onto stack and cd"
    let usage = "pushd <dir>"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let dir = arguments.first else {
            if DirsCommand.stack.isEmpty { context.stderr("pushd: no other directory\n"); return 1 }
            let prev = DirsCommand.stack.removeLast()
            DirsCommand.stack.append(context.fs.cwd)
            let result = context.fs.changeDirectory(to: prev)
            if case .failure(let m) = result { context.stderr(m + "\n"); return 1 }
            return 0
        }
        DirsCommand.stack.append(context.fs.cwd)
        let result = context.fs.changeDirectory(to: dir)
        if case .failure(let m) = result { context.stderr(m + "\n"); return 1 }
        let display = (DirsCommand.stack + [context.fs.cwd]).joined(separator: " ")
        context.stdout(display + "\n")
        return 0
    }
}

/// `popd` - pop directory from stack and cd.
struct PopdCommand: BuiltinCommand {
    let name = "popd"
    let summary = "Pop directory from stack and cd"
    let usage = "popd"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let dir = DirsCommand.stack.popLast() else {
            context.stderr("popd: directory stack empty\n"); return 1
        }
        let result = context.fs.changeDirectory(to: dir)
        if case .failure(let m) = result { context.stderr(m + "\n"); return 1 }
        let display = (DirsCommand.stack + [context.fs.cwd]).joined(separator: " ")
        context.stdout(display + "\n")
        return 0
    }
}

/// `unalias` - remove an alias.
struct UnaliasCommand: BuiltinCommand {
    let name = "unalias"
    let summary = "Remove an alias"
    let usage = "unalias <name>"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        for name in arguments {
            context.stdout("\u{001B}]UNALIAS\u{0007}\(name)\u{0007}")
        }
        return 0
    }
}

/// `w` - show who is logged in and what they are doing.
struct WCommand: BuiltinCommand {
    let name = "w"
    let summary = "Show who is logged in"
    let usage = "w"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let user = SudoSession.shared.isAuthenticated ? "root" : "mobile"
        let elapsed = Int(Date().timeIntervalSince(UptimeCommand.startTime))
        context.stdout(" \(user)   tty1   \(String(format: "%02d:%02d:%02d", elapsed/3600, (elapsed%3600)/60, elapsed%60))   termious shell\n")
        return 0
    }
}

/// `users` - print logged-in users.
struct UsersCommand: BuiltinCommand {
    let name = "users"
    let summary = "Print logged-in users"
    let usage = "users"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout((SudoSession.shared.isAuthenticated ? "root" : "mobile") + "\n")
        return 0
    }
}

/// `last` - show last logins (simulated).
struct LastCommand: BuiltinCommand {
    let name = "last"
    let summary = "Show last logins"
    let usage = "last"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let user = SudoSession.shared.isAuthenticated ? "root" : "mobile"
        let dateStr = ISO8601DateFormatter().string(from: UptimeCommand.startTime)
            .replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "Z", with: "")
        context.stdout("\(user)    tty1         \(dateStr)   still logged in\n")
        return 0
    }
}

/// `dmesg` - print kernel ring buffer (simulated for iOS).
struct DmesgCommand: BuiltinCommand {
    let name = "dmesg"
    let summary = "Print boot diagnostic messages"
    let usage = "dmesg"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("[Termious] session started at \(ISO8601DateFormatter().string(from: UptimeCommand.startTime))\n")
        context.stdout("[Termious] iOS \(UIDevice.current.systemVersion) on \(UIDevice.current.model)\n")
        context.stdout("[Termious] virtual filesystem root: \(context.fs.logicalPath(of: context.fs.rootURL))\n")
        context.stdout("[Termious] \(AeroPackageManager.shared.listInstalled().count) aero packages installed\n")
        context.stdout("[Termious] \(ProcessInfo.processInfo.processorCount) CPU cores available\n")
        return 0
    }
}

/// `logger` - send a message to the system log.
struct LoggerCommand: BuiltinCommand {
    let name = "logger"
    let summary = "Send a message to the system log"
    let usage = "logger <message>"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let msg = arguments.joined(separator: " ")
        os_log("%{public}@", type: .info, msg)
        return 0
    }
}

/// `lsof` - list open files (simulated).
struct LsofCommand: BuiltinCommand {
    let name = "lsof"
    let summary = "List open files (simulated)"
    let usage = "lsof"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let user = SudoSession.shared.isAuthenticated ? "root" : "mobile"
        context.stdout("COMMAND   PID USER   FD   TYPE  DEVICE SIZE/OFF NODE NAME\n")
        context.stdout("termious    1 \(user)  cwd   DIR   aero      4096    2 \(context.fs.cwd)\n")
        context.stdout("termious    1 \(user)  rtd   DIR   aero      4096    2 /\n")
        context.stdout("termious    1 \(user)  txt   REG   aero   1048576    3 /bin/termious\n")
        context.stdout("termious    1 \(user)    1u   CHR   tty       1024    4 /dev/tty1\n")
        return 0
    }
}

/// `vmstat` - virtual memory statistics (simulated).
struct VmstatCommand: BuiltinCommand {
    let name = "vmstat"
    let summary = "Virtual memory statistics"
    let usage = "vmstat"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var info = mach_task_basic_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        context.stdout("---procs---  ---memory---  ---cpu--\n")
        context.stdout(" r  b   swpd   free   buff  cache  us sy id\n")
        if result == KERN_SUCCESS {
            let free = Int(info.virtual_size - info.resident_size) / 1024
            let used = Int(info.resident_size) / 1024
            context.stdout(" 1  0      0  \(free)      0      0   5  3 92\n")
        } else {
            context.stdout(" 1  0      0      0      0      0   0  0 100\n")
        }
        return 0
    }
}

/// `iostat` - I/O statistics (simulated).
struct IostatCommand: BuiltinCommand {
    let name = "iostat"
    let summary = "I/O statistics (simulated)"
    let usage = "iostat"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("          CPU     I/O\n")
        context.stdout("device   %usr %sys %idle   r/s  w/s\n")
        context.stdout("aero-root    5    3    92   0    0\n")
        return 0
    }
}

/// `lsblk` - list block devices (simulated).
struct LsblkCommand: BuiltinCommand {
    let name = "lsblk"
    let summary = "List block devices (simulated)"
    let usage = "lsblk"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("NAME   MAJ:MIN RM   SIZE RO TYPE MOUNTPOINT\n")
        context.stdout("aero   254:0    0   64G  0 disk /\n")
        return 0
    }
}

/// `mount` - mount filesystems (informational).
struct MountCommand: BuiltinCommand {
    let name = "mount"
    let summary = "Show mounted filesystems"
    let usage = "mount"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("aero-root on / type aero (rw,nosuid,nodev)\n")
        context.stdout("proc on /proc type proc (rw,nosuid,nodev,noexec)\n")
        context.stdout("tmpfs on /tmp type tmpfs (rw,nosuid,nodev)\n")
        return 0
    }
}

/// `ps` - report process status (simulated; only the shell itself).
struct PsCommand: BuiltinCommand {
    let name = "ps"
    let summary = "Report process status"
    let usage = "ps [-e] [-f]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let full = arguments.contains("-f") || arguments.contains("-e")
        if full {
            context.stdout("UID        PID  PPID  C    STIME TTY     TIME CMD\n")
            context.stdout("mobile       1     0  0    00:00 tty1    0:00 /bin/termious\n")
        } else {
            context.stdout("  PID TTY       TIME CMD\n")
            context.stdout("    1 tty1    0:00 termious\n")
        }
        return 0
    }
}

/// `kill` - send a signal to a process (no-op on iOS, informational).
struct KillCommand: BuiltinCommand {
    let name = "kill"
    let summary = "Send a signal to a process (informational)"
    let usage = "kill [-l] [-SIGNAL] PID..."

    func run(arguments: [String], context: CommandContext) -> Int32 {
        if arguments.contains("-l") {
            let signals = ["HUP", "INT", "QUIT", "ILL", "TRAP", "ABRT", "BUS",
                           "FPE", "KILL", "USR1", "SEGV", "USR2", "PIPE", "ALRM",
                           "TERM", "STKFLT", "CHLD", "CONT", "STOP"]
            for (i, s) in signals.enumerated() {
                context.stdout("\(i + 1) = \(s)\n")
            }
            return 0
        }
        context.stdout("kill: iOS does not support sending signals to other processes\n")
        return 1
    }
}

/// `calendar` / `date` already done. `factor` done.
/// `look` done. `cksum` done.

/// `vmstat` done. `logger` done.

/// `uniq` with -c, -d, -u flags - extend the existing one via a new command.
/// We'll add a `uniq2` alias called `uniqc` for counting.
struct UniqCCommand: BuiltinCommand {
    let name = "uniqc"
    let summary = "Count adjacent duplicate lines"
    let usage = "uniqc [file]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let input: String
        if let f = arguments.first {
            let started = context.fs.startRootAccess()
            if let url = context.fs.resolve(f),
               let data = try? Data(contentsOf: url),
               let s = String(data: data, encoding: .utf8) { input = s }
            else { input = context.stdin }
            if started { context.fs.stopRootAccess() }
        } else { input = context.stdin }
        var last: String? = nil; var count = 0
        for line in input.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if s == last { count += 1 }
            else {
                if let l = last { context.stdout(String(format: "%7d %@\n", count, l)) }
                last = s; count = 1
            }
        }
        if let l = last { context.stdout(String(format: "%7d %@\n", count, l)) }
        return 0
    }
}

/// `colorman` - man with color (alias for man).
struct ColormanCommand: BuiltinCommand {
    let name = "colorman"
    let summary = "Show colored manual"
    let usage = "colorman <command>"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let name = arguments.first else { return 1 }
        context.stdout("\u{001B}]MAN_PAGE\u{0007}\(name)\u{0007}")
        return 0
    }
}

/// `theme` - change terminal color scheme.
struct ThemeCommand: BuiltinCommand {
    let name = "theme"
    let summary = "Change terminal color scheme"
    let usage = "theme [dark|light|green|amber|blue]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let scheme = arguments.first else {
            context.stdout("Available: dark light green amber blue solarized\n")
            return 0
        }
        context.stdout("\u{001B}]THEME\u{0007}\(scheme)\u{0007}")
        return 0
    }
}

/// `resize` - output resize escape sequence.
struct ResizeCommand: BuiltinCommand {
    let name = "resize"
    let summary = "Force terminal resize"
    let usage = "resize"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("COLUMNS=80;LINES=40;export COLUMNS LINES;\n")
        return 0
    }
}

/// `hostnamectl` - control hostname (informational).
struct HostnamectlCommand: BuiltinCommand {
    let name = "hostnamectl"
    let summary = "Show or set hostname"
    let usage = "hostnamectl"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("   Static hostname: \(UIDevice.current.name)\n")
        context.stdout("Operating System: iOS \(UIDevice.current.systemVersion)\n")
        context.stdout("          Kernel: Darwin\n")
        context.stdout("    Architecture: arm64\n")
        return 0
    }
}

/// `timedatectl` - show time and date info.
struct TimedatectlCommand: BuiltinCommand {
    let name = "timedatectl"
    let summary = "Show time and date info"
    let usage = "timedatectl"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let now = ISO8601DateFormatter().string(from: Date())
        context.stdout("               Local time: \(now)\n")
        context.stdout("           Universal time: \(now)\n")
        context.stdout("                 RTC time: \(now)\n")
        context.stdout("                Time zone: \(TimeZone.current.identifier)\n")
        context.stdout("System clock synchronized: yes\n")
        context.stdout("              NTP service: n/a\n")
        return 0
    }
}

/// `cal` already done. `factor` done. `look` done.

/// `units` - unit conversion (basic).
struct UnitsCommand: BuiltinCommand {
    let name = "units"
    let summary = "Convert units (basic: m/ft, kg/lb, C/F)"
    let usage = "units <value> <from> <to>"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard arguments.count >= 3,
              let value = Double(arguments[0]) else {
            context.stderr("units: need <value> <from> <to>\n"); return 1
        }
        let from = arguments[1].lowercased()
        let to = arguments[2].lowercased()
        let result: Double?
        switch (from, to) {
        case ("m", "ft"): result = value * 3.28084
        case ("ft", "m"): result = value / 3.28084
        case ("kg", "lb"): result = value * 2.20462
        case ("lb", "kg"): result = value / 2.20462
        case ("c", "f"): result = value * 9 / 5 + 32
        case ("f", "c"): result = (value - 32) * 5 / 9
        case ("km", "mi"): result = value * 0.621371
        case ("mi", "km"): result = value / 0.621371
        case ("l", "gal"): result = value * 0.264172
        case ("gal", "l"): result = value / 0.264172
        default: result = nil
        }
        if let r = result {
            context.stdout(String(format: "* %.4f\n", r))
        } else {
            context.stderr("units: unknown conversion\n"); return 1
        }
        return 0
    }
}

/// `tsort` done. `dd` done. `truncate` done. `mktemp` done. `shred` done. `install` done.

/// `paste` already in AdvancedCommands. `join` done. `comm` done. `column` done. `tsort` done. `split` done.

/// `fmt` done. `fold` done. `expand` done.

/// `sha1sum` done. `sha256sum` done. `sha512sum` done. `cksum` done. `sum` done. `base32` done. `strings` done. `od` done. `xxd` done.

/// `ps` done. `kill` done. `w` done. `users` done. `last` done. `dmesg` done. `logger` done. `lsof` done. `vmstat` done. `iostat` done. `lsblk` done. `mount` done.

/// `type` done. `command` done. `printenv` done. `unset` done. `dirs` done. `pushd` done. `popd` done. `unalias` done. `apropos` done. `tput` done. `stty` done. `true` done. `false` done. `umask` done. `ulimit` done. `nproc` done. `lscpu` done. `getconf` done. `readlink` done. `resize` done. `hostnamectl` done. `timedatectl` done. `units` done. `theme` done. `colorman` done. `uniqc` done.