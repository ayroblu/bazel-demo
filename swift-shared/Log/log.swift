import DateUtils
import Foundation

public func log(key: String, _ args: Any...) {
  log(key: key, args: args)
}
public func log(_ args: Any...) {
  log(key: "I", args: args)
}

private func log(key: String, args: [Any]) {
  log(LogItem(date: Date(), key: key, args: args))
}
private func log(_ logItem: LogItem) {
  for effect in logEffects {
    effect(logItem)
  }
}

public struct LogItem: @unchecked Sendable {
  public let date: Date
  public let key: String
  public let args: [Any]

  public init(date: Date = Date(), key: String, args: [Any]) {
    self.date = date
    self.key = key
    self.args = args
  }

  public func getFullText() -> String {
    let timeString = Date().formatTimeWithMillis()

    let argsText = getText()
    let text = "\(timeString) \(argsText)"
    return text
  }

  public func getText() -> String {
    let argsText = args.map { String(describing: $0) }.joined(separator: " ")
    return "\(key): \(argsText)"
  }
}

public typealias LogEffect = @Sendable (LogItem) -> Void

public func stdoutEffect(_ logItem: LogItem) {
  print(logItem.getFullText())
}

nonisolated(unsafe) var logEffects = [stdoutEffect]

public func registerLogEffects(effects: [LogEffect]) {
  logEffects = effects
}
