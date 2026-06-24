import Foundation

/// `git` - basic git wrapper (status, log, init, add, commit - operates on aero-downloaded repos).
struct GitCommand: BuiltinCommand {
    let name = "git"
    let summary = "Distributed version control (simulated)"
    let usage = "git <subcommand> [args]"
    var operands: [Operand] {[
        Operand(name: "subcommand", description: "status, log, init, add, commit, clone, etc.", required: true, type: .string),
        Operand(name: "args", description: "Arguments for the git subcommand", required: false, type: .string),
    ]}
    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let sub = arguments.first else { context.stderr("git: missing subcommand\n"); return 1 }
        let rest = Array(arguments.dropFirst())
        switch sub {
        case "status": context.stdout("On branch main\nnothing to commit, working tree clean\n"); return 0
        case "log":
            context.stdout("commit a1b2c3d (HEAD -> main)\nAuthor: Termious <termious@local>\nDate:   \(ISO8601DateFormatter().string(from: Date()))\n\n    Initial commit\n"); return 0
        case "init":
            guard let path = rest.first ?? Optional("."), let url = context.fs.resolve(path) else { context.stderr("git: cannot resolve path\n"); return 1 }
            let gitDir = url.appendingPathComponent(".git")
            try? FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
            context.stdout("Initialized empty Git repository in \(gitDir.path)\n"); return 0
        case "add":
            context.stdout("Added \(rest.joined(separator: " "))\n"); return 0
        case "commit":
            var msg = ""
            for (i, a) in rest.enumerated() { if a == "-m" && i + 1 < rest.count { msg = rest[i + 1] } }
            context.stdout("[main \(String(UUID().uuidString.prefix(7)))] \(msg.isEmpty ? "commit" : msg)\n"); return 0
        case "clone":
            if let repo = rest.first {
                let name = (repo as NSString).lastPathComponent.replacingOccurrences(of: ".git", with: "")
                context.stdout("Cloning into '\(name)'...\n")
                context.stdout("\u{001B}]AERO_CLONE\u{0007}\(repo.replacingOccurrences(of: "https://github.com/", with: "").replacingOccurrences(of: ".git", with: ""))\u{0007}\(name)\u{0007}")
            }; return 0
        case "diff": context.stdout("No differences found\n"); return 0
        case "branch": context.stdout("* main\n  develop\n"); return 0
        case "checkout":
            context.stdout("Switched to branch '\(rest.first ?? "main")'\n"); return 0
        case "pull": context.stdout("Already up to date.\n"); return 0
        case "push": context.stdout("Everything up-to-date\n"); return 0
        case "remote":
            if rest.first == "add" { context.stdout("Remote added\n") }
            else if rest.first == "-v" { context.stdout("origin\thttps://github.com/termious/app (fetch)\norigin\thttps://github.com/termious/app (push)\n") }
            else { context.stdout("origin\n") }; return 0
        case "config":
            if rest.count >= 2 { context.stdout("\(rest[0]) = \(rest[1])\n") }
            else { context.stdout("user.name=Termious\nuser.email=termious@local\n") }; return 0
        case "merge": context.stdout("Merge made by recursive strategy\n"); return 0
        case "fetch": context.stdout("Fetching origin\n"); return 0
        case "reset": context.stdout("HEAD is now at a1b2c3d\n"); return 0
        case "revert": context.stdout("[main d4e5f6g] Revert\n"); return 0
        case "stash": context.stdout("Saved working directory\n"); return 0
        case "tag":
            if rest.isEmpty { context.stdout("v1.0.0\nv1.0.1\n") }
            else { context.stdout("Tag \(rest.first ?? "") created\n") }; return 0
        case "show": context.stdout("commit a1b2c3d\nAuthor: Termious\n\n    Initial commit\n"); return 0
        case "blame":
            guard let f = rest.first, let url = context.fs.resolve(f), let data = try? Data(contentsOf: url), let s = String(data: data, encoding: .utf8) else { context.stderr("git blame: cannot read\n"); return 1 }
            var n = 1
            for line in s.split(separator: "\n", omittingEmptySubsequences: false) {
                context.stdout(String(format: "a1b2c3d (%@ %5d) %@\n", "Termious", n, String(line))); n += 1
            }; return 0
        case "help", "-h", "--help":
            context.stdout("git: available subcommands: status log init add commit clone diff branch checkout pull push remote config merge fetch reset revert stash tag show blame\n"); return 0
        default: context.stderr("git: '\(sub)' is not a command. See 'git help'.\n"); return 1
        }
    }
}

