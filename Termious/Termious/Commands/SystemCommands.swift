import Foundation
import UIKit

/// `systemctl` - control systemd services (simulated for iOS).
struct SystemctlCommand: BuiltinCommand {
    let name = "systemctl"
    let summary = "Control the systemd system manager (simulated)"
    let usage = "systemctl <start|stop|restart|status|enable|disable|list-units|is-active> [service]"
    var operands: [Operand] {[
        Operand(name: "action", description: "start, stop, restart, status, enable, disable, etc.", required: true, type: .string),
        Operand(name: "service", description: "Service name to control", required: false, type: .string),
    ]}
    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let sub = arguments.first else { context.stderr("systemctl: missing command\n"); return 1 }
        let svc = arguments.dropFirst().first ?? ""
        switch sub {
        case "start": context.stdout("\u{001B}[32m\u{2713}\u{001B}[0m Started \(svc)\n"); return 0
        case "stop": context.stdout("\u{001B}[31m\u{2715}\u{001B}[0m Stopped \(svc)\n"); return 0
        case "restart": context.stdout("\u{001B}[32m\u{2713}\u{001B}[0m Restarted \(svc)\n"); return 0
        case "reload": context.stdout("Reloaded \(svc)\n"); return 0
        case "status":
            context.stdout("\u{001B}[32m\u{25CF}\u{001B}[0m \(svc).service - \(svc) daemon\n     Loaded: loaded\n     Active: \u{001B}[32mactive (running)\u{001B}[0m\n     Main PID: 42\n"); return 0
        case "enable": context.stdout("Created symlink for \(svc)\n"); return 0
        case "disable": context.stdout("Removed symlink for \(svc)\n"); return 0
        case "mask": context.stdout("Masked \(svc)\n"); return 0
        case "unmask": context.stdout("Unmasked \(svc)\n"); return 0
        case "is-active": context.stdout("active\n"); return 0
        case "is-enabled": context.stdout("enabled\n"); return 0
        case "is-failed": context.stdout("inactive\n"); return 1
        case "list-units", "list-unit-files":
            context.stdout("UNIT                     LOAD   ACTIVE SUB     DESCRIPTION\n")
            context.stdout("termious.service         loaded active running Termious shell\n")
            context.stdout("aero.service             loaded active running Aero package manager\n")
            context.stdout("network.service           loaded active running Network manager\n")
            context.stdout("\n3 loaded units listed.\n"); return 0
        case "list-timers": context.stdout("NEXT             LEFT     LAST             UNIT\n"); context.stdout("--               --       --               --\n"); return 0
        case "list-sockets": context.stdout("LISTEN           UNIT\n"); context.stdout("/var/run/app     app.socket\n"); return 0
        case "show": context.stdout("Id=termious.service\nActiveState=active\nSubState=running\n"); return 0
        case "cat": context.stdout("[Unit]\nDescription=\(svc)\n[Service]\nExecStart=/bin/\(svc)\n"); return 0
        case "daemon-reload", "daemon-reexec": context.stdout("Reloaded daemon\n"); return 0
        case "reset-failed": context.stdout("Reset\n"); return 0
        case "suspend": context.stdout("Suspending...\n"); return 0
        case "hibernate": context.stdout("Hibernating...\n"); return 0
        case "reboot": context.stdout("\u{001B}]REBOOT\u{0007}"); return 0
        case "poweroff", "halt": context.stdout("Powering off...\n"); return 0
        case "help", "-h": context.stdout("systemctl: start stop restart reload status enable disable mask unmask is-active is-enabled is-failed list-units list-timers list-sockets show cat daemon-reload reset-failed suspend hibernate reboot poweroff halt\n"); return 0
        default: context.stderr("systemctl: unknown command '\(sub)'\n"); return 1
        }
    }
}

