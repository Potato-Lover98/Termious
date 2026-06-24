import Foundation

/// Splits a raw command line into tokens, honoring single and double quotes
/// and backslash escapes. Supports pipe (`|`) and redirect (`>`, `>>`, `<`)
/// operators as separate tokens.
public struct Tokenizer {
    public enum Token: Equatable {
        case word(String)
        case pipe
        case redirectOut          // >
        case redirectAppend       // >>
        case redirectIn           // <
    }

    public static func tokenize(_ line: String) -> [Token] {
        var tokens: [Token] = []
        var chars = Array(line)
        var i = 0
        var current = ""

        func flushWord() {
            if !current.isEmpty {
                tokens.append(.word(current))
                current.removeAll()
            }
        }

        while i < chars.count {
            let c = chars[i]

            if c.isWhitespace {
                flushWord()
                i += 1
                continue
            }

            // Operators
            if c == "|" {
                flushWord()
                tokens.append(.pipe)
                i += 1
                continue
            }
            if c == ">" {
                flushWord()
                if i + 1 < chars.count, chars[i + 1] == ">" {
                    tokens.append(.redirectAppend)
                    i += 2
                } else {
                    tokens.append(.redirectOut)
                    i += 1
                }
                continue
            }
            if c == "<" {
                flushWord()
                tokens.append(.redirectIn)
                i += 1
                continue
            }

            // Quoted strings
            if c == "\"" {
                i += 1
                while i < chars.count, chars[i] != "\"" {
                    if chars[i] == "\\", i + 1 < chars.count {
                        current.append(unescape(chars[i + 1]))
                        i += 2
                    } else {
                        current.append(chars[i])
                        i += 1
                    }
                }
                i += 1 // skip closing quote
                continue
            }
            if c == "'" {
                i += 1
                while i < chars.count, chars[i] != "'" {
                    current.append(chars[i])
                    i += 1
                }
                i += 1
                continue
            }

            // Backslash escape
            if c == "\\", i + 1 < chars.count {
                current.append(unescape(chars[i + 1]))
                i += 2
                continue
            }

            current.append(c)
            i += 1
        }

        flushWord()
        return tokens
    }

    private static func unescape(_ c: Character) -> String {
        switch c {
        case "n": return "\n"
        case "t": return "\t"
        case "r": return "\r"
        case "\\": return "\\"
        case "\"": return "\""
        case "'": return "'"
        case " ": return " "
        default: return String(c)
        }
    }
}