import Foundation

struct MkdirCommand: BuiltinCommand {
    let name = "mkdir"
    let summary = "Create directories"
    let usage = "mkdir [-p] dir..."
    var operands: [Operand] {[
        Operand(name: "dir", description: "Directory name(s) to create", required: true, type: .directory),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var makeParents = false
        var dirs: [String] = []
        for arg in arguments {
            if arg == "-p" { makeParents = true }
            else if arg.hasPrefix("-") {
                for f in arg.dropFirst() { if f == "p" { makeParents = true } }
            } else {
                dirs.append(arg)
            }
        }
        if dirs.isEmpty {
            context.stderr("mkdir: missing operand\n")
            return 1
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let fm = FileManager.default
        var hadError = false
        for d in dirs {
            guard let url = context.fs.resolve(d) else {
                context.stderr("mkdir: cannot create '\(d)'\n")
                hadError = true
                continue
            }
            do {
                if makeParents {
                    try fm.createDirectory(at: url, withIntermediateDirectories: true)
                } else {
                    try fm.createDirectory(at: url, withIntermediateDirectories: false)
                }
            } catch {
                context.stderr("mkdir: \(error.localizedDescription)\n")
                hadError = true
            }
        }
        return hadError ? 1 : 0
    }
}

struct RmCommand: BuiltinCommand {
    let name = "rm"
    let summary = "Remove files or directories"
    let usage = "rm [-r] [-f] path..."
    var operands: [Operand] {[
        Operand(name: "path", description: "File(s) or directory(s) to remove", required: true, type: .path),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var recursive = false
        var force = false
        var paths: [String] = []
        for arg in arguments {
            if arg.hasPrefix("-") {
                for f in arg.dropFirst() {
                    if f == "r" || f == "R" { recursive = true }
                    else if f == "f" { force = true }
                }
            } else {
                paths.append(arg)
            }
        }
        if paths.isEmpty {
            if !force { context.stderr("rm: missing operand\n") }
            return force ? 0 : 1
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let fm = FileManager.default
        var hadError = false
        for p in paths {
            guard let url = context.fs.resolve(p) else {
                if !force { context.stderr("rm: \(p): no such file\n") }
                hadError = !force
                continue
            }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else {
                if !force { context.stderr("rm: \(p): no such file\n") }
                hadError = !force
                continue
            }
            if isDir.boolValue && !recursive {
                context.stderr("rm: \(p): is a directory (use -r)\n")
                hadError = true
                continue
            }
            do {
                try fm.removeItem(at: url)
            } catch {
                if !force { context.stderr("rm: \(error.localizedDescription)\n") }
                hadError = !force
            }
        }
        return hadError ? 1 : 0
    }
}

struct CpCommand: BuiltinCommand {
    let name = "cp"
    let summary = "Copy files"
    let usage = "cp [-r] src... dst"
    var operands: [Operand] {[
        Operand(name: "src", description: "Source file(s) to copy", required: true, type: .path),
        Operand(name: "dst", description: "Destination path to copy to", required: true, type: .path),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var recursive = false
        var paths: [String] = []
        for arg in arguments {
            if arg.hasPrefix("-") {
                for f in arg.dropFirst() {
                    if f == "r" || f == "R" { recursive = true }
                }
            } else {
                paths.append(arg)
            }
        }
        guard paths.count >= 2 else {
            context.stderr("cp: usage: \(usage)\n")
            return 1
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let dst = paths.removeLast()
        let fm = FileManager.default
        var hadError = false

        let dstURL = context.fs.resolve(dst)
        guard let resolvedDst = dstURL else {
            context.stderr("cp: cannot resolve destination '\(dst)'\n")
            return 1
        }

        for src in paths {
            guard let srcURL = context.fs.resolve(src) else {
                context.stderr("cp: \(src): no such file\n")
                hadError = true
                continue
            }
            var isDir: ObjCBool = false
            fm.fileExists(atPath: srcURL.path, isDirectory: &isDir)
            if isDir.boolValue && !recursive {
                context.stderr("cp: \(src) is a directory (use -r)\n")
                hadError = true
                continue
            }
            let finalDst: URL
            var dstIsDir: ObjCBool = false
            if fm.fileExists(atPath: resolvedDst.path, isDirectory: &dstIsDir), dstIsDir.boolValue {
                finalDst = resolvedDst.appendingPathComponent(srcURL.lastPathComponent)
            } else {
                finalDst = resolvedDst
            }
            do {
                if fm.fileExists(atPath: finalDst.path) {
                    try fm.removeItem(at: finalDst)
                }
                try fm.copyItem(at: srcURL, to: finalDst)
            } catch {
                context.stderr("cp: \(error.localizedDescription)\n")
                hadError = true
            }
        }
        return hadError ? 1 : 0
    }
}

struct MvCommand: BuiltinCommand {
    let name = "mv"
    let summary = "Move or rename files"
    let usage = "mv src... dst"
    var operands: [Operand] {[
        Operand(name: "src", description: "Source file(s) to move", required: true, type: .path),
        Operand(name: "dst", description: "Destination path to move to", required: true, type: .path),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var paths: [String] = []
        for arg in arguments {
            if arg.hasPrefix("-") {} else { paths.append(arg) }
        }
        guard paths.count >= 2 else {
            context.stderr("mv: usage: \(usage)\n")
            return 1
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let dst = paths.removeLast()
        let fm = FileManager.default
        var hadError = false
        guard let resolvedDst = context.fs.resolve(dst) else {
            context.stderr("mv: cannot resolve destination '\(dst)'\n")
            return 1
        }
        for src in paths {
            guard let srcURL = context.fs.resolve(src) else {
                context.stderr("mv: \(src): no such file\n")
                hadError = true
                continue
            }
            let finalDst: URL
            var dstIsDir: ObjCBool = false
            if fm.fileExists(atPath: resolvedDst.path, isDirectory: &dstIsDir), dstIsDir.boolValue {
                finalDst = resolvedDst.appendingPathComponent(srcURL.lastPathComponent)
            } else {
                finalDst = resolvedDst
            }
            do {
                if fm.fileExists(atPath: finalDst.path) {
                    try fm.removeItem(at: finalDst)
                }
                try fm.moveItem(at: srcURL, to: finalDst)
            } catch {
                context.stderr("mv: \(error.localizedDescription)\n")
                hadError = true
            }
        }
        return hadError ? 1 : 0
    }
}

struct TouchCommand: BuiltinCommand {
    let name = "touch"
    let summary = "Create empty file or update timestamps"
    let usage = "touch file..."
    var operands: [Operand] {[
        Operand(name: "file", description: "File(s) to create or update timestamps", required: true, type: .file),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        if arguments.isEmpty {
            context.stderr("touch: missing operand\n")
            return 1
        }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let fm = FileManager.default
        var hadError = false
        for p in arguments {
            guard let url = context.fs.resolve(p) else {
                context.stderr("touch: cannot touch '\(p)'\n")
                hadError = true
                continue
            }
            if fm.fileExists(atPath: url.path) {
                try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
            } else {
                if !fm.createFile(atPath: url.path, contents: Data()) {
                    context.stderr("touch: cannot create '\(p)'\n")
                    hadError = true
                }
            }
        }
        return hadError ? 1 : 0
    }
}