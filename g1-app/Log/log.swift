import Foundation
import SwiftData

// insert into modelContext (swiftdata)
// on init, delete old entries
// fetch with swiftdata

@MainActor var modelContext: ModelContext?
@MainActor public func initLogDb(_ _modelContext: ModelContext) {
  modelContext = _modelContext
  try? deleteOldEntries(modelContext: _modelContext)
}

public func log(key: String, _ args: Any...) {
  log(key: key, args: args)
}
public func log(_ args: Any...) {
  log(key: "INFO", args: args)
}
func log(key: String, args: [Any]) {
  let formatter = DateFormatter()
  formatter.dateFormat = "HH:mm:ss.SSS"  // Hours:Minutes:Seconds.Milliseconds

  let timeString = formatter.string(from: Date())

  print(timeString, terminator: " ")
  for arg in args {
    print(arg, terminator: " ")
  }
  print()
  Task { @MainActor in
    modelContext?.insert(
      Log(
        timestamp: Date(), key: key,
        text: args.map { String(describing: $0) }.joined(separator: " "))
    )
  }
}

// Function to delete entries older than 1 week
func deleteOldEntries(modelContext: ModelContext) throws {
  // Calculate the date 1 week ago
  let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!

  // Create a predicate for entries with timestamp older than 1 week ago
  let predicate = #Predicate<Log> { entry in
    entry.timestamp < oneWeekAgo
  }

  // Fetch the entries that match our criteria
  let descriptor = FetchDescriptor<Log>(predicate: predicate)
  let oldEntries = try modelContext.fetch(descriptor)

  // Delete each entry
  for entry in oldEntries {
    modelContext.delete(entry)
  }

  // Save the changes
  try modelContext.save()

  if oldEntries.count > 0 {
    log("Deleted \(oldEntries.count) entries older than 1 week")
  }
}
