import Foundation
import HopCore

/// Exchange rates from github.com/fawazahmed0/exchange-api (free, no key,
/// updated daily), cached in ~/Library/Caches/hop so they work offline.
final class CurrencyStore {
    private static let sources = [
        "https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json",
        "https://latest.currency-api.pages.dev/v1/currencies/usd.min.json",
    ].compactMap(URL.init(string:))

    private static let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("hop/usd.json")

    /// Rates are refreshed when the cache is older than this.
    private static let maxAge: TimeInterval = 12 * 3600
    /// Don't retry more often than this after a failure (e.g. offline).
    private static let retryAfter: TimeInterval = 15 * 60

    private(set) var currencies = Currencies()
    private var fetchedAt: Date?
    private var lastAttempt: Date?
    private var fetching = false

    init() {
        guard let data = try? Data(contentsOf: Self.cacheURL), let cached = try? Currencies.parse(data) else { return }
        currencies = cached
        fetchedAt = (try? FileManager.default.attributesOfItem(atPath: Self.cacheURL.path))?[.modificationDate] as? Date
    }

    /// Fetches new rates in the background if the cached ones are stale;
    /// `onUpdate` runs on the main queue once they're in.
    func refreshIfStale(onUpdate: @escaping () -> Void) {
        let now = Date()
        if let fetchedAt, now.timeIntervalSince(fetchedAt) < Self.maxAge { return }
        if fetching { return }
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < Self.retryAfter { return }
        fetching = true
        lastAttempt = now
        fetch(from: Self.sources) { [weak self] data in
            DispatchQueue.main.async {
                guard let self else { return }
                self.fetching = false
                guard let data, let fresh = try? Currencies.parse(data) else { return }
                try? FileManager.default.createDirectory(at: Self.cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: Self.cacheURL, options: .atomic)
                self.currencies = fresh
                self.fetchedAt = Date()
                onUpdate()
            }
        }
    }

    /// Tries each source in turn until one answers with valid rates.
    private func fetch(from sources: [URL], completion: @escaping (Data?) -> Void) {
        guard let url = sources.first else { return completion(nil) }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let data, (response as? HTTPURLResponse)?.statusCode == 200, (try? Currencies.parse(data)) != nil {
                return completion(data)
            }
            NSLog("hop: exchange rates from \(url.host ?? "?") failed: \(error?.localizedDescription ?? "bad response")")
            self?.fetch(from: Array(sources.dropFirst()), completion: completion)
        }.resume()
    }
}
