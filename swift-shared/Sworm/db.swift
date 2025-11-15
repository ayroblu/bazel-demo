import FileUtils
import Foundation
import SQLite3

public class Database {
  var db: OpaquePointer?

  public init(name: String? = nil, dirPath: URL? = nil, migrations: [Migration]) throws {
    try openDatabase(name: name ?? "mydb.sqlite", dirPath: dirPath ?? defaultDirPath())
    // todo: ensure migrations are in order

    try createManagementTable()
    try runMigrations(migrations: migrations)
  }

  private func openDatabase(name: String, dirPath: URL) throws {
    print("opening database at: \(dirPath)\(name)")
    try mkdirp(dirPath)
    let filePath = dirPath / name

    let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
    let openCode = sqlite3_open_v2(filePath.path, &db, flags, nil)
    guard openCode == SQLITE_OK else { throw SwormError.openFailed(openCode) }
  }
}

func defaultDirPath() -> URL {
  return try! FileManager.default.url(
    for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false
  ) / (Bundle.main.bundleIdentifier ?? "__unknown__")
}

public enum DataType {
  case bool  // (Bool)
  case int  // (Int32)
  case long  // (Int64)
  case text  // (String)
  case date  // (Date)
  case blob  // (Data)
  case real  // (Double)
}

extension Database {
  private func getRows<T>(statementPointer: OpaquePointer?, executable: SwormSelectable<T>) throws
    -> [T]
  {
    var results: [T] = []
    var stepCode = sqlite3_step(statementPointer)
    while stepCode == SQLITE_ROW {
      defer { stepCode = sqlite3_step(statementPointer) }
      var values: [Any?] = []
      var counter: Int32 = 0
      for column in executable.columns {
        defer { counter += 1 }
        if sqlite3_column_type(statementPointer, counter) == SQLITE_NULL {
          values.append(nil)
          continue
        }
        switch column {
        case .int:
          values.append(sqlite3_column_int(statementPointer, counter))
        case .text:
          values.append(
            String(describing: String(cString: sqlite3_column_text(statementPointer, counter)))
          )
        case .bool:
          values.append(sqlite3_column_int(statementPointer, counter) > 0)
        case .long:
          values.append(sqlite3_column_int64(statementPointer, counter))
        case .date:
          let millis = sqlite3_column_int64(statementPointer, counter)
          let seconds = TimeInterval(millis) / 1000.0
          let date = Date(timeIntervalSince1970: seconds)
          values.append(date)
        case .blob:
          if let pointer = sqlite3_column_blob(statementPointer, counter) {
            let size = sqlite3_column_bytes(statementPointer, counter)
            let data = Data(bytes: pointer, count: Int(size))
            values.append(data)
          } else {
            let data = Data()
            values.append(data)
          }
        case .real:
          values.append(sqlite3_column_double(statementPointer, counter))
        }
      }
      results.append(try executable.parse(values))
    }
    guard stepCode == SQLITE_DONE else {
      throw SwormError.stepFailed(executable.statement, stepCode)
    }
    return results
  }

  private func injectValues(statementPointer: OpaquePointer?, values: [Any?]) {
    var counter: Int32 = 1
    for value in values {
      defer { counter += 1 }
      if let intValue = value as? Int32 {
        sqlite3_bind_int(statementPointer, counter, intValue)
      } else if let textValue = value as? String {
        sqlite3_bind_text(statementPointer, counter, (textValue as NSString).utf8String, -1, nil)
      } else if let boolValue = value as? Bool {
        sqlite3_bind_int(statementPointer, counter, boolValue ? 1 : 0)
      } else if let longValue = value as? Int64 {
        sqlite3_bind_int64(statementPointer, counter, longValue)
      } else if let doubleValue = value as? Double {
        sqlite3_bind_double(statementPointer, counter, doubleValue)
      } else if let dateValue = value as? Date {
        sqlite3_bind_int64(
          statementPointer, counter, Int64(dateValue.timeIntervalSince1970 * 1000))
      } else if let blobValue = value as? Data {
        _ = blobValue.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
          sqlite3_bind_blob(
            statementPointer, counter, bytes.baseAddress, Int32(blobValue.count), SQLITE_TRANSIENT)
        }
      }
    }
  }

  public func execute<T>(_ executable: SwormSelectable<T>) throws -> [T] {
    // print("execute \(executable.statement)")
    var statementPointer: OpaquePointer? = nil
    let prepareCode = sqlite3_prepare_v2(db, executable.statement, -1, &statementPointer, nil)
    guard prepareCode == SQLITE_OK else {
      throw SwormError.prepareFailed(executable.statement, prepareCode)
    }
    injectValues(statementPointer: statementPointer, values: executable.values)
    let rows: [T] = try getRows(
      statementPointer: statementPointer, executable: executable)
    sqlite3_finalize(statementPointer)
    return rows
  }
  public func executeOnly(_ executable: SwormExecutable) throws {
    // print("executeOnly \(executable.statement)")
    var statementPointer: OpaquePointer? = nil
    let prepareCode = sqlite3_prepare_v2(db, executable.statement, -1, &statementPointer, nil)
    guard prepareCode == SQLITE_OK else {
      throw SwormError.prepareFailed(executable.statement, prepareCode)
    }
    injectValues(statementPointer: statementPointer, values: executable.values)
    var stepCode = sqlite3_step(statementPointer)
    while stepCode == SQLITE_ROW {
      stepCode = sqlite3_step(statementPointer)
    }
    guard stepCode == SQLITE_DONE else {
      throw SwormError.stepFailed(executable.statement, stepCode)
    }
    sqlite3_finalize(statementPointer)
  }
}
// https://stackoverflow.com/questions/26883131/sqlite-transient-undefined-in-swift
let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum SwormError: Error {
  /// https://www.sqlite.org/rescode.html
  case openFailed(Int32)
  case prepareFailed(String, Int32)
  case stepFailed(String, Int32)

  case parseInsufficientData
  case parseInvalidType(String)
}

extension Date {
  public init(fromISO8601String isoString: String) {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [
      .withInternetDateTime, .withFractionalSeconds,
    ]
    self = formatter.date(from: isoString)!
  }
}

public class SwormExecutable {
  let statement: String
  let values: [Any?]

  public init(statement: String, values: [Any?] = []) {
    self.statement = statement
    self.values = values
  }
}
public class SwormSelectable<Result>: SwormExecutable {
  let columns: [DataType]
  let parse: (([Any?]) throws -> Result)

  public init(
    statement: String, values: [Any] = [], columns: [DataType],
    parse: @escaping (([Any?]) throws -> Result)
  ) {
    self.columns = columns
    self.parse = parse
    super.init(statement: statement, values: values)
  }
}

public func parseAny<T>(_ input: T.Type, _ value: Any?) throws -> T {
  guard let result = value as? T else {
    throw SwormError.parseInvalidType("Expected \(input), got \(type(of: value))")
  }
  return result
}
