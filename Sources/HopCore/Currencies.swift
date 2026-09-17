import Foundation

/// Exchange rates for the calculator: "100 usd to eur", "$20 + 15%", "€5".
public struct Currencies: Equatable, Sendable {
    /// Day the rates are for, as the source reports it ("2026-09-17").
    public var date: String?
    /// Units of each currency per US dollar, by upper-case code.
    public var perDollar: [String: Double]
    /// What an amount without "to …" is shown in, e.g. ["RUB", "EUR"].
    public var targets: [String]

    public init(date: String? = nil, perDollar: [String: Double] = [:], targets: [String] = []) {
        self.date = date
        self.perDollar = perDollar
        self.targets = targets
    }

    /// Reads a USD file of github.com/fawazahmed0/exchange-api:
    /// `{"date": "…", "usd": {"eur": 0.92, …}}`. Keeps ISO currencies plus
    /// BTC and ETH; the rest of its crypto list is full of words like "one".
    public static func parse(_ data: Data) throws -> Currencies {
        struct File: Decodable {
            var date: String
            var usd: [String: Double]
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        var rates: [String: Double] = [:]
        for (code, rate) in file.usd where rate > 0 && rate.isFinite {
            let upper = code.uppercased()
            if known.contains(upper) { rates[upper] = rate }
        }
        guard rates["USD"] != nil else { throw CocoaError(.coderInvalidValue) }
        return Currencies(date: file.date, perDollar: rates)
    }

    private static let known = Set(Locale.Currency.isoCurrencies.map(\.identifier)).union(["BTC", "ETH"])

    /// Symbols that stand for a currency on their own: "$100", "100€".
    static let symbols: [Character: String] = [
        "$": "USD", "€": "EUR", "£": "GBP", "₽": "RUB", "¥": "JPY", "₴": "UAH", "₸": "KZT",
        "₺": "TRY", "₹": "INR", "₩": "KRW", "₾": "GEL", "֏": "AMD", "₿": "BTC",
    ]

    private static let words: [String: String] = [
        "dollar": "USD", "dollars": "USD", "bucks": "USD", "euro": "EUR", "euros": "EUR",
        "ruble": "RUB", "rubles": "RUB", "rouble": "RUB", "roubles": "RUB", "yen": "JPY",
        "yuan": "CNY", "lari": "GEL", "tenge": "KZT", "hryvnia": "UAH", "bitcoin": "BTC",
    ]

    /// A currency by code, symbol or name, valued in dollars.
    func lookup(_ name: String) -> Unit? {
        let code = name.count == 1 ? name.first.flatMap { Self.symbols[$0] } : Self.words[name.lowercased()] ?? name.uppercased()
        guard let code, let rate = perDollar[code] else { return nil }
        return Unit(symbol: code, factor: 1 / rate, dims: Units.currency)
    }

    /// The currency a token names, unless it's already some other unit ("t", "in").
    func unit(_ token: Token) -> Unit? {
        guard case .ident(let name) = token, Units.lookup(name) == nil else { return nil }
        return lookup(name)
    }
}
