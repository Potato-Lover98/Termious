import Foundation

/// `aero` - a custom package manager that downloads from GitHub.
///
/// Usage:
///   aero install <owner/repo> [--name x] [--ref branch]   Download & extract a repo
///   aero search <query>                                    Search GitHub repos
///   aero list                                              List installed packages
///   aero info <name>                                       Show package details
///   aero delete <name>                                     Remove an installed package
///   aero update <name>                                     Re-download latest
///   aero files <name>                                      List files in a package
///   aero path <name>                                       Print install path
struct AeroCommand: BuiltinCommand {
    let name = "aero"
    let summary = "GitHub package manager"
    let usage = """
    aero install <owner/repo> [--name x] [--ref branch]
    aero search <query>
    aero list
    aero info <name>
    aero delete <name>
    aero update <name>
    aero files <name>
    aero path <name>
    """
    var operands: [Operand] {[
        Operand(name: "subcommand", description: "install, search, list, info, delete, update, files, path", required: true, type: .string),
        Operand(name: "target", description: "repo, query, or package name", required: false, type: .string),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let subcommand = arguments.first else {
            context.stderr("aero: missing subcommand. Usage:\n\(usage)\n")
            return 1
        }
        let rest = Array(arguments.dropFirst())

        switch subcommand {
        case "install": return runInstall(rest, context: context)
        case "search": return runSearch(rest, context: context)
        case "list", "ls": return runList(context: context)
        case "info": return runInfo(rest, context: context)
        case "delete", "remove", "rm": return runDelete(rest, context: context)
        case "update": return runUpdate(rest, context: context)
        case "files": return runFiles(rest, context: context)
        case "path": return runPath(rest, context: context)
        case "help", "-h", "--help":
            context.stdout("aero - GitHub package manager\n\n\(usage)\n")
            return 0
        default:
            context.stderr("aero: unknown subcommand '\(subcommand)'\n")
            return 1
        }
    }

    // MARK: - install

    private func runInstall(_ args: [String], context: CommandContext) -> Int32 {
        var repo: String? = nil
        var name: String? = nil
        var ref: String? = nil
        var i = 0
        while i < args.count {
            let a = args[i]
            if a == "--name" && i + 1 < args.count {
                name = args[i + 1]; i += 2
            } else if a == "--ref" && i + 1 < args.count {
                ref = args[i + 1]; i += 2
            } else if !a.hasPrefix("-") {
                repo = a; i += 1
            } else { i += 1 }
        }
        guard let repo = repo, !repo.isEmpty else {
            context.stderr("aero install: missing <owner/repo>\n")
            return 1
        }
        let group = DispatchGroup()
        var exitCode: Int32 = 0
        group.enter()
        AeroPackageManager.shared.install(
            repo: repo, ref: ref, name: name, fs: context.fs,
            progress: { msg in context.stdout(msg + "\n") }
        ) { result in
            switch result {
            case .success(let pkg):
                context.stdout("Successfully installed \(pkg.name) (\(pkg.repo))\n")
                context.stdout("Location: \(pkg.localPath)\n")
            case .failure(let err):
                context.stderr("aero install failed: \(err)\n")
                exitCode = 1
            }
            group.leave()
        }
        group.wait()
        return exitCode
    }

    // MARK: - search

    private func runSearch(_ args: [String], context: CommandContext) -> Int32 {
        let query = args.joined(separator: " ")
        guard !query.isEmpty else {
            context.stderr("aero search: missing query\n")
            return 1
        }
        context.stdout("Searching GitHub for '\(query)'...\n\n")
        let group = DispatchGroup()
        var exitCode: Int32 = 0
        group.enter()
        AeroPackageManager.shared.search(query: query) { result in
            switch result {
            case .success(let results):
                if results.isEmpty {
                    context.stdout("No results found.\n")
                } else {
                    for (idx, r) in results.enumerated() {
                        let stars = String(format: "%6d", r.stars)
                        context.stdout("\(String(format: "%2d", idx + 1)). \(stars)★  \(r.repo)\n")
                        if !r.desc.isEmpty {
                            context.stdout("                \(r.desc)\n")
                        }
                    }
                    context.stdout("\nInstall with: aero install <owner/repo>\n")
                }
            case .failure(let err):
                context.stderr("aero search failed: \(err)\n")
                exitCode = 1
            }
            group.leave()
        }
        group.wait()
        return exitCode
    }

    // MARK: - list

    private func runList(context: CommandContext) -> Int32 {
        let pkgs = AeroPackageManager.shared.listInstalled()
        if pkgs.isEmpty {
            context.stdout("No packages installed. Use 'aero install <owner/repo>'.\n")
            return 0
        }
        context.stdout(String(format: "%-16s %-28s %-10s %s\n",
                              "NAME", "REPO", "REF", "INSTALLED"))
        for pkg in pkgs {
            let dateStr = ISO8601DateFormatter().string(from: pkg.installedAt)
                .replacingOccurrences(of: "T", with: " ").replacingOccurrences(of: "Z", with: "")
            context.stdout(String(format: "%-16s %-28s %-10s %s\n",
                                  pkg.name, pkg.repo, pkg.ref, String(dateStr.prefix(16))))
        }
        return 0
    }

    // MARK: - info

    private func runInfo(_ args: [String], context: CommandContext) -> Int32 {
        guard let name = args.first else {
            context.stderr("aero info: missing package name\n")
            return 1
        }
        guard let pkg = AeroPackageManager.shared.packageInfo(name: name) else {
            context.stderr("aero: package '\(name)' not found\n")
            return 1
        }
        context.stdout("Name:       \(pkg.name)\n")
        context.stdout("Repo:       \(pkg.repo)\n")
        context.stdout("Ref:        \(pkg.ref)\n")
        context.stdout("Location:   \(pkg.localPath)\n")
        if let desc = pkg.description, !desc.isEmpty {
            context.stdout("Description: \(desc)\n")
        }
        if let sha = pkg.commitSha {
            context.stdout("Commit:     \(sha)\n")
        }
        context.stdout("Installed:  \(ISO8601DateFormatter().string(from: pkg.installedAt))\n")
        return 0
    }

    // MARK: - delete

    private func runDelete(_ args: [String], context: CommandContext) -> Int32 {
        guard let name = args.first else {
            context.stderr("aero delete: missing package name\n")
            return 1
        }
        if AeroPackageManager.shared.uninstall(name: name, fs: context.fs) {
            context.stdout("Removed \(name)\n")
            return 0
        } else {
            context.stderr("aero: package '\(name)' not found\n")
            return 1
        }
    }

    // MARK: - update

    private func runUpdate(_ args: [String], context: CommandContext) -> Int32 {
        guard let name = args.first else {
            context.stderr("aero update: missing package name\n")
            return 1
        }
        guard let pkg = AeroPackageManager.shared.packageInfo(name: name) else {
            context.stderr("aero: package '\(name)' not found\n")
            return 1
        }
        let group = DispatchGroup()
        var exitCode: Int32 = 0
        group.enter()
        AeroPackageManager.shared.install(
            repo: pkg.repo, ref: pkg.ref, name: pkg.name, fs: context.fs,
            progress: { msg in context.stdout(msg + "\n") }
        ) { result in
            switch result {
            case .success:
                context.stdout("Updated \(name)\n")
            case .failure(let err):
                context.stderr("aero update failed: \(err)\n")
                exitCode = 1
            }
            group.leave()
        }
        group.wait()
        return exitCode
    }

    // MARK: - files

    private func runFiles(_ args: [String], context: CommandContext) -> Int32 {
        guard let name = args.first else {
            context.stderr("aero files: missing package name\n")
            return 1
        }
        guard AeroPackageManager.shared.packageInfo(name: name) != nil else {
            context.stderr("aero: package '\(name)' not found\n")
            return 1
        }
        let pkgDir = AeroPackageManager.shared.packageURL(name, in: context.fs)
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let fm = FileManager.default
        guard fm.fileExists(atPath: pkgDir.path) else {
            context.stderr("aero: package directory missing\n")
            return 1
        }
        context.stdout("Files in \(name):\n\n")
        let enumerator = fm.enumerator(atPath: pkgDir.path)
        var count = 0
        while let element = enumerator?.nextObject() as? String {
            let logical = context.fs.logicalPath(of: pkgDir.appendingPathComponent(element))
            context.stdout("  \(logical)\n")
            count += 1
        }
        context.stdout("\n\(count) file(s)\n")
        return 0
    }

    // MARK: - path

    private func runPath(_ args: [String], context: CommandContext) -> Int32 {
        guard let name = args.first else {
            context.stderr("aero path: missing package name\n")
            return 1
        }
        guard AeroPackageManager.shared.packageInfo(name: name) != nil else {
            context.stderr("aero: package '\(name)' not found\n")
            return 1
        }
        let pkgDir = AeroPackageManager.shared.packageURL(name, in: context.fs)
        context.stdout(context.fs.logicalPath(of: pkgDir) + "\n")
        return 0
    }
}