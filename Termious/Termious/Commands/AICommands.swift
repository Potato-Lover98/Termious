import Foundation
import JavaScriptCore

/// `claude` - Claude Code CLI client. Talks directly to the Anthropic Messages API.
/// Set your API key first: export ANTHROPIC_API_KEY=sk-ant-...
/// Then: claude "write a function to sort an array"
struct ClaudeCommand: BuiltinCommand {
    let name = "claude"
    let summary = "Claude AI assistant (requires ANTHROPIC_API_KEY)"
    let usage = "claude \"your prompt\"  |  claude chat  |  claude --key <key>"
    var operands: [Operand] {[
        Operand(name: "prompt", description: "Prompt to send to Claude (or 'chat' for interactive)", required: true, type: .string),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        var args = arguments
        var inlineKey: String? = nil
        if let idx = args.firstIndex(of: "--key"), idx + 1 < args.count {
            inlineKey = args[idx + 1]
            context.stdout("\u{001B}]EXPORT\u{0007}ANTHROPIC_API_KEY=\(args[idx + 1])\u{0007}")
            args.removeSubrange(idx...idx + 1)
        }
        let apiKey = inlineKey ?? context.env["ANTHROPIC_API_KEY"] ?? ""
        if apiKey.isEmpty {
            context.stderr("claude: ANTHROPIC_API_KEY not set. Use: export ANTHROPIC_API_KEY=sk-ant-...\n")
            return 1
        }

        let prompt = args.joined(separator: " ")
        if prompt.isEmpty || prompt == "chat" {
            context.stdout("Claude Code (Termious edition)\n")
            context.stdout("Model: claude-sonnet-4-20250514\n")
            context.stdout("Type your prompt (Ctrl-D to end):\n")
            let input = context.stdin
            if !input.isEmpty {
                return callAPI(prompt: input, apiKey: apiKey, context: context)
            }
            context.stdout("(no input)\n")
            return 0
        }
        return callAPI(prompt: prompt, apiKey: apiKey, context: context)
    }

    private func callAPI(prompt: String, apiKey: String, context: CommandContext) -> Int32 {
        context.stdout("\u{001B}[36mThinking...\u{001B}[0m\n\n")
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            context.stderr("claude: invalid API URL\n"); return 1
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("claude-sonnet-4-20250514", forHTTPHeaderField: "anthropic-model")
        req.timeoutInterval = 60

        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 4096,
            "messages": [["role": "user", "content": prompt]],
            "system": "You are Claude Code running inside Termious, a sandboxed iOS terminal. Give concise, helpful answers. When showing code, use markdown code blocks."
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let group = DispatchGroup()
        var exitCode: Int32 = 0
        group.enter()
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error = error {
                context.stderr("claude: \(error.localizedDescription)\n")
                exitCode = 1; group.leave(); return
            }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                context.stderr("claude: invalid response\n"); exitCode = 1; group.leave(); return
            }
            if let error = json["error"] as? [String: Any],
               let msg = error["message"] as? String {
                context.stderr("claude: \(msg)\n"); exitCode = 1; group.leave(); return
            }
            if let content = json["content"] as? [[String: Any]] {
                for block in content {
                    if let text = block["text"] as? String {
                        context.stdout(text + "\n")
                    }
                }
            }
            if let usage = json["usage"] as? [String: Any] {
                let inTokens = usage["input_tokens"] as? Int ?? 0
                let outTokens = usage["output_tokens"] as? Int ?? 0
                context.stdout("\n\u{001B}[2m--- \(inTokens) in, \(outTokens) out tokens ---\u{001B}[0m\n")
            }
            group.leave()
        }.resume()
        group.wait()
        return exitCode
    }
}

