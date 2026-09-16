import Foundation

/// A TOML value. Covers the subset hop needs: strings, integers, floats,
/// booleans, arrays, tables and arrays of tables.
public enum TOMLValue: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case float(Double)
    case bool(Bool)
    case array([TOMLValue])
    case table([String: TOMLValue])

    public var string: String? { if case .string(let v) = self { v } else { nil } }
    public var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
    public var table: [String: TOMLValue]? { if case .table(let v) = self { v } else { nil } }
    public var array: [TOMLValue]? { if case .array(let v) = self { v } else { nil } }
    public var int: Int? {
        switch self {
        case .integer(let v): v
        case .float(let v) where v == v.rounded(): Int(v)
        default: nil
        }
    }
    public var double: Double? {
        switch self {
        case .integer(let v): Double(v)
        case .float(let v): v
        default: nil
        }
    }
}

public struct TOMLError: Error, Equatable, CustomStringConvertible {
    public let line: Int
    public let message: String
    public var description: String { "line \(line): \(message)" }
}

/// Minimal TOML parser. Unsupported: inline tables, dotted keys, dates,
/// multi-line strings.
public enum TOML {
    public static func parse(_ text: String) throws -> [String: TOMLValue] {
        var root: [String: TOMLValue] = [:]
        // Path of the table currently receiving keys; `isArray` marks `[[...]]`.
        var current: (path: [String], isArray: Bool) = ([], false)

        var lines = text.components(separatedBy: .newlines)[...]
        var lineNo = 0
        while let raw = lines.popFirst() {
            lineNo += 1
            let startLine = lineNo
            var line = stripComment(raw).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("[[") {
                guard line.hasSuffix("]]") else { throw TOMLError(line: lineNo, message: "unterminated [[table]] header") }
                let path = try parseKeyPath(String(line.dropFirst(2).dropLast(2)), line: lineNo)
                try appendArrayTable(&root, path: path, line: lineNo)
                current = (path, true)
                continue
            }
            if line.hasPrefix("[") {
                guard line.hasSuffix("]") else { throw TOMLError(line: lineNo, message: "unterminated [table] header") }
                let path = try parseKeyPath(String(line.dropFirst().dropLast()), line: lineNo)
                try ensureTable(&root, path: path, line: lineNo)
                current = (path, false)
                continue
            }

            guard let eq = line.firstIndex(of: "=") else {
                throw TOMLError(line: lineNo, message: "expected key = value")
            }
            let key = try parseKey(String(line[..<eq]).trimmingCharacters(in: .whitespaces), line: startLine)
            var valueText = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)

            // Arrays may span several lines.
            while valueText.hasPrefix("["), !bracketsBalanced(valueText) {
                guard let next = lines.popFirst() else {
                    throw TOMLError(line: startLine, message: "unterminated array")
                }
                lineNo += 1
                line = stripComment(next).trimmingCharacters(in: .whitespaces)
                valueText += " " + line
            }

            var scanner = ValueScanner(text: valueText, line: startLine)
            let value = try scanner.parseValue()
            try scanner.expectEnd()
            try setValue(&root, tablePath: current.path, inArray: current.isArray, key: key, value: value, line: startLine)
        }
        return root
    }

    // MARK: - Helpers

    private static func stripComment(_ s: String) -> String {
        var inBasic = false, inLiteral = false, escaped = false
        for i in s.indices {
            let c = s[i]
            if escaped { escaped = false; continue }
            if inBasic {
                if c == "\\" { escaped = true } else if c == "\"" { inBasic = false }
            } else if inLiteral {
                if c == "'" { inLiteral = false }
            } else if c == "\"" {
                inBasic = true
            } else if c == "'" {
                inLiteral = true
            } else if c == "#" {
                return String(s[..<i])
            }
        }
        return s
    }

    private static func bracketsBalanced(_ s: String) -> Bool {
        var depth = 0, inBasic = false, inLiteral = false, escaped = false
        for c in s {
            if escaped { escaped = false; continue }
            if inBasic { if c == "\\" { escaped = true } else if c == "\"" { inBasic = false }; continue }
            if inLiteral { if c == "'" { inLiteral = false }; continue }
            switch c {
            case "\"": inBasic = true
            case "'": inLiteral = true
            case "[": depth += 1
            case "]": depth -= 1
            default: break
            }
        }
        return depth <= 0
    }

    private static func parseKeyPath(_ s: String, line: Int) throws -> [String] {
        try s.split(separator: ".", omittingEmptySubsequences: false)
            .map { try parseKey($0.trimmingCharacters(in: .whitespaces), line: line) }
    }

    private static func parseKey(_ s: String, line: Int) throws -> String {
        if s.count >= 2, (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("'") && s.hasSuffix("'")) {
            var scanner = ValueScanner(text: s, line: line)
            if case .string(let k) = try scanner.parseValue() { return k }
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard !s.isEmpty, s.unicodeScalars.allSatisfy(allowed.contains) else {
            throw TOMLError(line: line, message: "invalid key '\(s)'")
        }
        return s
    }

    private static func ensureTable(_ root: inout [String: TOMLValue], path: [String], line: Int) throws {
        try modify(&root, path: path, line: line) { _ in }
    }

    private static func appendArrayTable(_ root: inout [String: TOMLValue], path: [String], line: Int) throws {
        guard let last = path.last else { throw TOMLError(line: line, message: "empty table name") }
        try modify(&root, path: Array(path.dropLast()), line: line) { table in
            switch table[last] {
            case nil: table[last] = .array([.table([:])])
            case .array(var items)?:
                items.append(.table([:]))
                table[last] = .array(items)
            default: throw TOMLError(line: line, message: "'\(last)' is not an array of tables")
            }
        }
    }

    private static func setValue(
        _ root: inout [String: TOMLValue], tablePath: [String], inArray: Bool,
        key: String, value: TOMLValue, line: Int
    ) throws {
        let assign: (inout [String: TOMLValue]) throws -> Void = { table in
            guard table[key] == nil else { throw TOMLError(line: line, message: "duplicate key '\(key)'") }
            table[key] = value
        }
        if inArray, let last = tablePath.last {
            try modify(&root, path: Array(tablePath.dropLast()), line: line) { parent in
                guard case .array(var items)? = parent[last], case .table(var t)? = items.last else {
                    throw TOMLError(line: line, message: "internal: missing array table")
                }
                try assign(&t)
                items[items.count - 1] = .table(t)
                parent[last] = .array(items)
            }
        } else {
            try modify(&root, path: tablePath, line: line, assign)
        }
    }

    /// Walks/creates tables along `path` (descending into the last element of
    /// arrays of tables) and applies `body` to the final table.
    private static func modify(
        _ table: inout [String: TOMLValue], path: [String], line: Int,
        _ body: (inout [String: TOMLValue]) throws -> Void
    ) throws {
        guard let head = path.first else { return try body(&table) }
        let rest = Array(path.dropFirst())
        switch table[head] {
        case nil:
            var sub: [String: TOMLValue] = [:]
            try modify(&sub, path: rest, line: line, body)
            table[head] = .table(sub)
        case .table(var sub)?:
            try modify(&sub, path: rest, line: line, body)
            table[head] = .table(sub)
        case .array(var items)?:
            guard case .table(var sub)? = items.last else {
                throw TOMLError(line: line, message: "'\(head)' is not a table")
            }
            try modify(&sub, path: rest, line: line, body)
            items[items.count - 1] = .table(sub)
            table[head] = .array(items)
        default:
            throw TOMLError(line: line, message: "'\(head)' is not a table")
        }
    }
}