/// `ssh-keygen` - generate SSH keys (simulated, stores key pair).
struct SshKeygenCommand: BuiltinCommand {
    let name = "ssh-keygen"
    let summary = "Generate SSH key pairs"
    let usage = "ssh-keygen [-t rsa] [-f file] [-C comment]"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        var keyType = "rsa"; var comment = "termious@local"; var outputFile: String? = nil
        var i = 0
        while i < arguments.count {
            let a = arguments[i]
            if a == "-t" && i + 1 < arguments.count { keyType = arguments[i + 1]; i += 2 }
            else if a == "-C" && i + 1 < arguments.count { comment = arguments[i + 1]; i += 2 }
            else if a == "-f" && i + 1 < arguments.count { outputFile = arguments[i + 1]; i += 2 }
            else { i += 1 }
        }
        let name = outputFile ?? "id_\(keyType)"
        guard let privURL = context.fs.resolve(name), let pubURL = context.fs.resolve(name + ".pub") else { context.stderr("ssh-keygen: cannot resolve\n"); return 1 }
        let started = context.fs.startRootAccess()
        defer { if started { context.fs.stopRootAccess() } }
        let privKey = "-----BEGIN \(keyType.uppercased()) PRIVATE KEY-----\n" + Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString() + "\n-----END \(keyType.uppercased()) PRIVATE KEY-----\n"
        let pubKey = "ssh-\(keyType) " + Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString() + " \(comment)\n"
        try? privKey.write(to: privURL, atomically: true, encoding: .utf8)
        try? pubKey.write(to: pubURL, atomically: true, encoding: .utf8)
        context.stdout("Generating public/private \(keyType) key pair.\n")
        context.stdout("Your identification has been saved in \(name)\n")
        context.stdout("Your public key has been saved in \(name).pub\n")
        return 0
    }
}

/// `nslookup` - DNS lookup via URLSession.
struct NslookupCommand: BuiltinCommand {
    let name = "nslookup"
    let summary = "Query DNS records"
    let usage = "nslookup <hostname> [server]"
    var operands: [Operand] {[
        Operand(name: "hostname", description: "Hostname to look up", required: true, type: .string),
        Operand(name: "server", description: "DNS server to query (optional)", required: false, type: .string),
    ]}
    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let host = arguments.first else { context.stderr("nslookup: missing host\n"); return 1 }
        let group = DispatchGroup(); var code: Int32 = 0; group.enter()
        DispatchQueue.global().async {
            context.stdout("Server:  8.8.8.8\nAddress: 8.8.8.8#53\n\n")
            context.stdout("Name:    \(host)\n")
            context.stdout("Address: ")
            if let url = URL(string: "https://dns.google/resolve?name=\(host)&type=A"),
               let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let answers = json["Answer"] as? [[String: Any]] {
                for ans in answers {
                    if let data = ans["data"] as? String, ans["type"] as? Int == 1 {
                        context.stdout("\(data)\n")
                        group.leave(); return
                    }
                }
            }
            context.stdout("\(host) - resolved\n")
            code = 0
            group.leave()
        }
        group.wait()
        return code
    }
}

/// `dig` - DNS lookup.
struct DigCommand: BuiltinCommand {
    let name = "dig"
    let summary = "DNS lookup utility"
    let usage = "dig <hostname> [type]"
    var operands: [Operand] {[
        Operand(name: "hostname", description: "Hostname to query", required: true, type: .string),
        Operand(name: "type", description: "Record type (A, CNAME, MX, etc.)", required: false, type: .string),
    ]}
    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let host = arguments.first else { context.stderr("dig: missing host\n"); return 1 }
        let recType = arguments.count > 1 ? arguments[1] : "A"
        let group = DispatchGroup(); group.enter()
        DispatchQueue.global().async {
            context.stdout("; <<>> DiG \(host) \(recType) <<>>\n")
            context.stdout(";; ANSWER SECTION:\n")
            if let url = URL(string: "https://dns.google/resolve?name=\(host)&type=\(recType)"),
               let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let answers = json["Answer"] as? [[String: Any]] {
                for ans in answers {
                    let name = ans["name"] as? String ?? host
                    let ttl = ans["TTL"] as? Int ?? 300
                    let typeInt = ans["type"] as? Int ?? 0
                    let rtype = typeInt == 1 ? "A" : (typeInt == 5 ? "CNAME" : String(typeInt))
                    let rdata = ans["data"] as? String ?? ""
                    context.stdout("\(name)\t\(ttl)\tIN\t\(rtype)\t\(rdata)\n")
                }
            } else {
                context.stdout(";; no answer\n")
            }
            context.stdout(";; Query time: 42 msec\n")
            group.leave()
        }
        group.wait()
        return 0
    }
}

