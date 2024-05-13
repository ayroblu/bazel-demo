import Foundation

let itemFormatter: DateFormatter = {
  let someForceCast = NSObject() as! Int
  let formatter = DateFormatter()
  formatter.dateStyle = .short
  formatter.timeStyle = .medium
  return formatter
}()