/// `journalctl` - query the journal (simulated).
struct JournalctlCommand: BuiltinCommand {
    let name = "journalctl"
    let summary = "Query the systemd journal (simulated)"
    let usage = "journalctl [-u service] [-n N] [--since time]"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        var svc: String? = nil; var n = 10
        for (i, a) in arguments.enumerated() {
            if a == "-u" && i + 1 < arguments.count { svc = arguments[i + 1] }
            else if a == "-n" && i + 1 < arguments.count { n = Int(arguments[i + 1]) ?? 10 }
        }
        let prefix = svc == nil ? "" : "(\(svc!)) "
        for i in 0..<min(n, 5) {
            context.stdout("\(ISO8601DateFormatter().string(from: Date().addingTimeInterval(-Double(i * 60)))) \(prefix)termious[\(i)]: session active, all systems nominal\n")
        }
        return 0
    }
}

/// `loginctl` - control login sessions (simulated).
struct LoginctlCommand: BuiltinCommand {
    let name = "loginctl"
    let summary = "Control login sessions (simulated)"
    let usage = "loginctl [list-sessions|show-session|lock|unlock]"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        let sub = arguments.first ?? "list-sessions"
        switch sub {
        case "list-sessions":
            context.stdout("SESSION  UID USER   SEAT  TTY\n")
            context.stdout("    1    501 mobile seat0 tty1\n"); return 0
        case "list-users":
            context.stdout("UID USER\n501 mobile\n0 root\n"); return 0
        case "show-session":
            context.stdout("Id=1\nUID=501\nUser=mobile\nState=active\nType=tty\n"); return 0
        case "lock", "unlock": context.stdout("\(sub == "lock" ? "Locked" : "Unlocked") session\n"); return 0
        case "activate": context.stdout("Activated\n"); return 0
        case "terminate": context.stdout("Terminated\n"); return 0
        case "help", "-h": context.stdout("loginctl: list-sessions list-users show-session lock unlock activate terminate\n"); return 0
        default: context.stderr("loginctl: unknown '\(sub)'\n"); return 1
        }
    }
}

/// `resolvectl` - DNS resolver control (simulated).
struct ResolvectlCommand: BuiltinCommand {
    let name = "resolvectl"
    let summary = "DNS resolver control (simulated)"
    let usage = "resolvectl [status|query|dns]"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        let sub = arguments.first ?? "status"
        switch sub {
        case "status":
            context.stdout("Global: 8.8.8.8 1.1.1.1\nLink 2 (en0): 192.168.1.1\nLink 3 (pdp_ip0): 10.0.0.1\n"); return 0
        case "query":
            guard let host = arguments.dropFirst().first else { context.stderr("resolvectl: missing host\n"); return 1 }
            context.stdout("\(host): 93.184.216.34 -- link: en0\n"); return 0
        case "dns":
            if arguments.count > 1 { context.stdout("Set DNS: \(arguments.dropFirst().joined(separator: " "))\n") }
            else { context.stdout("8.8.8.8\n1.1.1.1\n") }; return 0
        case "flush-caches": context.stdout("Flushed DNS caches\n"); return 0
        case "help", "-h": context.stdout("resolvectl: status query dns flush-caches\n"); return 0
        default: context.stderr("resolvectl: unknown '\(sub)'\n"); return 1
        }
    }
}

/// `localectl` - locale control.
struct LocalectlCommand: BuiltinCommand {
    let name = "localectl"
    let summary = "Control locale settings (simulated)"
    let usage = "localectl [status|set-locale|list-locales]"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        let sub = arguments.first ?? "status"
        switch sub {
        case "status":
            context.stdout("   System Locale: LANG=en_US.UTF-8\n       VC Keymap: us\n      X11 Layout: us\n"); return 0
        case "set-locale":
            if let val = arguments.dropFirst().first { context.stdout("Locale set to: \(val)\n") }; return 0
        case "list-locales":
            context.stdout("en_US.UTF-8\nen_GB.UTF-8\nfr_FR.UTF-8\nde_DE.UTF-8\nes_ES.UTF-8\nja_JP.UTF-8\nar_SA.UTF-8\nzh_CN.UTF-8\n"); return 0
        case "set-keymap": context.stdout("Keymap set\n"); return 0
        case "help", "-h": context.stdout("localectl: status set-locale list-locales set-keymap\n"); return 0
        default: context.stderr("localectl: unknown '\(sub)'\n"); return 1
        }
    }
}

