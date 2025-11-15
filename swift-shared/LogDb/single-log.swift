import Foundation
import Log
import Sworm

public func SingleLog() -> (Any...) -> Void {
  var previous: LogIdModel? = nil

  return { args in
    let key = "I"
    print(LogItem(key: key, args: args).getText())

    guard db != nil else {
      // print("Log: no db, no persistence")
      return
    }
    do {
      let logIdModel = try logModel(key: key, args: args)
      if let previous {
        do {
          try db!.executeOnly(deleteLogByIdExecutable(previous.id))
        } catch {
          print("SingleLog: error while deleting:", error)
        }
      }
      previous = logIdModel
    } catch {
      print("SingleLog: error while saving:", error)
    }
  }
}

private func logModel(key: String, args: [Any]) throws -> LogIdModel? {
  let text = args.map { String(describing: $0) }.joined(separator: " ")
  let result = try db!.execute(insertLogExecutable(date: Date(), key: key, text: text))
  return result.first
}
