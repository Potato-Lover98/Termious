import Foundation

/// `bg` - change the terminal background style.
///
/// Usage:
///   bg                  List all available styles
///   bg <name>           Apply a background style
///   bg off              Remove background style (transparent)
///   bg random           Apply a random style
struct BgCommand: BuiltinCommand {
    let name = "bg"
    let summary = "Change terminal background (15 styles: 5 gradient, 5 solid, 5 animated)"
    let usage = "bg [name|off|random]"
    var operands: [Operand] {[
        Operand(name: "name", description: "Background style name, 'off', or 'random'", required: false, type: .string),
    ]}

    func run(arguments: [String], context: CommandContext) -> Int32 {
        if arguments.isEmpty || arguments.first == "list" {
            return listStyles(context: context)
        }
        guard let arg = arguments.first else { return 1 }

        if arg == "off" {
            context.stdout("\u{001B}]BG_SET\u{0007}off\u{0007}")
            return 0
        }
        if arg == "random" {
            let styles = BackgroundManager.shared.styles
            let random = styles.randomElement()!
            context.stdout("\u{001B}]BG_SET\u{0007}\(random.name)\u{0007}")
            return 0
        }
        if BackgroundManager.shared.styles.contains(where: { $0.name == arg }) {
            context.stdout("\u{001B}]BG_SET\u{0007}\(arg)\u{0007}")
            return 0
        }
        context.stderr("bg: unknown style '\(arg)'. Use 'bg' to list styles.\n")
        return 1
    }

    private func listStyles(context: CommandContext) -> Int32 {
        context.stdout("\u{001B}[36mGradients:\u{001B}[0m\n")
        for s in BackgroundManager.shared.styles where s.kind == .gradient {
            context.stdout("  \u{001B}[32m\(padded(s.name))\u{001B}[0m \(s.description)\n")
        }
        context.stdout("\n\u{001B}[36mSolid:\u{001B}[0m\n")
        for s in BackgroundManager.shared.styles where s.kind == .solid {
            context.stdout("  \u{001B}[32m\(padded(s.name))\u{001B}[0m \(s.description)\n")
        }
        context.stdout("\n\u{001B}[36mAnimated:\u{001B}[0m\n")
        for s in BackgroundManager.shared.styles where s.kind == .animated {
            context.stdout("  \u{001B}[32m\(padded(s.name))\u{001B}[0m \(s.description)\n")
        }
        context.stdout("\nUse: bg <name>  |  bg off  |  bg random\n")
        return 0
    }

    private func padded(_ s: String) -> String {
        return s.padding(toLength: 14, withPad: " ", startingAt: 0)
    }
}