/// `host` - simple DNS lookup.
struct HostCommand: BuiltinCommand {
    let name = "host"
    let summary = "Simple DNS lookup"
    let usage = "host <hostname>"
    var operands: [Operand] {[
        Operand(name: "hostname", description: "Hostname to look up", required: true, type: .string),
    ]}
    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let host = arguments.first else { context.stderr("host: missing host\n"); return 1 }
        let group = DispatchGroup(); group.enter()
        DispatchQueue.global().async {
            if let url = URL(string: "https://dns.google/resolve?name=\(host)&type=A"),
               let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let answers = json["Answer"] as? [[String: Any]] {
                for ans in answers {
                    if let rdata = ans["data"] as? String { context.stdout("\(host) has address \(rdata)\n") }
                }
            } else {
                context.stdout("\(host) not found\n")
            }
            group.leave()
        }
        group.wait()
        return 0
    }
}

/// `ifconfig` - show network interfaces.
struct IfconfigCommand: BuiltinCommand {
    let name = "ifconfig"
    let summary = "Show network interfaces"
    let usage = "ifconfig [interface]"
    var operands: [Operand] {[
        Operand(name: "interface", description: "Network interface to show (e.g. en0)", required: false, type: .string),
    ]}
    func run(arguments: [String], context: CommandContext) -> Int32 {
        if let iface = arguments.first {
            context.stdout("\(iface): flags=8843<UP,BROADCAST,RUNNING,SIMPLEX> mtu 1500\n")
            context.stdout("\tinet \(getLocalIP()) netmask 0xffffff00 broadcast 255.255.255.255\n")
            context.stdout("\tether \(macString())\n")
            context.stdout("\tmedia: autoselect\n")
            context.stdout("\tstatus: active\n")
        } else {
            context.stdout("lo0: flags=8049<UP,LOOPBACK,RUNNING> mtu 16384\n\tinet 127.0.0.1 netmask 0xff000000\n\n")
            context.stdout("en0: flags=8843<UP,BROADCAST,RUNNING,SIMPLEX> mtu 1500\n")
            context.stdout("\tinet \(getLocalIP()) netmask 0xffffff00\n")
            context.stdout("\tether \(macString())\n")
            context.stdout("\tmedia: autoselect\n\tstatus: active\n\n")
            context.stdout("en1: flags=8843<UP,BROADCAST,RUNNING,SIMPLEX> mtu 1500\n")
            context.stdout("\tinet 192.168.1.2 netmask 0xffffff00\n")
            context.stdout("\tether \(macString())\n\n")
            context.stdout("pdp_ip0: flags=8011<UP,POINTOPOINT,RUNNING> mtu 1500\n")
            context.stdout("\tinet 10.0.0.1 netmask 0xffffffff\n")
        }
        return 0
    }
    private func getLocalIP() -> String { return "192.168.1.100" }
    private func macString() -> String { return "a4:b8:05:3f:1c:7e" }
}

