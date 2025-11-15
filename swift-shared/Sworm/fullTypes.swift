// public struct Database {
//   public let tables: [Table]
//   public let name: String?
//   public let dirPath: URL?
//   private var db: OpaquePointer?

//   public init(tables: [Table], name: String? = nil, dirPath: URL? = nil) {
//     self.tables = tables
//     self.name = name
//     self.dirPath = dirPath
//   }
// }

public struct Table {
  public let name: String
  public let columns: [Column]
  public let multicolumnIndexes: [[String]]

  public init(name: String, columns: [Column], multicolumnIndexes: [[String]] = []) {
    self.name = name
    self.columns = columns
    self.multicolumnIndexes = multicolumnIndexes
  }
}

public struct Column {
  public let name: String
  public let type: DataType
  public let primaryKey: Bool?
  public let unique: Bool?
  public let nullable: Bool?
  public let indexed: Bool?
  public let defaultValue: String?  // warning: raw sql injection

  public init(
    name: String,
    type: DataType,
    primaryKey: Bool? = nil,
    unique: Bool? = nil,
    nullable: Bool? = nil,
    indexed: Bool? = nil,
    defaultValue: String? = nil
  ) {
    self.name = name
    self.type = type
    self.primaryKey = primaryKey
    self.unique = unique
    self.nullable = nullable
    self.indexed = indexed
    self.defaultValue = defaultValue
  }
}

enum DbSchemaUpdate {
  case createTable(table: Table)
  case alterTable(tableName: String)  // add, rename, drop column
  case dropTable(tableName: String)
}

public struct SelectQuery {
  let columns: [(String, DataType)]  // name, datatype
  let whereFilter: [(String, String)]  // name, value (String, Int, Real etc?)
}

public enum WhereFilter {
  // = != < > <= >=
  // ALL AND ANY BETWEEN EXISTS IN LIKE NOT OR
  case equals(name: String, value: String)
}
