use thiserror::Error;

pub struct DbExecutable {
    pub statement: String,
    pub values: Vec<SqlValue>,
}
impl DbExecutable {
    pub fn new<I>(statement: &str, values: I) -> Self
    where
        I: IntoSqlValues,
    {
        DbExecutable {
            statement: statement.to_string(),
            values: values.into_sql_values(),
        }
    }
}
pub struct DbSelectable<T: FromQuery> {
    pub executable: DbExecutable,
    pub columns: Vec<ColumnType>,
    _phantom: std::marker::PhantomData<T>,
}
impl<T: FromQuery> DbSelectable<T> {
    pub fn new<I>(statement: &str, values: I, columns: Vec<ColumnType>) -> Self
    where
        I: IntoSqlValues,
    {
        DbSelectable {
            executable: DbExecutable::new(statement, values),
            columns,
            _phantom: std::marker::PhantomData,
        }
    }
    pub fn parse_values(&self, values: Vec<SqlValue>) -> Result<T, DbSqliteError> {
        T::parse(values)
    }
}

pub trait IntoSqlValues {
    fn into_sql_values(self) -> Vec<SqlValue>;
}
impl IntoSqlValues for () {
    fn into_sql_values(self) -> Vec<SqlValue> {
        Vec::new()
    }
}
impl<T: FromSqlValue> IntoSqlValues for Vec<T> {
    fn into_sql_values(self) -> Vec<SqlValue> {
        self.into_iter().map(|v| v.get_sql_value()).collect()
    }
}

#[derive(Debug)]
pub enum ColumnType {
    Int,
    Text,
    Bool,
    Long,
    Date,
    Blob,
    Real,
}
pub trait FromQuery: Sized {
    fn parse(values: Vec<SqlValue>) -> Result<Self, DbSqliteError>;
}
#[derive(Debug)]
pub enum SqlValue {
    Int(i32),
    Text(String),
    Bool(bool),
    Long(i64),
    Double(f64),
    Date(std::time::SystemTime),
    Blob(Vec<u8>),
    Null,
}
pub trait FromSqlValue: Sized {
    fn extract_value(value: SqlValue) -> Result<Self, SqlValue>;
    fn expected_type() -> &'static str;
    fn get_sql_value(self) -> SqlValue;
}
impl FromSqlValue for i32 {
    fn extract_value(value: SqlValue) -> Result<Self, SqlValue> {
        match value {
            SqlValue::Int(i) => Ok(i),
            _ => Err(value),
        }
    }
    fn expected_type() -> &'static str {
        "Int"
    }
    fn get_sql_value(self) -> SqlValue {
        SqlValue::Int(self)
    }
}
impl FromSqlValue for String {
    fn extract_value(value: SqlValue) -> Result<Self, SqlValue> {
        match value {
            SqlValue::Text(s) => Ok(s),
            _ => Err(value),
        }
    }
    fn expected_type() -> &'static str {
        "Text"
    }
    fn get_sql_value(self) -> SqlValue {
        SqlValue::Text(self)
    }
}
impl FromSqlValue for Vec<u8> {
    fn extract_value(value: SqlValue) -> Result<Self, SqlValue> {
        match value {
            SqlValue::Blob(b) => Ok(b),
            _ => Err(value),
        }
    }
    fn expected_type() -> &'static str {
        "Blob"
    }
    fn get_sql_value(self) -> SqlValue {
        SqlValue::Blob(self)
    }
}
impl SqlValue {
    pub fn get_nonnull<T: FromSqlValue>(self) -> Result<T, DbSqliteError> {
        if let SqlValue::Null = self {
            return Err(DbSqliteError::ParseNull);
        }
        match T::extract_value(self) {
            Ok(t) => Ok(t),
            Err(v) => Err(DbSqliteError::ParseInvalidType {
                expected: T::expected_type().to_string(),
                actual: format!("{:?}", v),
            }),
        }
    }
    pub fn get<T: FromSqlValue>(self) -> Result<Option<T>, DbSqliteError> {
        match self {
            SqlValue::Null => Ok(None),
            _ => match T::extract_value(self) {
                Ok(t) => Ok(Some(t)),
                Err(v) => Err(DbSqliteError::ParseInvalidType {
                    expected: format!("{} or NULL", T::expected_type()),
                    actual: format!("{:?}", v),
                }),
            },
        }
    }
}

#[derive(Error, Debug)]
pub enum DbSqliteError {
    /// https://www.sqlite.org/rescode.html
    #[error("Open failed with code: {0}")]
    OpenFailed(i32),
    #[error("Prepare failed for statement: {0}, with code: {1}")]
    PrepareFailed(String, i32),
    #[error("Step failed for statement: {0}, with code: {1}")]
    StepFailed(String, i32),
    // #[error("Step failed for statement: {statement}, with code: {code}")]
    // StepFailed {
    //     statement: String,
    //     code: isize,
    // },
    #[error("Parse received null for non null")]
    ParseNull,
    #[error("Parse invalid type: expected: {expected}, got: {actual}")]
    ParseInvalidType { expected: String, actual: String },
    #[error("Parse invalid length: {0} != {1}")]
    ParseInvalidLength(usize, usize),
    #[error("Time overflow")]
    SystemTimeError(),
}