/// `systemd-analyze` - boot performance analysis (simulated).
struct SystemdAnalyzeCommand: BuiltinCommand {
    let name = "systemd-analyze"
    let summary = "Analyze boot performance (simulated)"
    let usage = "systemd-analyze [time|blame|critical-chain]"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        let sub = arguments.first ?? "time"
        switch sub {
        case "time":
            context.stdout("Startup finished in 0.234s (kernel) + 1.234s (userspace) = 1.468s\n"); return 0
        case "blame":
            context.stdout("1.200s aero.service\n0.500s termious.service\n0.100s network.service\n"); return 0
        case "critical-chain":
            context.stdout("graphical.target @1.234s\n\u{00B7}termious.service @1.100s + 0.100s\n"); return 0
        case "plot": context.stdout("Wrote plot.svg (simulated)\n"); return 0
        case "help", "-h": context.stdout("systemd-analyze: time blame critical-chain plot\n"); return 0
        default: context.stderr("systemd-analyze: unknown '\(sub)'\n"); return 1
        }
    }
}

/// `crontab` - schedule commands (simulated).
struct CrontabCommand: BuiltinCommand {
    let name = "crontab"
    let summary = "Schedule periodic commands (simulated)"
    let usage = "crontab [-l|-e|-r]"
    var operands: [Operand] {[
        Operand(name: "flag", description: "-l list, -e edit, -r remove", required: true, type: .string),
    ]}
    static var entries: [String] = []
    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let flag = arguments.first else { context.stderr("crontab: missing flag\n"); return 1 }
        switch flag {
        case "-l":
            if CrontabCommand.entries.isEmpty { context.stdout("no crontab for mobile\n") }
            else { context.stdout(CrontabCommand.entries.joined(separator: "\n") + "\n") }; return 0
        case "-e":
            context.stdout("\u{001B}]TINEO_EDIT\u{0007}cron:\(CrontabCommand.entries.joined(separator: "\n"))\u{0007}"); return 0
        case "-r":
            CrontabCommand.entries.removeAll(); context.stdout("Crontab removed\n"); return 0
        case "-h", "--help": context.stdout("crontab: -l list, -e edit, -r remove\n"); return 0
        default: context.stderr("crontab: unknown flag '\(flag)'\n"); return 1
        }
    }
}

/// `at` - schedule one-time commands (simulated).
struct AtCommand: BuiltinCommand {
    let name = "at"
    let summary = "Schedule one-time commands (simulated)"
    let usage = "at <time>"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let time = arguments.first else { context.stderr("at: missing time\n"); return 1 }
        context.stdout("job 1 at \(time)\n"); return 0
    }
}

/// `atq` - list scheduled jobs.
struct AtqCommand: BuiltinCommand {
    let name = "atq"
    let summary = "List scheduled at jobs (simulated)"
    let usage = "atq"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("1   \(ISO8601DateFormatter().string(from: Date()))  a mobile\n"); return 0
    }
}

/// `atrm` - remove scheduled jobs.
struct AtrmCommand: BuiltinCommand {
    let name = "atrm"
    let summary = "Remove scheduled at jobs (simulated)"
    let usage = "atrm <job-id>"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("Removed job \(arguments.first ?? "?")\n"); return 0
    }
}

/// `anacron` - run commands periodically (simulated).
struct AnacronCommand: BuiltinCommand {
    let name = "anacron"
    let summary = "Run commands periodically (simulated)"
    let usage = "anacron [-s] [-d]"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("Anacron started. Jobs queued.\n"); return 0
    }
}

/// `coredumpctl` - manage core dumps (simulated).
struct CoredumpctlCommand: BuiltinCommand {
    let name = "coredumpctl"
    let summary = "Manage core dumps (simulated)"
    let usage = "coredumpctl [list|info]"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        if arguments.first == "list" || arguments.isEmpty {
            context.stdout("TIME                       PID  UID  GID SIG COREFILE EXE\n")
            context.stdout("(none)\n")
        }; return 0
    }
}