private struct ValueScanner {
    let chars: [Character]
    var pos = 0
    let line: Int

    init(text: String, line: Int) {
        chars = Array(text)
        self.line = line
    }

    func fail(_ message: String) -> TOMLError { TOMLError(line: line, message: message) }

    mutating func skipWhitespace() {
        while pos < chars.count, chars[pos].isWhitespace { pos += 1 }
    }

    mutating func expectEnd() throws {
        skipWhitespace()
        if pos < chars.count { throw fail("unexpected trailing characters") }
    }

    mutating func parseValue() throws -> TOMLValue {
        skipWhitespace()
        guard pos < chars.count else { throw fail("missing value") }
        switch chars[pos] {
        case "\"": return .string(try parseBasicString())
        case "'": return .string(try parseLiteralString())
        case "[": return try parseArray()
        default: return try parseBareword()
        }
    }

    mutating func parseBasicString() throws -> String {
        pos += 1
        var out = ""
        while pos < chars.count {
            let c = chars[pos]
            pos += 1
            switch c {
            case "\"": return out
            case "\\":
                guard pos < chars.count else { throw fail("unterminated string") }
                let e = chars[pos]
                pos += 1
                switch e {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                case "u", "U":
                    let len = e == "u" ? 4 : 8
                    guard pos + len <= chars.count,
                          let code = UInt32(String(chars[pos..<pos + len]), radix: 16),
                          let scalar = Unicode.Scalar(code)
                    else { throw fail("invalid unicode escape") }
                    out.unicodeScalars.append(scalar)
                    pos += len
                default: throw fail("invalid escape '\\\(e)'")
                }
            default: out.append(c)
            }
        }
        throw fail("unterminated string")
    }

    mutating func parseLiteralString() throws -> String {
        pos += 1
        guard let end = chars[pos...].firstIndex(of: "'") else { throw fail("unterminated string") }
        defer { pos = end + 1 }
        return String(chars[pos..<end])
    }

    mutating func parseArray() throws -> TOMLValue {
        pos += 1
        var items: [TOMLValue] = []
        while true {
            skipWhitespace()
            guard pos < chars.count else { throw fail("unterminated array") }
            if chars[pos] == "]" { pos += 1; return .array(items) }
            items.append(try parseValue())
            skipWhitespace()
            guard pos < chars.count else { throw fail("unterminated array") }
            if chars[pos] == "," { pos += 1 } else if chars[pos] != "]" { throw fail("expected ',' or ']' in array") }
        }
    }

    mutating func parseBareword() throws -> TOMLValue {
        let start = pos
        while pos < chars.count, !chars[pos].isWhitespace, chars[pos] != ",", chars[pos] != "]" { pos += 1 }
        let word = String(chars[start..<pos])
        switch word {
        case "true": return .bool(true)
        case "false": return .bool(false)
        default:
            let digits = word.replacingOccurrences(of: "_", with: "")
            if let i = Int(digits) { return .integer(i) }
            if let d = Double(digits) { return .float(d) }
            throw fail("invalid value '\(word)'")
        }
    }
}
