import Foundation

/// Arithmetic with units for the search field: "2^10", "90 min to h",
/// "1.5 GB in MiB", "100 km / 2 h", "200 + 15%", "15% of 80", "255 to hex".
public enum Calculator {
    public struct Result: Equatable, Sendable {
        /// What the panel shows: "1.5 h".
        public var text: String
        /// What Return copies: the number alone, "1.5".
        public var value: String
        /// Where the numbers came from, e.g. the date of exchange rates.
        public var note: String?

        public init(text: String, value: String, note: String? = nil) {
            self.text = text
            self.value = value
            self.note = note
        }
    }

    /// Results for `query`, best first; empty when it isn't a calculation or
    /// there is nothing to add to what was typed (a bare "42" or "5 min").
    /// Amounts in currencies are converted with `currencies`; without rates
    /// they aren't recognized at all.
    public static func evaluate(_ query: String, currencies: Currencies = Currencies()) -> [Result] {
        guard query.contains(where: \.isNumber), var tokens = try? tokenize(query) else { return [] }
        if tokens.last == .op("=") { tokens.removeLast() }
        guard !tokens.isEmpty else { return [] }

        var results: [Result] = []
        if let (quantity, target) = splitConversion(tokens, currencies) {
            results = (try? convert(quantity, to: target)).map { [$0] } ?? []
        } else if let parser = try? Parser.parseAll(tokens, currencies), let q = try? parser.result.resolved.checked() {
            if parser.ops > 0 { results.append(q.result()) }
            for extra in humanized(q, currencies) where !results.contains(extra) {
                results.append(extra)
            }
        }
        if let date = currencies.date, tokens.contains(where: { currencies.unit($0) != nil }) {
            for i in results.indices { results[i].note = "rates of \(date)" }
        }
        return results
    }

    // MARK: - Conversion ("… to …")

    private enum Target {
        case units([UnitPower])
        case radix(Int, prefix: String)
    }

    private static let conversionWords: Set<String> = ["to", "in", "as", "into"]

    /// Splits "expr to target" on the rightmost keyword that leaves both sides
    /// valid, so "12 in to cm" and "5 ft in in" both work.
    private static func splitConversion(_ tokens: [Token], _ currencies: Currencies) -> (Quantity, Target)? {
        var depth = 0
        var splits: [Int] = []
        for (i, token) in tokens.enumerated() {
            switch token {
            case .op("("): depth += 1
            case .op(")"): depth -= 1
            case .op("->") where depth == 0: splits.append(i)
            case .ident(let word) where depth == 0 && conversionWords.contains(word.lowercased()): splits.append(i)
            default: break
            }
        }
        for i in splits.reversed() where i > 0 && i < tokens.count - 1 {
            guard let target = parseTarget(Array(tokens[(i + 1)...]), currencies),
                  let parser = try? Parser.parseAll(Array(tokens[..<i]), currencies) else { continue }
            return (parser.result, target)
        }
        return nil
    }

    private static func parseTarget(_ tokens: [Token], _ currencies: Currencies) -> Target? {
        if tokens.count == 1, case .ident(let word) = tokens[0] {
            switch word.lowercased() {
            case "hex": return .radix(16, prefix: "0x")
            case "bin", "binary": return .radix(2, prefix: "0b")
            case "oct", "octal": return .radix(8, prefix: "0o")
            default: break
            }
        }
        var units: [UnitPower] = []
        var i = 0
        var sign = 1
        while i < tokens.count {
            guard case .ident(let name) = tokens[i], let unit = Units.lookup(name) ?? currencies.lookup(name) else { return nil }
            i += 1
            var power = 1
            if i + 1 < tokens.count, tokens[i] == .op("^"), case .number(let n, _) = tokens[i + 1], n == n.rounded(), n != 0 {
                power = Int(n)
                i += 2
            }
            let merged = Quantity.merge(units, UnitPower(unit: unit, power: power * sign))
            guard merged.scale == 1 else { return nil } // "km/m" isn't a unit to convert into
            units = merged.units
            guard i < tokens.count else { break }
            switch tokens[i] {
            case .op("*"): sign = 1
            case .op("/"): sign = -1
            default: return nil
            }
            i += 1
            guard i < tokens.count else { return nil }
        }
        return units.isEmpty ? nil : .units(units)
    }