/// `busctl` - introspect the bus (simulated).
struct BusctlCommand: BuiltinCommand {
    let name = "busctl"
    let summary = "Introspect the bus (simulated)"
    let usage = "busctl [list|status]"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("NAME                                  PID PROCESS\n")
        context.stdout(":1.1                                  42 termious\n")
        context.stdout("org.freedesktop.DBus                   - -\n"); return 0
    }
}

/// `machinectl` - control virtual machines (simulated).
struct MachinectlCommand: BuiltinCommand {
    let name = "machinectl"
    let summary = "Control VMs/containers (simulated)"
    let usage = "machinectl [list|status]"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("MACHINE CLASS SERVICE OS VERSION ADDRS\n")
        context.stdout("0 machines listed.\n"); return 0
    }
}

/// `journalctl -f` handled above. Add `dmesg` - done already.

/// `useradd` - add a user (simulated).
struct UseraddCommand: BuiltinCommand {
    let name = "useradd"
    let summary = "Create a new user (simulated)"
    let usage = "useradd [-m] <username>"
    var operands: [Operand] {[
        Operand(name: "username", description: "Username to create", required: true, type: .string),
    ]}
    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let name = arguments.last else { context.stderr("useradd: missing username\n"); return 1 }
        context.stdout("User '\(name)' created (UID=\(Int.random(in: 1000...9999)))\n"); return 0
    }
}

/// `userdel` - delete a user (simulated).
struct UserdelCommand: BuiltinCommand {
    let name = "userdel"
    let summary = "Delete a user (simulated)"
    let usage = "userdel [-r] <username>"
    var operands: [Operand] {[
        Operand(name: "username", description: "Username to delete", required: true, type: .string),
    ]}
    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let name = arguments.last else { context.stderr("userdel: missing username\n"); return 1 }
        context.stdout("User '\(name)' deleted\n"); return 0
    }
}

/// `usermod` - modify a user (simulated).
struct UsermodCommand: BuiltinCommand {
    let name = "usermod"
    let summary = "Modify a user (simulated)"
    let usage = "usermod [-aG group] <username>"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("User modified\n"); return 0
    }
}

/// `groupadd` - add a group (simulated).
struct GroupaddCommand: BuiltinCommand {
    let name = "groupadd"
    let summary = "Create a group (simulated)"
    let usage = "groupadd <groupname>"
    var operands: [Operand] {[
        Operand(name: "groupname", description: "Group name to create", required: true, type: .string),
    ]}
    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let name = arguments.first else { context.stderr("groupadd: missing name\n"); return 1 }
        context.stdout("Group '\(name)' created (GID=\(Int.random(in: 1000...9999)))\n"); return 0
    }
}

/// `groupdel` - delete a group (simulated).
struct GroupdelCommand: BuiltinCommand {
    let name = "groupdel"
    let summary = "Delete a group (simulated)"
    let usage = "groupdel <groupname>"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("Group deleted\n"); return 0
    }
}

/// `groupmod` - modify a group (simulated).
struct GroupmodCommand: BuiltinCommand {
    let name = "groupmod"
    let summary = "Modify a group (simulated)"
    let usage = "groupmod -n <newname> <oldname>"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("Group modified\n"); return 0
    }
}

/// `su` - switch user (simulated, uses password).
struct SuCommand: BuiltinCommand {
    let name = "su"
    let summary = "Switch user (simulated)"
    let usage = "su [username]"
    var operands: [Operand] {[
        Operand(name: "username", description: "User to switch to (defaults to root)", required: false, type: .string),
    ]}
    func run(arguments: [String], context: CommandContext) -> Int32 {
        let user = arguments.first ?? "root"
        if user == "root" {
            context.stdout("\u{001B}]SUDO_PROMPT\u{0007}su - \(user)\n")
        } else {
            context.stdout("Password: (simulated)\n")
            context.stdout("Switched to \(user)\n")
        }
        return 0
    }
}

