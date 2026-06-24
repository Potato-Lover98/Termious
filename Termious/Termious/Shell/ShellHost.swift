import Foundation

public protocol ShellHostDelegate: AnyObject {
    func shellHostDidRequestOpenPicker(_ host: ShellHost)
    func shellHostDidRequestExit(_ host: ShellHost)
    func shellHostDidClearScreen(_ host: ShellHost)
    func shellHostDidRequestSudoPrompt(_ host: ShellHost, command: String)
    func shellHostDidRequestPasswdChange(_ host: ShellHost)
    func shellHostDidRequestShowHistory(_ host: ShellHost)
    func shellHostDidRequestManPage(_ host: ShellHost, command: String)
    func shellHostDidRequestTimeCommand(_ host: ShellHost, command: String)
    func shellHostDidRequestWatch(_ host: ShellHost, interval: Double, command: String)
    func shellHostDidRequestReboot(_ host: ShellHost)
    func shellHostDidRequestSudoExec(_ host: ShellHost, command: String)
    func shellHostDidRequestThemeChange(_ host: ShellHost, scheme: String)
    func shellHostDidRequestBackgroundChange(_ host: ShellHost, styleName: String)
    func shellHostDidRequestTineoEdit(_ host: ShellHost, mode: String, path: String)
    func shellHostDidRequestOpenURL(_ host: ShellHost, url: String)
    func shellHostDidRequestSourceExec(_ host: ShellHost, content: String)
    func shellHostDidRequestAeroClone(_ host: ShellHost, repo: String, name: String)
}

public final class ShellHost {
    public let fs: VirtualFileSystem
    public let registry: CommandRegistry
    public var env: [String: String]
    public var aliases: [String: String] = [:]
    public weak var delegate: ShellHostDelegate?

    public init() {
        self.fs = VirtualFileSystem()
        self.registry = CommandRegistry()
        self.env = [
            "USER": "mobile",
            "SHELL": "/bin/termious",
            "TERM": "xterm-256color",
            "PWD": "/",
            "HOME": "/",
            "PATH": "/bin/termious"
        ]
    }

    public var prompt: String {
        let cwd = fs.cwd
        let display = fs.cwd
        let user: String = SudoSession.shared.isAuthenticated ? "root" : "mobile"
        let marker: String = SudoSession.shared.isAuthenticated ? "# " : "$ "
        return "\(user):\(display)\(marker)"
    }

    /// Executes a full command line (may contain multiple pipelines separated by ';').
    @discardableResult
    public func execute(_ line: String,
                        onOutput: @escaping (String) -> Void,
                        onError: @escaping (String) -> Void) -> Int32 {
        // Expand aliases
        let expanded = expandAliases(line)
        let pipelines = Parser.parse(expanded)
        var lastStatus: Int32 = 0
        for pipeline in pipelines {
            if pipeline.commands.isEmpty { continue }
            lastStatus = runPipeline(pipeline, onOutput: onOutput, onError: onError)
        }
        env["PWD"] = fs.cwd
        return lastStatus
    }

    private func expandAliases(_ line: String) -> String {
        if aliases.isEmpty { return line }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let firstWord = trimmed.split(separator: " ").first,
              let alias = aliases[String(firstWord)] else { return line }
        let rest = trimmed.dropFirst(firstWord.count)
        return alias + String(rest)
    }

