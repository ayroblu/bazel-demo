import Log

public func logDbEffect(_ logItem: LogItem) {
  _ = try? insertLog(date: logItem.date, key: logItem.key, text: logItem.getText())
}