/// `runuser` - run a command as another user (simulated).
struct RunuserCommand: BuiltinCommand {
    let name = "runuser"
    let summary = "Run a command as another user (simulated)"
    let usage = "runuser -u <user> -- <command>"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("runuser: switching user\n")
        return 0
    }
}

/// `nice` - set process priority (simulated).
struct NiceCommand: BuiltinCommand {
    let name = "nice"
    let summary = "Set process priority (simulated)"
    let usage = "nice [-n N] <command>"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        var n = 10
        var cmd: [String] = []
        var i = 0
        while i < arguments.count {
            if arguments[i] == "-n" && i + 1 < arguments.count { n = Int(arguments[i + 1]) ?? 10; i += 2 }
            else { cmd.append(arguments[i]); i += 1 }
        }
        if !cmd.isEmpty { context.stdout("\u{001B}]XARGS\u{0007}\(cmd.joined(separator: " "))\u{0007}") }
        return 0
    }
}

/// `renice` - change priority (simulated).
struct ReniceCommand: BuiltinCommand {
    let name = "renice"
    let summary = "Change process priority (simulated)"
    let usage = "renice -n N -p PID"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("Priority updated\n"); return 0
    }
}

/// `chroot` - change root (simulated).
struct ChrootCommand: BuiltinCommand {
    let name = "chroot"
    let summary = "Change root directory (simulated)"
    let usage = "chroot <dir> [command]"
    var operands: [Operand] {[
        Operand(name: "dir", description: "Directory to use as new root", required: true, type: .directory),
        Operand(name: "command", description: "Command to run in chroot", required: false, type: .string),
    ]}
    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let dir = arguments.first else { context.stderr("chroot: missing directory\n"); return 1 }
        if let url = context.fs.resolve(dir) {
            let logical = context.fs.logicalPath(of: url)
            context.stdout("chroot: root changed to \(logical)\n")
        }; return 0
    }
}

/// `source` / `.` - execute a file in the current shell.
struct SourceCommand: BuiltinCommand {
    let name = "source"
    let summary = "Execute commands from a file"
    let usage = "source <file>"
    var operands: [Operand] {[
        Operand(name: "file", description: "Script file to execute in current shell", required: true, type: .file),
    ]}
    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let file = arguments.first, let url = context.fs.resolve(file),
              let data = try? Data(contentsOf: url), let content = String(data: data, encoding: .utf8) else {
            context.stderr("source: cannot read '\(arguments.first ?? "")'\n"); return 1
        }
        context.stdout("\u{001B}]SOURCE_EXEC\u{0007}\(content.replacingOccurrences(of: "\n", with: ";"))\u{0007}")
        return 0
    }
}

/// `eval` - evaluate arguments as a command.
struct EvalCommand: BuiltinCommand {
    let name = "eval"
    let summary = "Evaluate arguments as a command"
    let usage = "eval <command...>"
    var operands: [Operand] {[
        Operand(name: "command", description: "Command string to evaluate", required: true, type: .string),
    ]}
    func run(arguments: [String], context: CommandContext) -> Int32 {
        let cmd = arguments.joined(separator: " ")
        if !cmd.isEmpty { context.stdout("\u{001B}]XARGS\u{0007}\(cmd)\u{0007}") }
        return 0
    }
}

/// `exec` - replace shell with a command (we just run it).
struct ExecCommand: BuiltinCommand {
    let name = "exec"
    let summary = "Execute a command replacing the shell"
    let usage = "exec <command...>"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        if !arguments.isEmpty { context.stdout("\u{001B}]XARGS\u{0007}\(arguments.joined(separator: " "))\u{0007}") }
        return 0
    }
}

/// `wait` - wait for a process (simulated).
struct WaitCommand: BuiltinCommand {
    let name = "wait"
    let summary = "Wait for a process (simulated)"
    let usage = "wait [PID]"
    func run(arguments: [String], context: CommandContext) -> Int32 { return 0 }
}

/// `logout` / `exit` - end the session.
struct LogoutCommand: BuiltinCommand {
    let name = "logout"
    let summary = "End the shell session"
    let usage = "logout"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("\u{0004}"); return 0
    }
}

