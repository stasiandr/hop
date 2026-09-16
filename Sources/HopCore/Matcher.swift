import Foundation

/// Fuzzy subsequence matcher tuned for short launcher queries.
public enum Matcher {
    /// Returns a score for `query` against `candidate`, or nil if it doesn't match.
    /// Higher is better. Rewards prefix matches, word starts and consecutive runs.
    public static func score(_ query: String, _ candidate: String) -> Int? {
        let q = Array(query.lowercased())
        let c = Array(candidate.lowercased())
        guard !q.isEmpty else { return 0 }
        guard q.count <= c.count else { return nil }

        if c == q { return 1000 }

        let orig = Array(candidate)
        let bonus = c.indices.map { ci -> Int in
            if ci == 0 { return 16 }
            return isWordStart(original: orig, index: ci, lowered: c) ? 11 : 1
        }

        // best[i][j]: best score with q[i] matched at c[j]. Picks the best
        // alignment rather than the first, so "ss" hits "System Settings" on
        // both word starts.
        var prev = [Int?](repeating: nil, count: c.count)
        for (i, qc) in q.enumerated() {
            var cur = [Int?](repeating: nil, count: c.count)
            var bestBefore: Int? = nil // max prev[k] for k < j - 1
            for j in c.indices {
                if j >= 2, let p = prev[j - 2] { bestBefore = max(bestBefore ?? p, p) }
                guard c[j] == qc else { continue }
                if i == 0 { cur[j] = bonus[j]; continue }
                let adjacent = j >= 1 ? prev[j - 1].map { $0 + 8 } : nil
                if let base = [adjacent, bestBefore].compactMap({ $0 }).max() {
                    cur[j] = base + bonus[j]
                }
            }
            prev = cur
        }
        guard let score = prev.compactMap({ $0 }).max() else { return nil }

        // Prefer shorter candidates when everything else is equal.
        return score * 10 - (c.count - q.count)
    }

    private static func isWordStart(original orig: [Character], index: Int, lowered: [Character]) -> Bool {
        let prev = lowered[index - 1]
        if prev == " " || prev == "-" || prev == "_" || prev == "." { return true }
        // camelCase boundary in the original string.
        return orig.count == lowered.count && orig[index].isUppercase && orig[index - 1].isLowercase
    }

    /// Ranks items by their best score across the given search terms.
    /// With an empty query, items keep their original order.
    public static func rank<T>(_ items: [T], query: String, terms: (T) -> [String]) -> [T] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return items }
        return items.enumerated()
            .compactMap { index, item -> (Int, Int, T)? in
                let best = terms(item).compactMap { score(trimmed, $0) }.max()
                return best.map { ($0, index, item) }
            }
            .sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }
            .map(\.2)
    }
}
