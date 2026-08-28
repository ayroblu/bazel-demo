import Foundation

/// Anki counts days from a rollover hour rather than midnight, and every day scale interval
/// lands on that boundary. Both the scheduler and the daily queue measure days this way.
public struct SchedulerCalendar: Sendable {
  public static let defaultRolloverHour = 4

  public let rolloverHour: Int
  public let calendar: Calendar

  public init(rolloverHour: Int = SchedulerCalendar.defaultRolloverHour, calendar: Calendar = .current) {
    self.rolloverHour = min(max(rolloverHour, 0), 23)
    self.calendar = calendar
  }

  /// The rollover instant that opened the day containing `date`.
  public func startOfDay(for date: Date) -> Date {
    let midnight = calendar.startOfDay(for: date)
    let rollover = calendar.date(byAdding: .hour, value: rolloverHour, to: midnight) ?? midnight
    guard date < rollover else { return rollover }
    return calendar.date(byAdding: .day, value: -1, to: rollover) ?? rollover
  }

  public func startOfDay(byAdding days: Int, to date: Date) -> Date {
    let start = startOfDay(for: date)
    return calendar.date(byAdding: .day, value: days, to: start) ?? start.addingTimeInterval(86_400 * Double(days))
  }

  /// When the day containing `date` gives way to the next one.
  public func endOfDay(for date: Date) -> Date {
    startOfDay(byAdding: 1, to: date)
  }

  /// Whole days between two instants, which is what FSRS calls elapsed days. Two reviews in
  /// one Anki day are zero days apart no matter how many hours separate them.
  public func elapsedDays(from start: Date, to end: Date) -> Int {
    let days = calendar.dateComponents(
      [.day],
      from: startOfDay(for: start),
      to: startOfDay(for: end)
    ).day ?? 0
    return max(0, days)
  }
}