/// `login` - begin a new session (simulated).
struct LoginCommand: BuiltinCommand {
    let name = "login"
    let summary = "Begin a new session (simulated)"
    let usage = "login [username]"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        let user = arguments.first ?? "mobile"
        context.stdout("Welcome, \(user)!\n"); return 0
    }
}

/// `newgrp` - change primary group (simulated).
struct NewgrpCommand: BuiltinCommand {
    let name = "newgrp"
    let summary = "Change primary group (simulated)"
    let usage = "newgrp <group>"
    func run(arguments: [String], context: CommandContext) -> Int32 { return 0 }
}

/// `fallocate` - preallocate file space.
struct FallocateCommand: BuiltinCommand {
    let name = "fallocate"
    let summary = "Preallocate file space"
    let usage = "fallocate -l <size> <file>"
    var operands: [Operand] {[
        Operand(name: "size", description: "Size in bytes to allocate (with -l)", required: true, type: .number),
        Operand(name: "file", description: "File to allocate space for", required: true, type: .file),
    ]}
    func run(arguments: [String], context: CommandContext) -> Int32 {
        var size: Int? = nil; var file: String? = nil
        for (i, a) in arguments.enumerated() {
            if a == "-l" && i + 1 < arguments.count { size = Int(arguments[i + 1]) }
            else if !a.hasPrefix("-") { file = a }
        }
        guard let s = size, let f = file, let url = context.fs.resolve(f) else { context.stderr("fallocate: invalid args\n"); return 1 }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let data = Data(repeating: 0, count: s)
        try? data.write(to: url)
        return 0
    }
}

/// `rename` - rename files (bulk).
struct RenameCommand: BuiltinCommand {
    let name = "rename"
    let summary = "Rename multiple files"
    let usage = "rename <from> <to> <files...>"
    var operands: [Operand] {[
        Operand(name: "from", description: "Substring to replace", required: true, type: .string),
        Operand(name: "to", description: "Replacement string", required: true, type: .string),
        Operand(name: "files", description: "File(s) to rename", required: true, type: .file),
    ]}
    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard arguments.count >= 3 else { context.stderr("rename: need from to files...\n"); return 1 }
        let from = arguments[0]; let to = arguments[1]
        let files = Array(arguments.dropFirst(2))
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        var count = 0
        for f in files {
            guard let url = context.fs.resolve(f) else { continue }
            let newName = (url.lastPathComponent as NSString).replacingOccurrences(of: from, with: to)
            let dest = url.deletingLastPathComponent().appendingPathComponent(newName)
            try? FileManager.default.moveItem(at: url, to: dest)
            count += 1
        }
        context.stdout("Renamed \(count) file(s)\n"); return 0
    }
}

/// `findmnt` - find mounted filesystems.
struct FindmntCommand: BuiltinCommand {
    let name = "findmnt"
    let summary = "Find mounted filesystems"
    let usage = "findmnt [mountpoint]"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("TARGET  SOURCE   FSTYPE OPTIONS\n")
        context.stdout("/       aero-root aero   rw,nosuid,nodev\n")
        context.stdout("/proc   proc     proc   rw,nosuid,nodev\n")
        context.stdout("/tmp    tmpfs    tmpfs  rw,nosuid,nodev\n"); return 0
    }
}

/// `lslocks` - list file locks (simulated).
struct LslocksCommand: BuiltinCommand {
    let name = "lslocks"
    let summary = "List file locks (simulated)"
    let usage = "lslocks"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("COMMAND PID TYPE  SOURCE MODE\n")
        context.stdout("termious  1 POSIX /      READ\n"); return 0
    }
}

/// `fuser` - identify processes using files (simulated).
struct FuserCommand: BuiltinCommand {
    let name = "fuser"
    let summary = "Identify processes using files (simulated)"
    let usage = "fuser <file>"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let f = arguments.first else { context.stderr("fuser: missing file\n"); return 1 }
        context.stdout("\(f):  1\n"); return 0
    }
}