    private func runPipeline(_ pipeline: Pipeline,
                             onOutput: @escaping (String) -> Void,
                             onError: @escaping (String) -> Void) -> Int32 {
        var stdinBuffer = ""
        var status: Int32 = 0

        for (idx, node) in pipeline.commands.enumerated() {
            let isLast = idx == pipeline.commands.count - 1
            let command = registry.resolve(node.executable)

            var input = stdinBuffer
            if let inFile = node.stdinFile {
                if let url = fs.resolve(inFile),
                   let data = try? Data(contentsOf: url),
                   let s = String(data: data, encoding: .utf8) {
                    input = s
                } else {
                    onError("\(node.executable): cannot open \(inFile) for input\n")
                    return 1
                }
            }

            var redirectTo: URL? = nil
            var appendMode = false
            if let outFile = node.stdoutFile {
                redirectTo = fs.resolve(outFile)
                appendMode = false
            } else if let appFile = node.appendFile {
                redirectTo = fs.resolve(appFile)
                appendMode = true
            }

            var capturedOutput = ""
            let sink: (String) -> Void = { text in
                if let url = redirectTo {
                    let started = self.fs.startRootAccess()
                    let data = Data(text.utf8)
                    if appendMode && FileManager.default.fileExists(atPath: url.path) {
                        if let handle = try? FileHandle(forWritingTo: url) {
                            handle.seekToEndOfFile()
                            handle.write(data)
                            handle.closeFile()
                        }
                    } else {
                        try? data.write(to: url)
                    }
                    if started { self.fs.stopRootAccess() }
                } else {
                    capturedOutput += text
                }
            }
            let errSink: (String) -> Void = { text in onError(text) }

            guard let cmd = command else {
                onError("\(node.executable): command not found. Type 'help'.\n")
                return 127
            }

            if cmd.name == "help" {
                status = runHelp(arguments: node.arguments,
                                 context: makeContext(stdin: input, out: sink, err: errSink))
            } else {
                let ctx = makeContext(stdin: input, out: sink, err: errSink)
                status = cmd.run(arguments: node.arguments, context: ctx)
            }

            // Detect and strip control signals
            var forwarded = capturedOutput
            forwarded = processControlSignals(from: forwarded, node: node,
                                               onOutput: onOutput, onError: onError)
            if isLast {
                if !forwarded.isEmpty { onOutput(forwarded) }
                stdinBuffer = ""
            } else {
                stdinBuffer = forwarded
            }
        }

        return status
    }