    private static func convert(_ quantity: Quantity, to target: Target) throws -> Result {
        let q = try quantity.resolved.checked()
        switch target {
        case .radix(let radix, let prefix):
            guard q.units.isEmpty, q.value == q.value.rounded(), abs(q.value) < 9.0e15 else { throw Failure() }
            let n = Int64(q.value)
            let text = (n < 0 ? "-" : "") + prefix + String(n.magnitude, radix: radix)
            return Result(text: text, value: text)
        case .units(let units):
            guard Quantity.dims(q.units) == Quantity.dims(units) else { throw Failure() }
            let value: Double
            if let from = q.singleTemperature, let to = Quantity(value: 0, units: units).singleTemperature {
                value = (q.value * from.factor + from.offset - to.offset) / to.factor
            } else {
                value = q.value * Quantity.factor(q.units) / Quantity.factor(units)
            }
            return try Quantity(value: value, units: units).checked().result()
        }
    }

    // MARK: - Friendlier units

    private static let timeLadder = ["ms", "s", "min", "h", "d"]
    private static let decimalBytes = ["B", "KB", "MB", "GB", "TB", "PB"]
    private static let binaryBytes = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
    private static let bits = ["bit", "kbit", "Mbit", "Gbit", "Tbit"]

    /// The same amount in the units a person would pick: "5400 s" → "1.5 h",
    /// "1 h 30 min"; bytes in both decimal and binary units.
    private static func humanized(_ q: Quantity, _ currencies: Currencies) -> [Result] {
        guard q.units.count == 1, q.units[0].power == 1 else { return [] }
        let unit = q.units[0].unit
        let base = q.value * unit.factor
        if unit.dims == Units.currency {
            return currencies.targets.compactMap { code in
                guard code != unit.symbol, let target = currencies.lookup(code) else { return nil }
                return Quantity(value: base / target.factor, units: [UnitPower(unit: target, power: 1)]).result()
            }
        }
        var ladders: [[String]] = []
        if unit.dims == Units.time { ladders = [timeLadder] }
        if unit.dims == Units.data { ladders = (bits.contains(unit.symbol) ? [bits] : []) + [decimalBytes, binaryBytes] }

        var results: [Result] = []
        for ladder in ladders {
            let units = ladder.compactMap(Units.bySymbol)
            let best = units.last { abs(base) >= $0.factor } ?? units[0]
            guard best.symbol != unit.symbol else { continue }
            let value = (base / best.factor * 1000).rounded() / 1000
            results.append(Quantity(value: value, units: [UnitPower(unit: best, power: 1)]).result())
        }
        if unit.dims == Units.time, let parts = timeBreakdown(seconds: base) {
            results.append(Result(text: parts, value: parts))
        }
        return results
    }

    /// "1 d 2 h 3 min 4 s", or nil when a single unit says it all.
    private static func timeBreakdown(seconds: Double) -> String? {
        var rest = abs(seconds).rounded()
        guard rest >= 60, rest < 1e12 else { return nil }
        var parts: [String] = []
        for (symbol, size) in [("d", 86400.0), ("h", 3600), ("min", 60), ("s", 1)] {
            let n = (rest / size).rounded(.down)
            rest -= n * size
            if n > 0 { parts.append("\(Int64(n)) \(symbol)") }
        }
        guard parts.count >= 2 else { return nil }
        return (seconds < 0 ? "-" : "") + parts.joined(separator: " ")
    }

    // MARK: - Numbers

    /// Up to 10 significant digits, no float noise ("0.1 + 0.2" → "0.3").
    static func format(_ x: Double) -> String {
        if x == x.rounded(), abs(x) < 1e15 { return String(Int64(x)) }
        var s = String(format: "%.10g", x)
        if s.contains("e"), abs(x) < 1, abs(x) >= 1e-10 {
            // "0.00001", not "1e-05": same 10 significant digits, spelled out.
            let decimals = 9 - Int(log10(abs(x)).rounded(.down))
            s = String(format: "%.\(decimals)f", x)
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        } else if s.contains("e") {
            // "1.5e-07" → "1.5e-7"
            s = s.replacingOccurrences(of: "e-0", with: "e-").replacingOccurrences(of: "e+0", with: "e").replacingOccurrences(of: "e+", with: "e")
        }
        return s
    }