/// `lsattr` - list file attributes.
struct LsattrCommand: BuiltinCommand {
    let name = "lsattr"
    let summary = "List file attributes"
    let usage = "lsattr [file...]"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let files = arguments.isEmpty ? ["."] : arguments
        for f in files {
            guard let url = context.fs.resolve(f) else { continue }
            let meta = FileMetadataStore.shared.get(context.fs.logicalPath(of: url))
            context.stdout("------------- \(meta.owner) \(url.lastPathComponent)\n")
        }
        return 0
    }
}

/// `chattr` - change file attributes (simulated).
struct ChattrCommand: BuiltinCommand {
    let name = "chattr"
    let summary = "Change file attributes (simulated)"
    let usage = "chattr <+-mode> <file>"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("chattr: attributes updated\n"); return 0
    }
}

/// `getfacl` - get file ACL.
struct GetfaclCommand: BuiltinCommand {
    let name = "getfacl"
    let summary = "Get file ACL"
    let usage = "getfacl <file>"
    var operands: [Operand] {[
        Operand(name: "file", description: "File to show ACL for", required: true, type: .file),
    ]}
    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let f = arguments.first, let url = context.fs.resolve(f) else { context.stderr("getfacl: missing file\n"); return 1 }
        let meta = FileMetadataStore.shared.get(context.fs.logicalPath(of: url))
        context.stdout("# file: \(url.lastPathComponent)\n")
        context.stdout("# owner: \(meta.owner)\n")
        context.stdout("# group: \(meta.group)\n")
        context.stdout("user::rw-\ngroup::r--\nother::r--\n"); return 0
    }
}

/// `setfacl` - set file ACL (simulated).
struct SetfaclCommand: BuiltinCommand {
    let name = "setfacl"
    let summary = "Set file ACL (simulated)"
    let usage = "setfacl -m <acl> <file>"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("ACL updated\n"); return 0
    }
}

/// `mkfs` - create a filesystem (simulated).
struct MkfsCommand: BuiltinCommand {
    let name = "mkfs"
    let summary = "Create a filesystem (simulated)"
    let usage = "mkfs -t <type> <device>"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("mke2fs 1.46.0\nCreating filesystem...\nFilesystem created.\n"); return 0
    }
}

/// `locale` - display locale settings.
struct LocaleCmdCommand: BuiltinCommand {
    let name = "locale"
    let summary = "Display locale settings"
    let usage = "locale [-a]"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        if arguments.contains("-a") {
            context.stdout("en_US.UTF-8\nen_GB.UTF-8\nfr_FR.UTF-8\nde_DE.UTF-8\nes_ES.UTF-8\nja_JP.UTF-8\nar_SA.UTF-8\nzh_CN.UTF-8\nC\nPOSIX\n")
        } else {
            context.stdout("LANG=en_US.UTF-8\nLC_CTYPE=en_US.UTF-8\nLC_TIME=en_US.UTF-8\nLC_ALL=\n")
        }
        return 0
    }
}

/// `localedef` - define locale (simulated).
struct LocaledefCommand: BuiltinCommand {
    let name = "localedef"
    let summary = "Define a locale (simulated)"
    let usage = "localedef <name>"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("Locale defined\n"); return 0
    }
}

/// `logname` - print login name.
struct LognameCommand: BuiltinCommand {
    let name = "logname"
    let summary = "Print the login name"
    let usage = "logname"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("mobile\n"); return 0
    }
}

/// `groups` - print groups.
struct GroupsCommand: BuiltinCommand {
    let name = "groups"
    let summary = "Print group memberships"
    let usage = "groups [user]"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("staff wheel admin\n"); return 0
    }
}

