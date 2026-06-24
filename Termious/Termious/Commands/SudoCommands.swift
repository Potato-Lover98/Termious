import Foundation

/// `sudo` - runs a command as the virtual superuser. Requires a password
/// (default "alpine"). The password is requested via a control sequence that
/// the UI intercepts to show a password dialog. Once authenticated, the
/// sudo session stays active for 5 minutes.
///
/// Usage:
///   sudo <command...>        Run a command with elevated privileges
///   sudo -k                  Kill sudo session (require password next time)
///   sudo -l                  List sudo privileges
struct SudoCommand: BuiltinCommand {
    let name = "sudo"
    let summary = "Execute a command as the superuser"
    let usage = "sudo [-k|-l] <command...>"
    var operands: [Operand] {[
        Operand(name: "command", description: "Command to run with root privileges", required: true, type: .string),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        // Handle sudo-only flags
        var args = arguments
        if let first = args.first {
            if first == "-k" {
                SudoSession.shared.invalidate()
                context.stdout("sudo: session invalidated. Password required next time.\n")
                return 0
            }
            if first == "-l" {
                context.stdout("User mobile may run the following commands:\n    (ALL) ALL\n")
                return 0
            }
            if first == "-h" || first == "--help" {
                context.stdout("sudo - \(summary)\nusage: \(usage)\n")
                return 0
            }
        }

        guard !args.isEmpty else {
            context.stderr("sudo: missing command to execute\n")
            return 1
        }

        // Check if already authenticated
        if !SudoSession.shared.isAuthenticated {
            // Emit a control sequence to ask the UI for a password.
            // The UI will present a password alert and call back.
            // We emit the signal and wait for the session to be authenticated.
            context.stdout("\u{001B}]SUDO_PROMPT\u{0007}")
            // The actual password verification happens in the UI layer;
            // if authentication fails, the UI will print an error and we
            // return failure. For now, return 1 — the UI handles re-execution.
            return 1
        }

        // Already authenticated — emit a signal telling the shell to re-run
        // the remaining args as root. The ShellHost handles this by
        // re-executing the command with root context.
        let cmdLine = args.joined(separator: " ")
        context.stdout("\u{001B}]SUDO_EXEC\u{0007}\(cmdLine)\u{0007}")
        return 0
    }
}

/// `passwd` - change the sudo password.
/// Usage:
///   passwd                   Change password (prompts for old + new)
///   passwd <new>             Set new password directly (for setup)
struct PasswdCommand: BuiltinCommand {
    let name = "passwd"
    let summary = "Change the sudo password"
    let usage = "passwd [newpassword]"
    var operands: [Operand] {[
        Operand(name: "newpassword", description: "New password to set (omitted = interactive)", required: false, type: .string),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        if let newPw = arguments.first {
            PasswordManager.shared.setPassword(newPw)
            context.stdout("Password updated.\n")
            return 0
        }
        // Emit a signal to the UI to present a change-password dialog
        context.stdout("\u{001B}]PASSWD_CHANGE\u{0007}")
        return 0
    }
}

/// `chown` - change virtual file ownership.
/// Usage: chown owner[:group] file...
struct ChownCommand: BuiltinCommand {
    let name = "chown"
    let summary = "Change file owner and group"
    let usage = "chown owner[:group] file..."
    var operands: [Operand] {[
        Operand(name: "owner", description: "New owner (and :group optionally)", required: true, type: .string),
        Operand(name: "file", description: "File(s) to change ownership of", required: true, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard arguments.count >= 2 else {
            context.stderr("chown: missing operand\nusage: \(usage)\n")
            return 1
        }
        let ownerSpec = arguments[0]
        let files = Array(arguments.dropFirst())

        let parts = ownerSpec.split(separator: ":", maxSplits: 1)
        let owner = String(parts[0])
        let group = parts.count > 1 ? String(parts[1]) : nil

        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }

        var hadError = false
        for file in files {
            guard let url = context.fs.resolve(file) else {
                context.stderr("chown: cannot access '\(file)'\n")
                hadError = true
                continue
            }
            if !FileManager.default.fileExists(atPath: url.path) {
                context.stderr("chown: cannot access '\(file)': no such file\n")
                hadError = true
                continue
            }
            let logical = context.fs.logicalPath(of: url)
            FileMetadataStore.shared.update(logical, owner: owner, group: group)
        }
        return hadError ? 1 : 0
    }
}

/// `chmod` - change virtual file permissions.
/// Usage: chmod <mode> file...    (mode is octal like 755 or symbolic like +x)
struct ChmodCommand: BuiltinCommand {
    let name = "chmod"
    let summary = "Change file permissions"
    let usage = "chmod <mode> file..."
    var operands: [Operand] {[
        Operand(name: "mode", description: "Octal mode like 755 or 644", required: true, type: .number),
        Operand(name: "file", description: "File(s) to change permissions of", required: true, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard arguments.count >= 2 else {
            context.stderr("chmod: missing operand\nusage: \(usage)\n")
            return 1
        }
        let modeStr = arguments[0]
        let files = Array(arguments.dropFirst())

        // Validate octal mode
        guard let mode = UInt(modeStr, radix: 8), mode <= 0o777 else {
            context.stderr("chmod: invalid mode: '\(modeStr)'\n")
            return 1
        }
        let modeString = String(format: "%03o", mode)

        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }

        var hadError = false
        for file in files {
            guard let url = context.fs.resolve(file) else {
                context.stderr("chmod: cannot access '\(file)'\n")
                hadError = true
                continue
            }
            if !FileManager.default.fileExists(atPath: url.path) {
                context.stderr("chmod: cannot access '\(file)': no such file\n")
                hadError = true
                continue
            }
            let logical = context.fs.logicalPath(of: url)
            FileMetadataStore.shared.update(logical, permissions: modeString)
        }
        return hadError ? 1 : 0
    }
}

/// `chgrp` - change virtual file group.
struct ChgrpCommand: BuiltinCommand {
    let name = "chgrp"
    let summary = "Change file group"
    let usage = "chgrp <group> file..."
    var operands: [Operand] {[
        Operand(name: "group", description: "New group name", required: true, type: .string),
        Operand(name: "file", description: "File(s) to change group of", required: true, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard arguments.count >= 2 else {
            context.stderr("chgrp: missing operand\nusage: \(usage)\n")
            return 1
        }
        let group = arguments[0]
        let files = Array(arguments.dropFirst())
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        var hadError = false
        for file in files {
            guard let url = context.fs.resolve(file) else {
                context.stderr("chgrp: cannot access '\(file)'\n")
                hadError = true
                continue
            }
            let logical = context.fs.logicalPath(of: url)
            FileMetadataStore.shared.update(logical, group: group)
        }
        return hadError ? 1 : 0
    }
}

/// `whoami` override - now reports root when sudo session is active.
/// (Registered in place of the original WhoamiCommand.)