    /// "1048576" → "1 048 576" (narrow no-break spaces) for display.
    static func grouped(_ s: String) -> String {
        let negative = s.hasPrefix("-")
        let body = negative ? String(s.dropFirst()) : s
        guard !body.contains("e") else { return s }
        let intPart = body.prefix { $0.isNumber }
        guard intPart.count > 4 else { return s }
        var digits = Array(intPart)
        var out = ""
        while digits.count > 3 {
            out = "\u{202F}" + String(digits.suffix(3)) + out
            digits.removeLast(3)
        }
        return (negative ? "-" : "") + String(digits) + out + body.dropFirst(intPart.count)
    }
}

struct Failure: Error {}

// MARK: - Tokens

enum Token: Equatable {
    /// `plain` is false for literals like 0xff, which are worth showing in decimal.
    case number(Double, plain: Bool)
    case ident(String)
    case op(String)
}

private func tokenize(_ text: String) throws -> [Token] {
    let chars = Array(text)
    var tokens: [Token] = []
    var i = 0
    func isIdentChar(_ c: Character) -> Bool { c.isLetter || c == "°" || c == "µ" }

    while i < chars.count {
        let c = chars[i]
        if c.isWhitespace { i += 1; continue }

        if c.isASCII && c.isNumber || (c == "." && i + 1 < chars.count && chars[i + 1].isASCII && chars[i + 1].isNumber) {
            // 0x / 0b / 0o literals
            if c == "0", i + 2 < chars.count, let radix = ["x": 16, "b": 2, "o": 8][chars[i + 1].lowercased()],
               chars[i + 2].isHexDigit {
                var j = i + 2
                var digits = ""
                while j < chars.count, chars[j].isHexDigit || chars[j] == "_" {
                    if chars[j] != "_" { digits.append(chars[j]) }
                    j += 1
                }
                guard let n = Int64(digits, radix: radix) else { throw Failure() }
                tokens.append(.number(Double(n), plain: false))
                i = j
                continue
            }
            var j = i
            var literal = ""
            while j < chars.count, chars[j].isASCII && chars[j].isNumber || chars[j] == "." || chars[j] == "_" {
                if chars[j] != "_" { literal.append(chars[j]) }
                j += 1
            }
            // Exponent only when digits follow, so "2e" isn't a number.
            if j < chars.count, chars[j] == "e" || chars[j] == "E" {
                var k = j + 1
                if k < chars.count, chars[k] == "+" || chars[k] == "-" { k += 1 }
                if k < chars.count, chars[k].isASCII && chars[k].isNumber {
                    literal.append(contentsOf: chars[j..<k])
                    j = k
                    while j < chars.count, chars[j].isASCII && chars[j].isNumber { literal.append(chars[j]); j += 1 }
                }
            }
            guard let n = Double(literal) else { throw Failure() }
            tokens.append(.number(n, plain: true))
            i = j
            continue
        }

        if Currencies.symbols[c] != nil {
            tokens.append(.ident(String(c)))
            i += 1
            continue
        }

        if isIdentChar(c) {
            var j = i
            while j < chars.count, isIdentChar(chars[j]) { j += 1 }
            tokens.append(.ident(String(chars[i..<j])))
            i = j
            continue
        }

        let two = i + 1 < chars.count ? String(chars[i...i + 1]) : ""
        if two == "**" { tokens.append(.op("^")); i += 2; continue }
        if two == "->" { tokens.append(.op("->")); i += 2; continue }
        switch c {
        case "+", "-", "*", "/", "^", "%", "(", ")", "=": tokens.append(.op(String(c)))
        case "−": tokens.append(.op("-"))
        case "×", "·": tokens.append(.op("*"))
        case "÷": tokens.append(.op("/"))
        case "→": tokens.append(.op("->"))
        case "²": tokens += [.op("^"), .number(2, plain: true)]
        case "³": tokens += [.op("^"), .number(3, plain: true)]
        default: throw Failure()
        }
        i += 1
    }
    return tokens
}

// MARK: - Parser

/// Recursive descent over the tokens:
///   expr    := term (("+" | "-") term)*
///   term    := unary (("*" | "/" | "mod") unary | "of" unary | quantity)*
///   unary   := ("-" | "+") unary | power
///   power   := postfix ("^" unary)?
///   postfix := primary ("%" | unit ("^" int)? ("/" unit)*)*
///   primary := number | "(" expr ")" | function "(" expr ")" | constant | unit
private struct Parser {
    let tokens: [Token]
    let currencies: Currencies
    var pos = 0
    /// Operations performed; zero means the input was a lone literal.
    var ops = 0
    var result = Quantity(value: 0)

