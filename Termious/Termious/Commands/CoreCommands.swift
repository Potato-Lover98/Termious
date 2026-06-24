import Foundation

struct LsCommand: BuiltinCommand {
    let name = "ls"
    let summary = "List directory contents"
    let usage = "ls [-l] [-a] [path...]"
    var operands: [Operand] {[
        Operand(name: "path", description: "Directory or file to list", required: false, type: .path),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var longFormat = false
        var showAll = false
        var paths: [String] = []

        for arg in arguments {
            if arg.hasPrefix("-") {
                for flag in arg.dropFirst() {
                    if flag == "l" { longFormat = true }
                    else if flag == "a" { showAll = true }
                    else if flag == "h" {
                        context.stdout("usage: \(usage)\n")
                        return 0
                    }
                }
            } else {
                paths.append(arg)
            }
        }
        if paths.isEmpty { paths = ["."] }

        let fm = FileManager.default
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }

        var hadError = false
        for (idx, path) in paths.enumerated() {
            guard let url = context.fs.resolve(path) else {
                context.stderr("ls: cannot access '\(path)'\n")
                hadError = true
                continue
            }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
                context.stderr("ls: cannot access '\(path)'\n")
                hadError = true
                continue
            }

            if !isDir.boolValue {
                if longFormat { context.stdout(formatLong(url: url, name: path, isDir: false, fs: context.fs)) }
                else { context.stdout("\(path)\n") }
                continue
            }

            if paths.count > 1 {
                if idx > 0 { context.stdout("\n") }
                context.stdout("\(path):\n")
            }

            do {
                let entries = try fm.contentsOfDirectory(atPath: url.path)
                    .filter { showAll || !$0.hasPrefix(".") }
                    .sorted()
                if longFormat {
                    for entry in entries {
                        let entryURL = url.appendingPathComponent(entry)
                        context.stdout(formatLong(url: entryURL, name: entry,
                                                   isDir: (try? entryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false,
                                                   fs: context.fs))
                    }
                } else {
                    // Compact column layout
                    let line = entries.joined(separator: "  ")
                    context.stdout(line + "\n")
                }
            } catch {
                context.stderr("ls: \(error.localizedDescription)\n")
                hadError = true
            }
        }
        return hadError ? 1 : 0
    }

    private func formatLong(url: URL, name: String, isDir: Bool, fs: VirtualFileSystem) -> String {
        let fm = FileManager.default
        var attrs: [FileAttributeKey: Any]?
        do { attrs = try fm.attributesOfItem(atPath: url.path) } catch { attrs = nil }

        let logical = fs.logicalPath(of: url)
        let meta = FileMetadataStore.shared.get(logical)
        let perms = permissionsString(meta.permissions, isDir: isDir)
        let type = isDir ? "d" : "-"
        let size = (attrs?[.size] as? Int) ?? 0
        let mod = (attrs?[.modificationDate] as? Date) ?? Date()
        let modStr = ISO8601DateFormatter().string(from: mod)
            .replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "Z", with: "")
        return "\(type)\(perms) \(meta.owner) \(meta.group) \(pad(size: size)) \(String(modStr.prefix(16))) \(name)\n"
    }

    private func permissionsString(_ mode: String, isDir: Bool) -> String {
        let m = Int(mode, radix: 8) ?? 0o644
        let perms = [
            (m >> 6) & 7, (m >> 3) & 7, m & 7
        ]
        let chars = ["r", "w", "x"]
        var result = ""
        for group in perms {
            for (i, c) in chars.enumerated() {
                result.append((group & (1 << (2 - i))) != 0 ? c : "-")
            }
        }
        return result
    }

    private func pad(size: Int) -> String {
        String(format: "%10d", size)
    }
}

struct CdCommand: BuiltinCommand {
    let name = "cd"
    let summary = "Change the working directory"
    let usage = "cd [path]"
    var operands: [Operand] {[
        Operand(name: "path", description: "Target directory to change to", required: false, type: .directory),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let target = arguments.isEmpty ? "/" : arguments[0]
        let result = context.fs.changeDirectory(to: target)
        switch result {
        case .success:
            return 0
        case .failure(let msg):
            context.stderr(msg + "\n")
            return 1
        }
    }
}

struct PwdCommand: BuiltinCommand {
    let name = "pwd"
    let summary = "Print the working directory"
    let usage = "pwd"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout(context.fs.cwd + "\n")
        return 0
    }
}

struct EchoCommand: BuiltinCommand {
    let name = "echo"
    let summary = "Print text"
    let usage = "echo [-n] [text...]"
    var operands: [Operand] {[
        Operand(name: "text", description: "Text to print to stdout", required: false, type: .string),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var args = arguments
        var noNewline = false
        if let first = args.first, first == "-n" {
            noNewline = true
            args.removeFirst()
        }
        let text = args.joined(separator: " ")
        context.stdout(noNewline ? text : text + "\n")
        return 0
    }
}

struct CatCommand: BuiltinCommand {
    let name = "cat"
    let summary = "Print file contents"
    let usage = "cat [file...]"
    var operands: [Operand] {[
        Operand(name: "file", description: "File(s) to print contents of", required: false, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        if arguments.isEmpty {
            // Pass stdin through
            context.stdout(context.stdin)
            return 0
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        var error = false
        for path in arguments {
            guard let url = context.fs.resolve(path) else {
                context.stderr("cat: \(path): no such file\n")
                error = true
                continue
            }
            if let data = try? Data(contentsOf: url),
               let str = String(data: data, encoding: .utf8) {
                context.stdout(str)
                if !str.hasSuffix("\n") { context.stdout("\n") }
            } else {
                context.stderr("cat: \(path): cannot read file\n")
                error = true
            }
        }
        return error ? 1 : 0
    }
}

struct ClearCommand: BuiltinCommand {
    let name = "clear"
    let summary = "Clear the screen"
    let usage = "clear"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("\u{001B}[2J\u{001B}[H")
        return 0
    }
}

struct ExitCommand: BuiltinCommand {
    let name = "exit"
    let summary = "Exit the shell"
    let usage = "exit"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        // Signal handled by Shell
        context.stdout("\u{0004}") // EOT marker interpreted by shell
        return 0
    }
}

struct HelpCommand: BuiltinCommand {
    let name = "help"
    let summary = "Show available commands"
    let usage = "help [command]"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        // Resolved via ShellHost since it needs the registry. Fallback here:
        if let name = arguments.first {
            context.stdout("Use '\(name) -h' for command-specific help.\n")
        } else {
            context.stdout("Type 'help <command>' or '<command> -h'.\n")
        }
        return 0
    }
}

struct DateCommand: BuiltinCommand {
    let name = "date"
    let summary = "Print current date and time"
    let usage = "date"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let f = ISO8601DateFormatter()
        context.stdout(f.string(from: Date()) + "\n")
        return 0
    }
}

struct WhoamiCommand: BuiltinCommand {
    let name = "whoami"
    let summary = "Print the current user"
    let usage = "whoami"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let user = SudoSession.shared.isAuthenticated ? "root" : (context.env["USER"] ?? "mobile")
        context.stdout(user + "\n")
        return 0
    }
}

struct EnvCommand: BuiltinCommand {
    let name = "env"
    let summary = "Print environment variables"
    let usage = "env"

    func run(arguments: [String], context: CommandContext) -> Int32 {
        for (k, v) in context.env.sorted(by: { $0.key < $1.key }) {
            context.stdout("\(k)=\(v)\n")
        }
        return 0
    }
}