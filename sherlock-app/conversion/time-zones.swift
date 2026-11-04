import Foundation

public func convertTime(_ text: String, now: Date = Date()) -> Conversion? {
  let input = text.lowercased().trimmingCharacters(in: .whitespaces)
  if let match = input.wholeMatch(of: /(?:time|now) in (.+)|(.+) time/),
    let place = place(named: match.1 ?? match.2 ?? ""), !(match.1 ?? match.2 ?? "").isEmpty
  {
    let result = format(now, in: place.zone)
    return Conversion(
      result: "\(result) in \(place.name)", value: result,
      detail: "Now in \(place.name) (\(offset(place.zone, at: now)))")
  }
  let pattern = /(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(.*?)\s+(?:in|to)\s+(.+)/
  guard let match = input.wholeMatch(of: pattern), var hour = Int(match.1),
    let from = place(named: match.4), let to = place(named: match.5)
  else { return nil }
  let minute = match.2.flatMap { Int($0) } ?? 0
  if let period = match.3 {
    guard (1...12).contains(hour) else { return nil }
    hour = hour % 12 + (period == "pm" ? 12 : 0)
  }
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = from.zone
  guard hour < 24, minute < 60,
    let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: now)
  else { return nil }
  let result = format(date, in: to.zone, relativeTo: from.zone)
  return Conversion(
    result: "\(result) in \(to.name)", value: result,
    detail: "\(format(date, in: from.zone)) in \(from.name) = \(result) in \(to.name)")
}

private func place(named name: Substring) -> (zone: TimeZone, name: String)? {
  let key = name.trimmingCharacters(in: .whitespaces)
  if key.isEmpty || key == "local" || key == "here" { return (.current, "local time") }
  let identifier =
    zoneAliases[key] ?? zoneIdentifiers[key]
    ?? (key.count <= 5 ? TimeZone(abbreviation: key.uppercased())?.identifier : nil)
  return identifier.flatMap(TimeZone.init(identifier:)).map { ($0, cityName($0)) }
}

private let zoneIdentifiers = Dictionary(
  TimeZone.knownTimeZoneIdentifiers.flatMap { identifier in
    [(identifier.lowercased(), identifier), (cityName(identifier).lowercased(), identifier)]
  },
  uniquingKeysWith: { first, _ in first })

private let zoneAliases = [
  "sf": "America/Los_Angeles", "san francisco": "America/Los_Angeles",
  "la": "America/Los_Angeles", "seattle": "America/Los_Angeles", "nyc": "America/New_York",
  "ny": "America/New_York", "boston": "America/New_York", "uk": "Europe/London",
  "england": "Europe/London", "germany": "Europe/Berlin", "france": "Europe/Paris",
  "spain": "Europe/Madrid", "italy": "Europe/Rome", "japan": "Asia/Tokyo",
  "india": "Asia/Kolkata", "china": "Asia/Shanghai", "beijing": "Asia/Shanghai",
  "hk": "Asia/Hong_Kong", "korea": "Asia/Seoul", "australia": "Australia/Sydney",
  "nz": "Pacific/Auckland", "new zealand": "Pacific/Auckland", "utc": "UTC", "gmt": "GMT",
]

private func format(_ date: Date, in zone: TimeZone, relativeTo source: TimeZone? = nil) -> String {
  var style = Date.FormatStyle(date: .omitted, time: .shortened)
  style.timeZone = zone
  let time = date.formatted(style)
  guard let source else { return time }
  var sourceCalendar = Calendar(identifier: .gregorian)
  sourceCalendar.timeZone = source
  var targetCalendar = Calendar(identifier: .gregorian)
  targetCalendar.timeZone = zone
  let sourceDay = sourceCalendar.dateComponents([.year, .month, .day], from: date)
  let targetDay = targetCalendar.dateComponents([.year, .month, .day], from: date)
  guard sourceDay != targetDay else { return time }
  var dayStyle = Date.FormatStyle().weekday(.abbreviated)
  dayStyle.timeZone = zone
  return "\(time) \(date.formatted(dayStyle))"
}

private func cityName(_ zone: TimeZone) -> String {
  cityName(zone.identifier)
}

private func cityName(_ identifier: String) -> String {
  (identifier.split(separator: "/").last.map(String.init) ?? identifier).replacing("_", with: " ")
}

private func offset(_ zone: TimeZone, at date: Date) -> String {
  let seconds = zone.secondsFromGMT(for: date)
  let hours = Double(seconds) / 3600
  return "GMT" + (seconds == 0 ? "" : (hours > 0 ? "+" : "") + formatNumber(hours, grouping: false))
}