    static func parseAll(_ tokens: [Token], _ currencies: Currencies) throws -> Parser {
        var parser = Parser(tokens: tokens, currencies: currencies)
        parser.result = try parser.expr()
        guard parser.pos == tokens.count else { throw Failure() }
        return parser
    }

    private var peek: Token? { pos < tokens.count ? tokens[pos] : nil }
    private func lookup(_ name: String) -> Unit? { Units.lookup(name) ?? currencies.lookup(name) }
    private func peek(_ offset: Int) -> Token? { pos + offset < tokens.count ? tokens[pos + offset] : nil }

    private mutating func expr() throws -> Quantity {
        var left = try term()
        while let token = peek, token == .op("+") || token == .op("-") {
            pos += 1
            let right = try term()
            left = try left.adding(right, sign: token == .op("+") ? 1 : -1)
            ops += 1
        }
        return left
    }

    private mutating func term() throws -> Quantity {
        var left = try unary()
        while let token = peek {
            switch token {
            case .op("*"):
                pos += 1
                left = left.multiplied(by: try unary())
            case .op("/"):
                pos += 1
                let right = try unary().resolved
                guard right.value != 0 else { throw Failure() }
                left = left.multiplied(by: right.reciprocal)
            case .ident(let w) where w.lowercased() == "mod":
                pos += 1
                left = try left.remainder(try unary())
            case .ident(let w) where w.lowercased() == "of" && left.percent:
                pos += 1
                let whole = try unary().resolved
                left = Quantity(value: whole.value * left.value / 100, units: whole.units)
            case .number where !left.units.isEmpty:
                // "1 h 30 min"
                let right = try postfix()
                guard !right.units.isEmpty else { throw Failure() }
                left = try left.adding(right, sign: 1)
            default:
                return left
            }
            ops += 1
        }
        return left
    }

    private mutating func unary() throws -> Quantity {
        switch peek {
        case .op("-"):
            pos += 1
            var q = try unary()
            q.value.negate()
            return q
        case .op("+"):
            pos += 1
            return try unary()
        default:
            return try power()
        }
    }

    private mutating func power() throws -> Quantity {
        let base = try postfix()
        guard peek == .op("^") else { return base }
        pos += 1
        let exponent = try unary().resolved
        ops += 1
        return try base.raised(to: exponent)
    }

    private mutating func postfix() throws -> Quantity {
        var q = try primary()
        while let token = peek {
            if token == .op("%"), !q.percent, q.units.isEmpty {
                pos += 1
                q.percent = true
            } else if case .ident(let name) = token, let unit = lookup(name) {
                pos += 1
                q = q.multiplied(by: Quantity(value: 1, units: [UnitPower(unit: unit, power: try unitPower())]))
                // "MB/s" binds tighter than division, so "1 GB / 10 MB/s" is 100 s.
                while peek == .op("/"), case .ident(let name)? = peek(1), let unit = lookup(name) {
                    pos += 2
                    q = q.multiplied(by: Quantity(value: 1, units: [UnitPower(unit: unit, power: -(try unitPower()))]))
                }
            } else {
                break
            }
        }
        return q
    }

    /// Optional "^2" right after a unit: "5 m^2" is 5 m², not 25 m².
    private mutating func unitPower() throws -> Int {
        guard peek == .op("^"), case .number(let n, _)? = peek(1), n == n.rounded(), n != 0, abs(n) < 10 else { return 1 }
        pos += 2
        return Int(n)
    }

    private mutating func primary() throws -> Quantity {
        guard let token = peek else { throw Failure() }
        pos += 1
        switch token {
        case .number(let n, let plain):
            if !plain { ops += 1 }
            return Quantity(value: n)
        case .op("("):
            let inner = try expr()
            // Tolerate a missing ")" at the end while typing.
            if peek == .op(")") { pos += 1 } else if peek != nil { throw Failure() }
            return inner
        case .ident(let name):
            let lower = name.lowercased()
            if let function = Functions.table[lower], peek == .op("(") {
                pos += 1
                let arg = try expr()
                if peek == .op(")") { pos += 1 } else if peek != nil { throw Failure() }
                ops += 1
                return try function(arg.resolved)
            }
            if let constant = ["pi": Double.pi, "π": .pi, "e": M_E, "tau": 2 * .pi][lower] {
                ops += 1
                return Quantity(value: constant)
            }
            if let unit = lookup(name) {
                // "$100"; only symbols, or "top 10" would be Tongan paʻanga.
                if unit.dims == Units.currency, name.count == 1, case .number(let n, _)? = peek {
                    pos += 1
                    return Quantity(value: n, units: [UnitPower(unit: unit, power: 1)])
                }
                return Quantity(value: 1, units: [UnitPower(unit: unit, power: try unitPower())])
            }
            throw Failure()
        default:
            throw Failure()
        }
    }
}

