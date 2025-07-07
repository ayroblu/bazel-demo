import Foundation

/// format is like HH:mm:ss
public func formatDate(_ format: String, date: Date = Date()) -> String {
  let formatter = DateFormatter()
  formatter.dateFormat = format
  return formatter.string(from: Date())
}