/// `hermes` - JavaScript execution engine using JavaScriptCore (built into iOS).
/// Usage: hermes "console.log('hello')"  |  hermes run script.js
struct HermesCommand: BuiltinCommand {
    let name = "hermes"
    let summary = "Run JavaScript via JavaScriptCore engine"
    let usage = "hermes \"<js code>\"  |  hermes run <file.js>"
    var operands: [Operand] {[
        Operand(name: "code", description: "JS code to execute or 'run <file>'", required: true, type: .string),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        guard let jsContext = JSContext() else {
            context.stderr("hermes: failed to create JS context\n")
            return 1
        }
        jsContext.exceptionHandler = { _, exception in
            if let exc = exception {
                context.stderr("hermes: \(exc.toString() ?? "error")\n")
            }
        }
        // Add console.log support
        let consoleLog: @convention(block) (String) -> Void = { msg in
            context.stdout(msg + "\n")
        }
        let console = JSValue(newObjectIn: jsContext)
        console?.setObject(consoleLog, forKeyedSubscript: "log" as NSString)
        console?.setObject(consoleLog, forKeyedSubscript: "info" as NSString)
        console?.setObject(consoleLog, forKeyedSubscript: "warn" as NSString)
        let consoleErr: @convention(block) (String) -> Void = { msg in
            context.stderr(msg + "\n")
        }
        console?.setObject(consoleErr, forKeyedSubscript: "error" as NSString)
        jsContext.setObject(console, forKeyedSubscript: "console" as NSString)

        // Add print()
        let printFn: @convention(block) (String) -> Void = { msg in
            context.stdout(msg + "\n")
        }
        jsContext.setObject(printFn, forKeyedSubscript: "print" as NSString)

        // Determine code to run
        var code = ""
        if arguments.first == "run" && arguments.count > 1 {
            let started = context.fs.startRootAccess()
            if let url = context.fs.resolve(arguments[1]),
               let data = try? Data(contentsOf: url),
               let s = String(data: data, encoding: .utf8) {
                code = s
            } else {
                context.stderr("hermes: cannot read \(arguments[1])\n")
                if started { context.fs.stopRootAccess() }
                return 1
            }
            if started { context.fs.stopRootAccess() }
        } else {
            code = arguments.joined(separator: " ")
        }

        if code.isEmpty {
            context.stderr("hermes: no code provided\n")
            return 1
        }

        let result = jsContext.evaluateScript(code)
        if let result = result, !result.isUndefined {
            let output = result.toString()
            if output != "undefined" {
                context.stdout("=> \(output ?? "")\n")
            }
        }
        return 0
    }
}

/// `openclaw` - OpenClaw game launcher (simulated, shows game info).
struct OpenClawCommand: BuiltinCommand {
    let name = "openclaw"
    let summary = "OpenClaw game engine (simulated)"
    let usage = "openclaw [play|info|levels]"
    var operands: [Operand] {[
        Operand(name: "action", description: "play, info, or levels", required: false, type: .string),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        let action = arguments.first ?? "info"
        switch action {
        case "info":
            context.stdout("\u{001B}[33mOpenClaw\u{001B}[0m v2.0 - Captain Claw remake\n\n")
            context.stdout("An open-source remake of the classic 1997 platformer.\n")
            context.stdout("Engine: Custom C++ / SDL2\n")
            context.stdout("Status: \u{001B}[32mAvailable\u{001B}[0m (requires assets from original game)\n\n")
            context.stdout("This is a simulated launcher. The real OpenClaw\n")
            context.stdout("requires a desktop with SDL2 and OpenGL.\n")
        case "play":
            context.stdout("\u{001B}[33mOpenClaw\u{001B}[0m - Starting game...\n\n")
            context.stdout("Sorry, OpenClaw requires SDL2/OpenGL which isn't\n")
            context.stdout("available on iOS. Use 'hermes' to run JS games instead!\n")
        case "levels":
            context.stdout("OpenClaw Levels:\n")
            context.stdout("  1. La Roca  (tutorial)\n")
            context.stdout("  2. El Puerto\n")
            context.stdout("  3. La Verdia\n")
            context.stdout("  4. Dark Woods\n")
            context.stdout("  5. The Crystal Mines\n")
            context.stdout("  6. The Undersea\n")
            context.stdout("  7. The Aqueduct\n")
            context.stdout("  8. The Dragon\n")
            context.stdout("  9. The Temple\n")
            context.stdout(" 10. The Final Battle\n")
        case "help", "-h":
            context.stdout("openclaw: info, play, levels\n")
        default:
            context.stderr("openclaw: unknown '\(action)'\n")
            return 1
        }
        return 0
    }
}

/// `ai` - generic AI assistant (routes to Claude or Hermes).
struct AiCommand: BuiltinCommand {
    let name = "ai"
    let summary = "AI assistant (Claude or Hermes JS)"
    let usage = "ai \"prompt\"  |  ai js \"code\"  |  ai models"
    var operands: [Operand] {[
        Operand(name: "prompt", description: "Prompt for AI or 'js <code>' or 'models'", required: true, type: .string),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        if arguments.first == "models" {
            context.stdout("Available AI models:\n")
            context.stdout("  claude-sonnet-4-20250514   (via 'claude' command)\n")
            context.stdout("  hermes (JavaScriptCore)    (via 'hermes' command)\n")
            context.stdout("  local-gpu (Metal)          (via 'gpu' command)\n")
            return 0
        }
        if arguments.first == "js" {
            let code = arguments.dropFirst().joined(separator: " ")
            context.stdout("\u{001B}]XARGS\u{0007}hermes \(code)\u{0007}")
            return 0
        }
        // Default: route to Claude
        let prompt = arguments.joined(separator: " ")
        context.stdout("\u{001B}]XARGS\u{0007}claude \(prompt)\u{0007}")
        return 0
    }
}