// MARK: - Quantities

struct Unit: Sendable {
    var symbol: String
    /// Size in base units (m, kg, s, bit, K, rad).
    var factor: Double
    var dims: [Int]
    /// Only temperatures have one: kelvin = value * factor + offset.
    var offset: Double = 0
}

struct UnitPower: Sendable {
    var unit: Unit
    var power: Int
}

/// A number in the units it carries: 1.5 with [h] is an hour and a half.
struct Quantity {
    var value: Double
    var units: [UnitPower] = []
    /// "15%": 15 until it's used; adding it scales the other side.
    var percent = false

    static func factor(_ units: [UnitPower]) -> Double {
        units.reduce(1) { $0 * pow($1.unit.factor, Double($1.power)) }
    }

    static func dims(_ units: [UnitPower]) -> [Int] {
        units.reduce(Units.none) { acc, u in zip(acc, u.unit.dims).map { $0 + $1 * u.power } }
    }

    /// Adds a unit, folding it into one of the same kind: km·m becomes km².
    /// Returns the factor the value has to be multiplied by.
    static func merge(_ units: [UnitPower], _ new: UnitPower) -> (units: [UnitPower], scale: Double) {
        var units = units
        var scale = 1.0
        if let i = units.firstIndex(where: { $0.unit.symbol == new.unit.symbol }) {
            units[i].power += new.power
        } else if let i = units.firstIndex(where: { $0.unit.dims == new.unit.dims && $0.unit.offset == 0 && new.unit.offset == 0 }) {
            scale = pow(new.unit.factor / units[i].unit.factor, Double(new.power))
            units[i].power += new.power
        } else {
            units.append(new)
        }
        return (units.filter { $0.power != 0 }, scale)
    }

    var resolved: Quantity {
        percent ? Quantity(value: value / 100, units: units) : self
    }

    var reciprocal: Quantity {
        Quantity(value: 1 / value, units: units.map { UnitPower(unit: $0.unit, power: -$0.power) })
    }

    var singleTemperature: Unit? {
        guard units.count == 1, units[0].power == 1, units[0].unit.dims == Units.temperature else { return nil }
        return units[0].unit
    }

    func checked() throws -> Quantity {
        guard value.isFinite else { throw Failure() }
        return self
    }

    func multiplied(by other: Quantity) -> Quantity {
        let a = resolved, b = other.resolved
        var result = Quantity(value: a.value * b.value, units: a.units)
        for u in b.units {
            let merged = Quantity.merge(result.units, u)
            result.units = merged.units
            result.value *= merged.scale
        }
        return result.simplified()
    }

    /// Leftovers like "Mbps·s" become one plain unit of what they measure.
    private func simplified() -> Quantity {
        guard units.count > 1 else { return self }
        let dims = Quantity.dims(units)
        let base = value * Quantity.factor(units)
        if dims == Units.none { return Quantity(value: base) }
        guard let unit = Units.baseUnits.first(where: { $0.dims == dims }) else { return self }
        return Quantity(value: base / unit.factor, units: [UnitPower(unit: unit, power: 1)])
    }

    func adding(_ other: Quantity, sign: Double) throws -> Quantity {
        if other.percent && !percent {
            return Quantity(value: value * (1 + sign * other.value / 100), units: units)
        }
        guard percent == other.percent, Quantity.dims(units) == Quantity.dims(other.units) else { throw Failure() }
        if units.isEmpty && !other.units.isEmpty {
            return Quantity(value: value + sign * other.value, units: other.units, percent: percent)
        }
        let converted = other.value * Quantity.factor(other.units) / Quantity.factor(units)
        return Quantity(value: value + sign * converted, units: units, percent: percent)
    }

