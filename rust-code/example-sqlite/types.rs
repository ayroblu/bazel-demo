use std::slice::from_raw_parts;

use libsqlite3_sys::*;
use thiserror::Error;

pub struct DbExecutable {
    pub statement: String,
    pub values: Vec<SqliteValue>,
}
impl DbExecutable {
    pub fn new<I>(statement: &str, values: I) -> Self
    where
        I: IntoSqliteValues,
    {
        DbExecutable {
            statement: statement.to_string(),
            values: values.into_sqlite_values(),
        }
    }
}
pub struct DbSelectable<T: FromSqlite> {
    pub executable: DbExecutable,
    _phantom: std::marker::PhantomData<T>,
}
impl<T: FromSqlite> DbSelectable<T> {
    pub fn new<I>(statement: &str, values: I) -> Self
    where
        I: IntoSqliteValues,
    {
        DbSelectable {
            executable: DbExecutable::new(statement, values),
            _phantom: std::marker::PhantomData,
        }
    }
}

pub trait IntoSqliteValues {
    fn into_sqlite_values(self) -> Vec<SqliteValue>;
}
impl IntoSqliteValues for () {
    fn into_sqlite_values(self) -> Vec<SqliteValue> {
        Vec::new()
    }
}
impl<T: FromSqliteValue> IntoSqliteValues for Vec<T> {
    fn into_sqlite_values(self) -> Vec<SqliteValue> {
        self.into_iter().map(|v| v.get_sqlite_value()).collect()
    }
}
impl IntoSqliteValues for Vec<SqliteValue> {
    fn into_sqlite_values(self) -> Vec<SqliteValue> {
        self
    }
}

pub trait FromSqliteValue: Sized {
    fn get_sqlite_value(self) -> SqliteValue;
    fn parse(value: SqliteValue) -> Result<Self, DbSqliteError>;
}

pub trait FromSqlite: Sized {
    fn parse(row: Row) -> Result<Self, DbSqliteError>;
}

#[derive(Error, Debug, PartialEq)]
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
    #[error("Parse invalid index: length: {0}, index: {1}")]
    ParseInvalidLength(usize, usize),
    #[error("Time overflow")]
    SystemTimeError(),
}

#[derive(Clone, Debug, PartialEq)]
pub enum SqliteValue {
    /// The value is a `NULL` value.
    Null,
    /// The value is a signed integer.
    Integer(i64),
    /// The value is a floating point number.
    Real(f64),
    /// The value is a text string.
    Text(String),
    /// The value is a blob of data
    Blob(Box<[u8]>),
}
impl SqliteValue {
    #[inline]
    #[must_use]
    pub fn type_name(&self) -> &str {
        match *self {
            SqliteValue::Null => "NULL",
            SqliteValue::Integer(_) => "Integer",
            SqliteValue::Real(_) => "Real",
            SqliteValue::Text(_) => "Text",
            SqliteValue::Blob(_) => "Blob",
        }
    }
}

pub fn get_sqlite_value(stmt: *mut sqlite3_stmt, column: i32) -> SqliteValue {
    let column_type = unsafe { sqlite3_column_type(stmt, column) };
    match column_type {
        SQLITE_NULL => SqliteValue::Null,
        SQLITE_INTEGER => SqliteValue::Integer(unsafe { sqlite3_column_int64(stmt, column) }),
        SQLITE_FLOAT => SqliteValue::Real(unsafe { sqlite3_column_double(stmt, column) }),
        SQLITE_TEXT => {
            // Quoting from "Using SQLite" book:
            // To avoid problems, an application should first extract the desired type using
            // a sqlite3_column_xxx() function, and then call the
            // appropriate sqlite3_column_bytes() function.
            let text = unsafe { sqlite3_column_text(stmt, column) };
            let len = unsafe { sqlite3_column_bytes(stmt, column) };
            assert!(
                !text.is_null(),
                "unexpected SQLITE_TEXT column type with NULL data"
            );
            let s = unsafe { from_raw_parts(text.cast::<u8>(), len as usize) };

            SqliteValue::Text(String::from_utf8_lossy(s).into_owned())
        }
        SQLITE_BLOB => {
            let (blob, len) = unsafe {
                (
                    sqlite3_column_blob(stmt, column),
                    sqlite3_column_bytes(stmt, column),
                )
            };

            assert!(
                len >= 0,
                "unexpected negative return from sqlite3_column_bytes"
            );
            if len > 0 {
                assert!(
                    !blob.is_null(),
                    "unexpected SQLITE_BLOB column type with NULL data"
                );
                let s = unsafe { from_raw_parts(blob.cast::<u8>(), len as usize) };
                SqliteValue::Blob(s.to_vec().into_boxed_slice())
            } else {
                // The return value from sqlite3_column_blob() for a zero-length BLOB
                // is a NULL pointer.
                SqliteValue::Blob(vec![].into_boxed_slice())
            }
        }
        _ => unreachable!("sqlite3_column_type returned invalid value"),
    }
}

pub struct Row {
    pub(crate) stmt: *mut sqlite3_stmt,
    pub(crate) length: i32,
}
impl Row {
    pub fn new(stmt: *mut sqlite3_stmt) -> Self {
        let length = unsafe { sqlite3_column_count(stmt) };
        Self { stmt, length }
    }
    pub fn get<T: FromSqliteValue>(&self, column: i32) -> Result<T, DbSqliteError> {
        if column >= self.length {
            return Err(DbSqliteError::ParseInvalidLength(
                self.length as usize,
                column as usize,
            ));
        }
        let value = get_sqlite_value(self.stmt, column);
        T::parse(value)
    }
}