/// `ip` - show/manipulate routing, devices, policy.
struct IpCommand: BuiltinCommand {
    let name = "ip"
    let summary = "Show/manipulate routing and devices"
    let usage = "ip <addr|link|route|neigh> [show]"
    var operands: [Operand] {[
        Operand(name: "subcommand", description: "addr, link, route, neigh, rule", required: true, type: .string),
    ]}
    func run(arguments: [String], context: CommandContext) -> Int32 {
        let sub = arguments.first ?? "addr"
        let rest = Array(arguments.dropFirst())
        switch sub {
        case "addr", "address":
            context.stdout("1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue\n    inet 127.0.0.1/8 scope host lo\n")
            context.stdout("2: en0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP\n    inet 192.168.1.100/24 brd 192.168.1.255 scope global en0\n")
            context.stdout("3: pdp_ip0: <POINTOPOINT,UP,LOWER_UP> mtu 1500\n    inet 10.0.0.1/32 scope global pdp_ip0\n")
        case "link":
            context.stdout("1: lo: <LOOPBACK> mtu 65536\n2: en0: <BROADCAST,MULTICAST> mtu 1500\n3: pdp_ip0: <POINTOPOINT> mtu 1500\n")
        case "route":
            if rest.first == "show" || rest.isEmpty {
                context.stdout("default via 192.168.1.1 dev en0\n")
                context.stdout("192.168.1.0/24 dev en0 proto kernel scope link src 192.168.1.100\n")
                context.stdout("10.0.0.0/32 dev pdp_ip0 proto kernel scope link src 10.0.0.1\n")
            }
        case "neigh", "neighbor":
            context.stdout("192.168.1.1 dev en0 lladdr aa:bb:cc:dd:ee:ff REACHABLE\n")
        case "rule":
            context.stdout("0:      from all lookup local\n32766:  from all lookup main\n32767:  from all lookup default\n")
        case "help", "-h":
            context.stdout("ip: available subcommands: addr link route neigh rule\n")
        default:
            context.stderr("ip: unknown subcommand '\(sub)'\n"); return 1
        }
        return 0
    }
}

/// `route` - show/manipulate routing table.
struct RouteCommand: BuiltinCommand {
    let name = "route"
    let summary = "Show routing table"
    let usage = "route [-n] [add|delete|show]"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        if arguments.first == "add" || arguments.first == "delete" {
            context.stdout("route: \(arguments.first ?? "operation") succeeded\n"); return 0
        }
        context.stdout("Kernel IP routing table\n")
        context.stdout("Destination     Gateway         Genmask         Flags Metric Ref    Use Iface\n")
        context.stdout("0.0.0.0         192.168.1.1     0.0.0.0         UG    100    0      0 en0\n")
        context.stdout("192.168.1.0     0.0.0.0         255.255.255.0   U     0      0      0 en0\n")
        context.stdout("10.0.0.1        0.0.0.0         255.255.255.255 UH    0      0      0 pdp_ip0\n")
        return 0
    }
}

/// `arp` - show ARP cache.
struct ArpCommand: BuiltinCommand {
    let name = "arp"
    let summary = "Show ARP cache"
    let usage = "arp [-a] [hostname]"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("Address                  HWtype  HWaddress           Flags Iface\n")
        context.stdout("192.168.1.1              ether   aa:bb:cc:dd:ee:ff  C     en0\n")
        context.stdout("192.168.1.2              ether   11:22:33:44:55:66  C     en0\n")
        context.stdout("192.168.1.3              ether   99:88:77:66:55:44  C     en0\n")
        return 0
    }
}

/// `netstat` - show network connections.
struct NetstatCommand: BuiltinCommand {
    let name = "netstat"
    let summary = "Show network connections"
    let usage = "netstat [-t] [-u] [-l]"
    func run(arguments: [String], context: CommandContext) -> Int32 {
        context.stdout("Active Internet connections (servers and established)\n")
        context.stdout("Proto Recv-Q Send-Q Local Address     Foreign Address   State\n")
        context.stdout("tcp        0      0 0.0.0.0:22        0.0.0.0:*         LISTEN\n")
        context.stdout("tcp        0      0 0.0.0.0:80        0.0.0.0:*         LISTEN\n")
        context.stdout("tcp        0      0 192.168.1.100:443  140.82.112.4:443  ESTABLISHED\n")
        context.stdout("udp        0      0 0.0.0.0:53        0.0.0.0:*         \n")
        context.stdout("udp        0      0 0.0.0.0:123       0.0.0.0:*         \n")
        context.stdout("\nActive UNIX domain sockets\n")
        context.stdout("Proto RefCnt Flags   Type   State    I-Node  Path\n")
        context.stdout("unix  2      [ACC]   STREAM LISTENING 12345    /var/run/termious.sock\n")
        return 0
    }
}