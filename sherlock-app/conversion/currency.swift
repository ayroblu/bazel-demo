import Foundation

public struct CurrencyRequest: Sendable {
  let amount: Double
  let from: String
  let to: String
}

public func parseCurrencyRequest(_ text: String) -> CurrencyRequest? {
  let pattern =
    /\s*([$£€¥])?\s*(\d[\d,]*\.?\d*)\s*([a-z]{3}|[$£€¥])?\s+(?:in|to|as|into)\s+([a-z]{3}|[$£€¥])\s*/
  guard let match = text.lowercased().wholeMatch(of: pattern),
    let amount = Double(match.2.replacing(",", with: "")),
    let from = currencyCode(match.1 ?? match.3), let to = currencyCode(match.4)
  else { return nil }
  return CurrencyRequest(amount: amount, from: from, to: to)
}

@MainActor
public final class ExchangeRates {
  public var onUpdate: () -> Void = {}
  private var cache: RatesCache?
  private var isFetching = false
  private var lastAttempt = Date.distantPast

  public init() {
    cache = (try? Data(contentsOf: cacheURL)).flatMap {
      try? JSONDecoder().decode(RatesCache.self, from: $0)
    }
  }

  public func convert(_ request: CurrencyRequest) -> Conversion? {
    refreshIfStale()
    guard let cache, let fromRate = cache.rates[request.from], let toRate = cache.rates[request.to]
    else { return nil }
    let converted = request.amount / fromRate * toRate
    let result = "\(formatNumber(converted, grouping: true)) \(request.to)"
    return Conversion(
      result: result, value: formatNumber(converted, grouping: false),
      detail:
        "\(formatNumber(request.amount, grouping: true)) \(request.from) = \(result) · ECB rate of \(cache.date)"
    )
  }

  private func refreshIfStale() {
    guard !isFetching, Date().timeIntervalSince(cache?.fetchedAt ?? .distantPast) > 12 * 60 * 60,
      Date().timeIntervalSince(lastAttempt) > 60
    else { return }
    isFetching = true
    lastAttempt = Date()
    Task {
      defer { isFetching = false }
      guard let fetched = await fetchRates() else { return }
      cache = fetched
      try? FileManager.default.createDirectory(
        at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? JSONEncoder().encode(fetched).write(to: cacheURL, options: [.atomic])
      onUpdate()
    }
  }
}

private func currencyCode(_ text: Substring?) -> String? {
  guard let text else { return nil }
  let code = currencySymbols[String(text)] ?? text.uppercased()
  return supportedCurrencies.contains(code) ? code : nil
}

private let currencySymbols = ["$": "USD", "£": "GBP", "€": "EUR", "¥": "JPY"]

private let supportedCurrencies: Set<String> = [
  "AUD", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP", "HKD", "HUF", "IDR",
  "ILS", "INR", "ISK", "JPY", "KRW", "MXN", "MYR", "NOK", "NZD", "PHP", "PLN", "RON", "SEK",
  "SGD", "THB", "TRY", "USD", "ZAR",
]

private struct RatesCache: Codable {
  let fetchedAt: Date
  let date: String
  let rates: [String: Double]
}

private let cacheURL = URL.cachesDirectory.appending(path: "com.ayroblu.sherlock/rates.json")

@concurrent private func fetchRates() async -> RatesCache? {
  struct Response: Decodable {
    let date: String
    let rates: [String: Double]
  }
  let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=USD")!
  guard let (data, _) = try? await URLSession.shared.data(from: url),
    let response = try? JSONDecoder().decode(Response.self, from: data)
  else { return nil }
  return RatesCache(
    fetchedAt: Date(), date: response.date, rates: response.rates.merging(["USD": 1]) { $1 })
}