    private func processControlSignals(from text: String, node: CommandNode,
                                       onOutput: @escaping (String) -> Void,
                                       onError: @escaping (String) -> Void) -> String {
        var result = text

        // OSC: ESC ] <code> BEL
        while let range = result.range(of: "\u{001B}]") {
            guard let endRange = result.range(of: "\u{0007}", range: range.upperBound..<result.endIndex)
            else { break }
            let payload = String(result[range.upperBound..<endRange.lowerBound])

            if payload == "OPEN_PICKER" {
                delegate?.shellHostDidRequestOpenPicker(self)
            } else if payload == "SUDO_PROMPT" {
                let cmdLine = node.arguments.joined(separator: " ")
                delegate?.shellHostDidRequestSudoPrompt(self, command: cmdLine)
            } else if payload == "SUDO_EXEC" {
                // payload is SUDO_EXEC<command> — but we used a separate BEL
                // Actually the command is embedded after the first BEL.
                // The format is: ESC ] SUDO_EXEC BEL <command> BEL
                // The part after endRange up to next BEL is the command.
                if let nextBel = result.range(of: "\u{0007}", range: endRange.upperBound..<result.endIndex) {
                    let cmd = String(result[endRange.upperBound..<nextBel.lowerBound])
                    delegate?.shellHostDidRequestSudoExec(self, command: cmd)
                    result.removeSubrange(range.lowerBound..<nextBel.upperBound)
                    continue
                }
            } else if payload == "PASSWD_CHANGE" {
                delegate?.shellHostDidRequestPasswdChange(self)
            } else if payload == "SHOW_HISTORY" {
                delegate?.shellHostDidRequestShowHistory(self)
            } else if payload == "MAN_PAGE" {
                if let nextBel = result.range(of: "\u{0007}", range: endRange.upperBound..<result.endIndex) {
                    let cmdName = String(result[endRange.upperBound..<nextBel.lowerBound])
                    delegate?.shellHostDidRequestManPage(self, command: cmdName)
                    result.removeSubrange(range.lowerBound..<nextBel.upperBound)
                    continue
                }
            } else if payload == "TIME_CMD" {
                if let nextBel = result.range(of: "\u{0007}", range: endRange.upperBound..<result.endIndex) {
                    let cmdLine = String(result[endRange.upperBound..<nextBel.lowerBound])
                    delegate?.shellHostDidRequestTimeCommand(self, command: cmdLine)
                    result.removeSubrange(range.lowerBound..<nextBel.upperBound)
                    continue
                }
            } else if payload == "WATCH" {
                if let nextBel = result.range(of: "\u{0007}", range: endRange.upperBound..<result.endIndex) {
                    let inner = String(result[endRange.upperBound..<nextBel.lowerBound])
                    let parts = inner.split(separator: "|", maxSplits: 1)
                    if parts.count == 2 {
                        let interval = Double(parts[0]) ?? 2.0
                        let cmd = String(parts[1])
                        delegate?.shellHostDidRequestWatch(self, interval: interval, command: cmd)
                    }
                    result.removeSubrange(range.lowerBound..<nextBel.upperBound)
                    continue
                }
            } else if payload == "REBOOT" {
                delegate?.shellHostDidRequestReboot(self)
            } else if payload == "EXPORT" {
                if let nextBel = result.range(of: "\u{0007}", range: endRange.upperBound..<result.endIndex) {
                    let kv = String(result[endRange.upperBound..<nextBel.lowerBound])
                    let parts = kv.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        env[String(parts[0])] = String(parts[1])
                    }
                    result.removeSubrange(range.lowerBound..<nextBel.upperBound)
                    continue
                }
            } else if payload == "ALIAS" {
                if let nextBel = result.range(of: "\u{0007}", range: endRange.upperBound..<result.endIndex) {
                    let kv = String(result[endRange.upperBound..<nextBel.lowerBound])
                    let parts = kv.split(separator: "=", maxSplits: 1)
                    if parts.count == 2 {
                        aliases[String(parts[0])] = String(parts[1])
                    }
                    result.removeSubrange(range.lowerBound..<nextBel.upperBound)
                    continue
                }
            } else if payload == "UNALIAS" {
                if let nextBel = result.range(of: "\u{0007}", range: endRange.upperBound..<result.endIndex) {
                    let name = String(result[endRange.upperBound..<nextBel.lowerBound])
                    aliases.removeValue(forKey: name)
                    result.removeSubrange(range.lowerBound..<nextBel.upperBound)
                    continue
                }
            } else if payload == "UNSET" {
                if let nextBel = result.range(of: "\u{0007}", range: endRange.upperBound..<result.endIndex) {
                    let name = String(result[endRange.upperBound..<nextBel.lowerBound])
                    env.removeValue(forKey: name)
                    result.removeSubrange(range.lowerBound..<nextBel.upperBound)
                    continue
                }
            } else if payload == "XARGS" {
                if let nextBel = result.range(of: "\u{0007}", range: endRange.upperBound..<result.endIndex) {
                    let cmdLine = String(result[endRange.upperBound..<nextBel.lowerBound])
                    execute(cmdLine,
                            onOutput: onOutput,
                            onError: onError)
                    result.removeSubrange(range.lowerBound..<nextBel.upperBound)
                    continue
                }
            } else if payload == "TYPE_CMD" {
                if let nextBel = result.range(of: "\u{0007}", range: endRange.upperBound..<result.endIndex) {
                    let names = String(result[endRange.upperBound..<nextBel.lowerBound])
                    for name in names.split(separator: " ") {
                        let n = String(name)
                        if registry.resolve(n) != nil {
                            result += "\(n) is a shell builtin\n"
                        } else if aliases[n] != nil {
                            result += "\(n) is an alias for \(aliases[n] ?? "")\n"
                        } else {
                            result += "\(n) not found\n"
                        }
                    }
                    result.removeSubrange(range.lowerBound..<nextBel.upperBound)
                    continue
                }
            } else if payload == "APROPOS" {
                if let nextBel = result.range(of: "\u{0007}", range: endRange.upperBound..<result.endIndex) {
                    let query = String(result[endRange.upperBound..<nextBel.lowerBound]).lowercased()
                    for cmdName in registry.availableCommands {
                        if let cmd = registry.resolve(cmdName),
                           cmd.summary.lowercased().contains(query) || cmdName.contains(query) {
                            result += "\(cmdName) (\(cmd.summary))\n"
                        }
                    }
                    result.removeSubrange(range.lowerBound..<nextBel.upperBound)
                    continue
                }
            } else if payload == "THEME" {
                if let nextBel = result.range(of: "\u{0007}", range: endRange.upperBound..<result.endIndex) {
                    let scheme = String(result[endRange.upperBound..<nextBel.lowerBound])
                    delegate?.shellHostDidRequestThemeChange(self, scheme: scheme)
                    result.removeSubrange(range.lowerBound..<nextBel.upperBound)
                    continue
                }
            } else if payload == "BG_SET" {
                if let nextBel = result.range(of: "\u{0007}", range: endRange.upperBound..<result.endIndex) {
                    let styleName = String(result[endRange.upperBound..<nextBel.lowerBound])
                    delegate?.shellHostDidRequestBackgroundChange(self, styleName: styleName)
                    result.removeSubrange(range.lowerBound..<nextBel.upperBound)
                    continue
                }
            } else if payload == "TINEO_EDIT" {
                if let nextBel = result.range(of: "\u{0007}", range: endRange.upperBound..<result.endIndex) {
                    let inner = String(result[endRange.upperBound..<nextBel.lowerBound])
                    if inner.hasPrefix("EDIT:") {
                        delegate?.shellHostDidRequestTineoEdit(self, mode: "EDIT", path: String(inner.dropFirst(5)))
                    } else if inner.hasPrefix("NEW:") {
                        delegate?.shellHostDidRequestTineoEdit(self, mode: "NEW", path: String(inner.dropFirst(4)))
                    }
                    result.removeSubrange(range.lowerBound..<nextBel.upperBound)
                    continue
                }
            } else if payload == "OPEN_URL" {
                if let nextBel = result.range(of: "\u{0007}", range: endRange.upperBound..<result.endIndex) {
                    let urlStr = String(result[endRange.upperBound..<nextBel.lowerBound])
                    delegate?.shellHostDidRequestOpenURL(self, url: urlStr)
                    result.removeSubrange(range.lowerBound..<nextBel.upperBound)
                    continue
                }
            } else if payload == "SOURCE_EXEC" {
                if let nextBel = result.range(of: "\u{0007}", range: endRange.upperBound..<result.endIndex) {
                    let content = String(result[endRange.upperBound..<nextBel.lowerBound])
                    delegate?.shellHostDidRequestSourceExec(self, content: content)
                    result.removeSubrange(range.lowerBound..<nextBel.upperBound)
                    continue
                }
            } else if payload == "AERO_CLONE" {
                if let nextBel = result.range(of: "\u{0007}", range: endRange.upperBound..<result.endIndex) {
                    let inner = String(result[endRange.upperBound..<nextBel.lowerBound])
                    let parts = inner.split(separator: "\u{0007}", maxSplits: 1)
                    if parts.count == 2 {
                        delegate?.shellHostDidRequestAeroClone(self, repo: String(parts[0]), name: String(parts[1]))
                    }
                    result.removeSubrange(range.lowerBound..<nextBel.upperBound)
                    continue
                }
            }

            result.removeSubrange(range.lowerBound..<endRange.upperBound)
        }

