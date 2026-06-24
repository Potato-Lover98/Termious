import Foundation

/// A single command stage with its arguments and I/O redirections.
public struct CommandNode {
    public var executable: String
    public var arguments: [String]
    public var stdinFile: String?     // < file
    public var stdoutFile: String?    // > file (truncate)
    public var appendFile: String?    // >> file
}

/// A parsed pipeline: one or more commands connected by `|`.
public struct Pipeline {
    public var commands: [CommandNode]
}

public struct Parser {
    public static func parse(_ line: String) -> [Pipeline] {
        // Split on ";" for now (no quoting-aware split needed because
        // Tokenizer keeps semicolons inside quotes intact as part of words).
        let statements = splitStatements(line)
        return statements.map { statement in
            let tokens = Tokenizer.tokenize(statement)
            return buildPipeline(from: tokens)
        }
    }

    private static func splitStatements(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inSingle = false
        var inDouble = false
        var escape = false

        for c in line {
            if escape {
                current.append(c)
                escape = false
                continue
            }
            if c == "\\" {
                current.append(c)
                escape = true
                continue
            }
            if c == "'" && !inDouble {
                inSingle.toggle()
                current.append(c)
                continue
            }
            if c == "\"" && !inSingle {
                inDouble.toggle()
                current.append(c)
                continue
            }
            if c == ";" && !inSingle && !inDouble {
                result.append(current)
                current.removeAll()
                continue
            }
            current.append(c)
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            result.append(current)
        }
        return result
    }

    private static func buildPipeline(from tokens: [Tokenizer.Token]) -> Pipeline {
        var nodes: [CommandNode] = []
        var current = CommandNode(executable: "", arguments: [], stdinFile: nil,
                                  stdoutFile: nil, appendFile: nil)
        var pendingRedir: Tokenizer.Token?

        func flushNode() {
            if !current.executable.isEmpty {
                nodes.append(current)
                current = CommandNode(executable: "", arguments: [], stdinFile: nil,
                                      stdoutFile: nil, appendFile: nil)
            }
        }

        for token in tokens {
            switch token {
            case .word(let w):
                if let redir = pendingRedir {
                    switch redir {
                    case .redirectIn:
                        current.stdinFile = w
                    case .redirectOut:
                        current.stdoutFile = w
                    case .redirectAppend:
                        current.appendFile = w
                    default:
                        break
                    }
                    pendingRedir = nil
                } else if current.executable.isEmpty {
                    current.executable = w
                } else {
                    current.arguments.append(w)
                }
            case .pipe:
                flushNode()
            case .redirectOut, .redirectAppend, .redirectIn:
                pendingRedir = token
            }
        }

        flushNode()
        return Pipeline(commands: nodes)
    }
}