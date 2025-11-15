import Foundation

extension Date {
  public func add(by: Calendar.Component, value: Int) -> Date {
    // return Calendar.current.date(byAdding: .day, value: -7, to: self)!
    return Calendar.current.date(byAdding: by, value: value, to: self)!
  }

  /// UTS #35 format:
  /// Year:
  /// * yyyy: Four-digit year (e.g., 2025)
  /// * yy: Two-digit year (e.g., 25)
  /// Month:
  /// * MM: Two-digit month (e.g., 08 for August)
  /// * M: One or two-digit month (e.g., 8 for August)
  /// * MMM: Abbreviated month name (e.g., Aug)
  /// * MMMM: Full month name (e.g., August)
  /// * MMMMM: Narrow month name (e.g., A)
  /// Day:
  /// * dd: Two-digit day of the month (e.g., 25)
  /// * d: One or two-digit day of the month (e.g., 5 or 25)
  /// Weekday:
  /// * EEE: Abbreviated weekday name (e.g., Mon)
  /// * EEEE: Full weekday name (e.g., Monday)
  /// * EEEEE: Narrow weekday name (e.g., M)
  /// Hour:
  /// * HH: Two-digit hour in 24-hour format (e.g., 14 for 2 PM)
  /// * H: One or two-digit hour in 24-hour format (e.g., 2 or 14)
  /// * hh: Two-digit hour in 12-hour format (e.g., 02 for 2 AM/PM)
  /// * h: One or two-digit hour in 12-hour format (e.g., 2 for 2 AM/PM)
  /// Minute:
  /// * mm: Two-digit minute (e.g., 05)
  /// Second:
  /// * ss: Two-digit second (e.g., 37)
  /// Time Zone:
  /// * zzz: Three-letter time zone abbreviation (e.g., GMT)
  /// * zzzz: Full time zone name (e.g., Greenwich Mean Time)
  /// * Z: Time zone offset from UTC in the format +HHmm or -HHmm (e.g., +0200)
  /// Era:
  /// * G: Abbreviated era (e.g., AD)
  /// * GGGG: Full era name (e.g., Anno Domini)
  public func format(uts35: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = uts35
    return formatter.string(from: self)
  }

  public func formatTimeWithMillis() -> String {
    return format(uts35: "HH:mm:ss.SSS")
  }
  public func formatTime() -> String {
    return format(uts35: "HH:mm:ss")
  }
}