    func remainder(_ other: Quantity) throws -> Quantity {
        let a = resolved, b = other.resolved
        guard Quantity.dims(a.units) == Quantity.dims(b.units) else { throw Failure() }
        let divisor = b.value * Quantity.factor(b.units) / Quantity.factor(a.units)
        guard divisor != 0 else { throw Failure() }
        return Quantity(value: fmod(a.value, divisor), units: a.units)
    }

    func raised(to exponent: Quantity) throws -> Quantity {
        guard exponent.units.isEmpty else { throw Failure() }
        let base = resolved
        if base.units.isEmpty { return Quantity(value: pow(base.value, exponent.value)) }
        guard exponent.value == exponent.value.rounded(), abs(exponent.value) < 10 else { throw Failure() }
        let n = Int(exponent.value)
        return Quantity(value: pow(base.value, exponent.value),
                        units: n == 0 ? [] : base.units.map { UnitPower(unit: $0.unit, power: $0.power * n) })
    }

    func result() -> Calculator.Result {
        // Money to the cent; crypto keeps its fractions.
        let isMoney = units.count == 1 && units[0].power == 1 && units[0].unit.dims == Units.currency
            && !["BTC", "ETH"].contains(units[0].unit.symbol) && abs(value) >= 0.01
        let number = Calculator.format(isMoney ? (value * 100).rounded() / 100 : value)
        if percent { return Calculator.Result(text: Calculator.grouped(number) + "%", value: number) }
        guard !units.isEmpty else { return Calculator.Result(text: Calculator.grouped(number), value: number) }
        return Calculator.Result(text: Calculator.grouped(number) + " " + unitText, value: number)
    }

    /// "km/h", "m²", "B·s", "1/s"
    private var unitText: String {
        func show(_ u: UnitPower, _ power: Int) -> String {
            let sup: [Character: Character] = ["0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹"]
            return power == 1 ? u.unit.symbol : u.unit.symbol + String(String(power).compactMap { sup[$0] })
        }
        let top = units.filter { $0.power > 0 }.map { show($0, $0.power) }
        let bottom = units.filter { $0.power < 0 }.map { show($0, -$0.power) }
        let numerator = top.isEmpty ? "1" : top.joined(separator: "·")
        switch bottom.count {
        case 0: return numerator
        case 1: return numerator + "/" + bottom[0]
        default: return numerator + "/(" + bottom.joined(separator: "·") + ")"
        }
    }
}

// MARK: - Tables

private enum Functions {
    typealias Function = @Sendable (Quantity) throws -> Quantity

    static func plain(_ f: @escaping @Sendable (Double) -> Double) -> Function {
        { q in
            guard q.units.isEmpty else { throw Failure() }
            return Quantity(value: f(q.value))
        }
    }

    static func keepingUnits(_ f: @escaping @Sendable (Double) -> Double) -> Function {
        { q in Quantity(value: f(q.value), units: q.units) }
    }

    /// Takes radians or anything convertible to them: sin(90 deg).
    static func trig(_ f: @escaping @Sendable (Double) -> Double) -> Function {
        { q in
            if q.units.isEmpty { return Quantity(value: f(q.value)) }
            guard Quantity.dims(q.units) == Units.angle else { throw Failure() }
            return Quantity(value: f(q.value * Quantity.factor(q.units)))
        }
    }

    static let table: [String: Function] = [
        "sqrt": { q in
            guard q.units.allSatisfy({ $0.power % 2 == 0 }) else { throw Failure() }
            return Quantity(value: q.value.squareRoot(), units: q.units.map { UnitPower(unit: $0.unit, power: $0.power / 2) })
        },
        "cbrt": plain(cbrt),
        "abs": keepingUnits(abs),
        "round": keepingUnits { $0.rounded() },
        "floor": keepingUnits { $0.rounded(.down) },
        "ceil": keepingUnits { $0.rounded(.up) },
        "sin": trig(sin), "cos": trig(cos), "tan": trig(tan),
        "asin": plain(asin), "acos": plain(acos), "atan": plain(atan),
        "ln": plain(log), "log": plain(log10), "lg": plain(log2), "exp": plain(exp),
    ]
}