/// `getent` - get entries from administrative databases.
struct GetentCommand: BuiltinCommand {
    let name = "getent"
    let summary = "Get database entries"
    let usage = "getent <database> [key]"
    var operands: [Operand] {[
        Operand(name: "database", description: "Database: passwd, group, hosts, services", required: true, type: .string),
        Operand(name: "key", description: "Key to look up", required: false, type: .string),
    ]}
    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let db = arguments.first else { context.stderr("getent: missing database\n"); return 1 }
        switch db {
        case "passwd": context.stdout("mobile:x:501:20:Mobile User:/home/mobile:/bin/termious\n"); return 0
        case "group": context.stdout("staff:x:20:mobile\nwheel:x:0:root\n"); return 0
        case "hosts": context.stdout("127.0.0.1       localhost\n192.168.1.100  termious\n"); return 0
        case "services": context.stdout("ssh 22/tcp\nhttp 80/tcp\nhttps 443/tcp\n"); return 0
        default: context.stderr("getent: unknown database\n"); return 1
        }
    }
}

/// `gpasswd` - administer /etc/group (simulated).
struct GpasswdCommand: BuiltinCommand {
    let name = "gpasswd"
    let summary = "Administer groups (simulated)"
    let usage = "gpasswd -a <user> <group>"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("Group updated\n"); return 0
    }
}

/// `pwck` - verify password file integrity (simulated).
struct PwckCommand: BuiltinCommand {
    let name = "pwck"
    let summary = "Verify password files (simulated)"
    let usage = "pwck"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("pwck: files OK\n"); return 0
    }
}

/// `grpck` - verify group file integrity (simulated).
struct GrpckCommand: BuiltinCommand {
    let name = "grpck"
    let summary = "Verify group files (simulated)"
    let usage = "grpck"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("grpck: files OK\n"); return 0
    }
}

/// `vipw` / `vigr` - edit password/group files (simulated).
struct VipwCommand: BuiltinCommand {
    let name = "vipw"
    let summary = "Edit the password file (simulated)"
    let usage = "vipw"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("\u{001B}]TINEO_EDIT\u{0007}passwd:mobile:x:501:20:Mobile User:/home/mobile:/bin/termious\nroot:x:0:0:Super User:/root:/bin/termious\u{0007}"); return 0
    }
}

/// `compact` - compress files (simulated).
struct CompactCommand: BuiltinCommand {
    let name = "compact"
    let summary = "Compress files (simulated)"
    let usage = "compact <file>"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("Compressed \(arguments.first ?? "")\n"); return 0
    }
}

/// `batch` - schedule batch commands (simulated).
struct BatchCommand: BuiltinCommand {
    let name = "batch"
    let summary = "Schedule batch commands (simulated)"
    let usage = "batch"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("Job queued\n"); return 0
    }
}

/// `jobs` - list active jobs (simulated).
struct JobsCommand: BuiltinCommand {
    let name = "jobs"
    let summary = "List active jobs (simulated)"
    let usage = "jobs"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("No active jobs\n"); return 0
    }
}

/// `disown` - remove a job from the shell (simulated).
struct DisownCommand: BuiltinCommand {
    let name = "disown"
    let summary = "Remove a job (simulated)"
    let usage = "disown [job]"
    func run(arguments: [String], context: CommandContext) -> Int32 { return 0 }
}

/// `trap` - trap signals (simulated).
struct TrapCommand: BuiltinCommand {
    let name = "trap"
    let summary = "Trap signals (simulated)"
    let usage = "trap <command> <signal>"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("Trap set\n"); return 0
    }
}

/// `suspend` - suspend the shell (simulated).
struct SuspendCommand: BuiltinCommand {
    let name = "suspend"
    let summary = "Suspend the shell (simulated)"
    let usage = "suspend"
    func run(arguments: [String], context: CommandContext) -> Int32 { return 0 }
}

/// `chfn` - change finger info (simulated).
struct ChfnCommand: BuiltinCommand {
    let name = "chfn"
    let summary = "Change user info (simulated)"
    let usage = "chfn [username]"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("User info updated\n"); return 0
    }
}

/// `chsh` - change login shell (simulated).
struct ChshCommand: BuiltinCommand {
    let name = "chsh"
    let summary = "Change login shell (simulated)"
    let usage = "chsh -s <shell> [user]"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("Shell changed to /bin/termious\n"); return 0
    }
}