        // Handle exit (EOT marker)
        if result.contains("\u{0004}") {
            result = result.replacingOccurrences(of: "\u{0004}", with: "")
            delegate?.shellHostDidRequestExit(self)
        }
        // Handle clear (ANSI clear screen)
        if result.contains("\u{001B}[2J\u{001B}[H") {
            result = result.replacingOccurrences(of: "\u{001B}[2J\u{001B}[H", with: "")
            delegate?.shellHostDidClearScreen(self)
        }

        return result
    }

    private func makeContext(stdin: String,
                             out: @escaping (String) -> Void,
                             err: @escaping (String) -> Void) -> CommandContext {
        CommandContext(fs: fs, env: env, stdin: stdin, stdout: out, stderr: err)
    }

    private func runHelp(arguments: [String], context: CommandContext) -> Int32 {
        if let name = arguments.first {
            if let cmd = registry.resolve(name) {
                context.stdout("\u{001B}[33m\(cmd.name)\u{001B}[0m - \(cmd.summary)\n")
                context.stdout("\u{001B}[36musage:\u{001B}[0m \(cmd.usage)\n")
                if !cmd.operands.isEmpty {
                    context.stdout("\n\u{001B}[36moperands:\u{001B}[0m\n")
                    for op in cmd.operands {
                        let req = op.required ? "required" : "optional"
                        context.stdout("  \u{001B}[32m\(op.name)\u{001B}[0m  (\(req))  \(op.description)\n")
                    }
                }
            } else {
                context.stderr("help: unknown command: \(name)\n")
                return 1
            }
            return 0
        }

        let categories: [(label: String, color: String, names: [String])] = [
            ("FILES", "32", ["ls", "cd", "pwd", "cat", "mkdir", "rm", "cp", "mv", "touch", "ln",
                              "tree", "find", "stat", "du", "file", "basename", "dirname",
                              "realpath", "readlink", "split", "dd", "truncate", "mktemp",
                              "shred", "install", "fallocate", "rename", "lsattr", "chattr",
                              "getfacl", "setfacl", "compact"]),
            ("TEXT", "36", ["head", "tail", "wc", "grep", "sed", "awk", "cut", "tr", "sort",
                             "uniq", "uniqc", "rev", "paste", "tac", "nl", "diff", "comm",
                             "join", "fmt", "fold", "expand", "column", "tsort", "look",
                             "shuf", "strings", "od", "xxd", "tee", "xargs", "printf"]),
            ("NETWORK", "34", ["wget", "curl", "ping", "nslookup", "dig", "host", "ifconfig",
                                 "ip", "route", "arp", "netstat", "ssh-keygen", "xdg-open",
                                 "safari"]),
            ("ARCHIVES", "35", ["zip", "unzip", "tar"]),
            ("CRYPTO", "31", ["hash", "cksum", "sum", "sha1sum", "sha256sum", "sha512sum",
                              "base64", "base32"]),
            ("SYSTEM", "33", ["uname", "hostname", "hostnamectl", "uptime", "df", "free",
                               "whoami", "id", "logname", "groups", "nproc", "lscpu",
                               "getconf", "dmesg", "vmstat", "iostat", "lsblk", "mount",
                               "findmnt", "lslocks", "fuser", "ps", "kill", "w", "users",
                               "last", "logger", "lsof", "locale", "localedef", "cal",
                               "date", "sleep", "seq", "factor", "bc", "expr", "units",
                               "test", "true", "false", "umask", "ulimit", "env",
                               "printenv", "getent", "nice", "renice", "chroot", "crontab",
                               "at", "atq", "atrm", "anacron", "batch", "jobs", "disown",
                               "trap", "suspend", "wait", "logout", "login", "newgrp"]),
            ("SERVICE", "34", ["systemctl", "journalctl", "loginctl", "resolvectl",
                                "localectl", "timedatectl", "systemd-analyze", "coredumpctl",
                                "busctl", "machinectl"]),
            ("USER", "35", ["sudo", "passwd", "su", "runuser", "useradd", "userdel",
                             "usermod", "groupadd", "groupdel", "groupmod", "chown",
                             "chgrp", "chmod", "gpasswd", "chfn", "chsh", "pwck", "grpck",
                             "vipw", "mkfs"]),
            ("SHELL", "32", ["echo", "clear", "exit", "help", "history", "type", "command",
                              "export", "unset", "alias", "unalias", "source", "eval",
                              "exec", "which", "man", "time", "watch", "reboot", "apropos",
                              "tput", "stty", "resize", "pushd", "popd", "dirs", "bg",
                              "theme", "colors", "credits", "info", "colorman"]),
            ("PACKAGE", "36", ["aero", "bookmarks", "open", "git"]),
            ("EDITOR", "33", ["tineo"]),
            ("AI & GPU", "35", ["claude", "hermes", "ai", "openclaw", "gpu", "metal"]),
            ("MISC", "37", ["yes"]),
        ]

        context.stdout("\n\u{001B}[1m\u{001B}[32mTermious\u{001B}[0m \u{001B}[0m- \u{001B}[36m\(registry.availableCommands.count)\u{001B}[0m commands available\n\n")
        for cat in categories {
            context.stdout("\u{001B}[1m\u{001B}[\(cat.color)m\(cat.label)\u{001B}[0m\n")
            var line = "  "
            for name in cat.names {
                if let cmd = registry.resolve(name) {
                    let padded = name.padding(toLength: max(14, name.count + 1), withPad: " ", startingAt: 0)
                    if line.count + padded.count > 80 {
                        context.stdout(line.trimmingCharacters(in: .whitespaces) + "\n")
                        line = "  "
                    }
                    line += padded
                }
            }
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                context.stdout(line.trimmingCharacters(in: .whitespaces) + "\n")
            }
            context.stdout("\n")
        }
        context.stdout("\u{001B}[36mQuick start:\u{001B}[0m\n")
        context.stdout("  help <command>    Show usage for a command\n")
        context.stdout("  man <command>     Show manual page\n")
        context.stdout("  tineo <file>      Edit a file with syntax highlighting\n")
        context.stdout("  aero install <owner/repo>  Download from GitHub\n")
        context.stdout("  sudo <command>    Run as root (password: alpine)\n")
        context.stdout("  bg <name>         Change background (15 styles)\n")
        context.stdout("  theme <name>      Change color scheme\n")
        context.stdout("  xdg-open <file>   Open HTML/XML in Safari\n")
        context.stdout("  claude \"prompt\"   Ask Claude AI (set ANTHROPIC_API_KEY first)\n")
        context.stdout("  hermes \"code\"     Run JavaScript via JavaScriptCore\n")
        context.stdout("  gpu info           Show Metal GPU info\n")
        context.stdout("  gpu bench          Run GPU benchmark\n")
        return 0
    }
}