enum Units {
    // length, mass, time, data, temperature, angle, currency
    static let none = [0, 0, 0, 0, 0, 0, 0]
    static let length = [1, 0, 0, 0, 0, 0, 0]
    static let mass = [0, 1, 0, 0, 0, 0, 0]
    static let time = [0, 0, 1, 0, 0, 0, 0]
    static let data = [0, 0, 0, 1, 0, 0, 0]
    static let temperature = [0, 0, 0, 0, 1, 0, 0]
    static let angle = [0, 0, 0, 0, 0, 1, 0]
    static let currency = [0, 0, 0, 0, 0, 0, 1]
    static let volume = [3, 0, 0, 0, 0, 0, 0]
    static let speed = [1, 0, -1, 0, 0, 0, 0]
    static let dataRate = [0, 0, -1, 1, 0, 0, 0]
    static let frequency = [0, 0, -1, 0, 0, 0, 0]

    /// Names are matched case-insensitively, so "mb" and "MB" are both megabytes.
    /// Bits need to be spelled out: "Mbit", "Mbps".
    private static let all: [(names: [String], unit: Unit)] = [
        (["nm", "nanometer", "nanometers"], Unit(symbol: "nm", factor: 1e-9, dims: length)),
        (["µm", "um", "micron", "microns"], Unit(symbol: "µm", factor: 1e-6, dims: length)),
        (["mm", "millimeter", "millimeters"], Unit(symbol: "mm", factor: 1e-3, dims: length)),
        (["cm", "centimeter", "centimeters"], Unit(symbol: "cm", factor: 1e-2, dims: length)),
        (["m", "meter", "meters", "metre", "metres"], Unit(symbol: "m", factor: 1, dims: length)),
        (["km", "kilometer", "kilometers"], Unit(symbol: "km", factor: 1e3, dims: length)),
        (["in", "inch", "inches"], Unit(symbol: "in", factor: 0.0254, dims: length)),
        (["ft", "foot", "feet"], Unit(symbol: "ft", factor: 0.3048, dims: length)),
        (["yd", "yard", "yards"], Unit(symbol: "yd", factor: 0.9144, dims: length)),
        (["mi", "mile", "miles"], Unit(symbol: "mi", factor: 1609.344, dims: length)),

        (["mg", "milligram", "milligrams"], Unit(symbol: "mg", factor: 1e-6, dims: mass)),
        (["g", "gram", "grams"], Unit(symbol: "g", factor: 1e-3, dims: mass)),
        (["kg", "kilogram", "kilograms"], Unit(symbol: "kg", factor: 1, dims: mass)),
        (["t", "ton", "tons", "tonne", "tonnes"], Unit(symbol: "t", factor: 1e3, dims: mass)),
        (["oz", "ounce", "ounces"], Unit(symbol: "oz", factor: 0.028349523125, dims: mass)),
        (["lb", "lbs", "pound", "pounds"], Unit(symbol: "lb", factor: 0.45359237, dims: mass)),

        (["ns", "nanosecond", "nanoseconds"], Unit(symbol: "ns", factor: 1e-9, dims: time)),
        (["µs", "us", "microsecond", "microseconds"], Unit(symbol: "µs", factor: 1e-6, dims: time)),
        (["ms", "millisecond", "milliseconds"], Unit(symbol: "ms", factor: 1e-3, dims: time)),
        (["s", "sec", "secs", "second", "seconds"], Unit(symbol: "s", factor: 1, dims: time)),
        (["min", "mins", "minute", "minutes"], Unit(symbol: "min", factor: 60, dims: time)),
        (["h", "hr", "hrs", "hour", "hours"], Unit(symbol: "h", factor: 3600, dims: time)),
        (["d", "day", "days"], Unit(symbol: "d", factor: 86400, dims: time)),
        (["w", "wk", "week", "weeks"], Unit(symbol: "wk", factor: 604_800, dims: time)),
        (["mo", "month", "months"], Unit(symbol: "mo", factor: 2_629_746, dims: time)),
        (["y", "yr", "yrs", "year", "years"], Unit(symbol: "yr", factor: 31_556_952, dims: time)),

        (["bit", "bits"], Unit(symbol: "bit", factor: 1, dims: data)),
        (["kbit", "kbits", "kilobit", "kilobits"], Unit(symbol: "kbit", factor: 1e3, dims: data)),
        (["mbit", "mbits", "megabit", "megabits"], Unit(symbol: "Mbit", factor: 1e6, dims: data)),
        (["gbit", "gbits", "gigabit", "gigabits"], Unit(symbol: "Gbit", factor: 1e9, dims: data)),
        (["tbit", "tbits", "terabit", "terabits"], Unit(symbol: "Tbit", factor: 1e12, dims: data)),
        (["b", "byte", "bytes"], Unit(symbol: "B", factor: 8, dims: data)),
        (["kb", "kilobyte", "kilobytes"], Unit(symbol: "KB", factor: 8e3, dims: data)),
        (["mb", "megabyte", "megabytes"], Unit(symbol: "MB", factor: 8e6, dims: data)),
        (["gb", "gigabyte", "gigabytes"], Unit(symbol: "GB", factor: 8e9, dims: data)),
        (["tb", "terabyte", "terabytes"], Unit(symbol: "TB", factor: 8e12, dims: data)),
        (["pb", "petabyte", "petabytes"], Unit(symbol: "PB", factor: 8e15, dims: data)),
        (["kib", "kibibyte", "kibibytes"], Unit(symbol: "KiB", factor: 8 * 1024, dims: data)),
        (["mib", "mebibyte", "mebibytes"], Unit(symbol: "MiB", factor: 8 * pow(1024, 2), dims: data)),
        (["gib", "gibibyte", "gibibytes"], Unit(symbol: "GiB", factor: 8 * pow(1024, 3), dims: data)),
        (["tib", "tebibyte", "tebibytes"], Unit(symbol: "TiB", factor: 8 * pow(1024, 4), dims: data)),
        (["pib", "pebibyte", "pebibytes"], Unit(symbol: "PiB", factor: 8 * pow(1024, 5), dims: data)),
        (["bps"], Unit(symbol: "bps", factor: 1, dims: dataRate)),
        (["kbps"], Unit(symbol: "kbps", factor: 1e3, dims: dataRate)),
        (["mbps"], Unit(symbol: "Mbps", factor: 1e6, dims: dataRate)),
        (["gbps"], Unit(symbol: "Gbps", factor: 1e9, dims: dataRate)),

        (["kelvin"], Unit(symbol: "K", factor: 1, dims: temperature)),
        (["c", "°c", "celsius"], Unit(symbol: "°C", factor: 1, dims: temperature, offset: 273.15)),
        (["f", "°f", "fahrenheit"], Unit(symbol: "°F", factor: 5.0 / 9, dims: temperature, offset: 273.15 - 32 * 5.0 / 9)),

        (["rad", "radian", "radians"], Unit(symbol: "rad", factor: 1, dims: angle)),
        (["deg", "degree", "degrees", "°"], Unit(symbol: "°", factor: .pi / 180, dims: angle)),

        (["ml", "milliliter", "milliliters"], Unit(symbol: "ml", factor: 1e-6, dims: volume)),
        (["l", "liter", "liters", "litre", "litres"], Unit(symbol: "l", factor: 1e-3, dims: volume)),
        (["gal", "gallon", "gallons"], Unit(symbol: "gal", factor: 3.785411784e-3, dims: volume)),

        (["kmh", "kph"], Unit(symbol: "km/h", factor: 1 / 3.6, dims: speed)),
        (["mph"], Unit(symbol: "mph", factor: 0.44704, dims: speed)),
        (["kn", "knot", "knots"], Unit(symbol: "kn", factor: 1852.0 / 3600, dims: speed)),

        (["hz", "hertz"], Unit(symbol: "Hz", factor: 1, dims: frequency)),
        (["khz"], Unit(symbol: "kHz", factor: 1e3, dims: frequency)),
        (["mhz"], Unit(symbol: "MHz", factor: 1e6, dims: frequency)),
        (["ghz"], Unit(symbol: "GHz", factor: 1e9, dims: frequency)),
    ]

    private static let byName: [String: Unit] = {
        var map: [String: Unit] = [:]
        for (names, unit) in all { for name in names { map[name] = unit } }
        return map
    }()

    private static let symbols: [String: Unit] = {
        Dictionary(all.map { ($0.unit.symbol, $0.unit) }, uniquingKeysWith: { a, _ in a })
    }()

    /// What a mixed product like "Mbps·s" is shown in.
    static let baseUnits: [Unit] = ["m", "kg", "s", "B", "rad", "l"].compactMap { symbols[$0] }

    static func lookup(_ name: String) -> Unit? { byName[name.lowercased()] }
    static func bySymbol(_ symbol: String) -> Unit? { symbols[symbol] }
}
