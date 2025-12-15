use std::time::{Duration, SystemTime, UNIX_EPOCH};

use crate::types::*;

impl FromSqliteValue for bool {
    fn get_sqlite_value(self) -> SqliteValue {
        let value = if self { 1 } else { 0 };
        SqliteValue::Integer(value)
    }
    fn parse(value: SqliteValue) -> Result<Self, DbSqliteError> {
        match value {
            SqliteValue::Integer(i) => Ok(i > 0),
            _ => Err(parse_typeerror("Integer", value)),
        }
    }
}
impl FromSqliteValue for i32 {
    fn get_sqlite_value(self) -> SqliteValue {
        SqliteValue::Integer(self as i64)
    }
    fn parse(value: SqliteValue) -> Result<Self, DbSqliteError> {
        match value {
            SqliteValue::Integer(i) => Ok(i as i32),
            _ => Err(parse_typeerror("Integer", value)),
        }
    }
}
impl FromSqliteValue for i64 {
    fn get_sqlite_value(self) -> SqliteValue {
        SqliteValue::Integer(self)
    }
    fn parse(value: SqliteValue) -> Result<Self, DbSqliteError> {
        match value {
            SqliteValue::Integer(i) => Ok(i),
            _ => Err(parse_typeerror("Integer", value)),
        }
    }
}
impl FromSqliteValue for Option<i64> {
    fn get_sqlite_value(self) -> SqliteValue {
        self.map_or_else(|| SqliteValue::Null, |v| SqliteValue::Integer(v))
    }
    fn parse(value: SqliteValue) -> Result<Self, DbSqliteError> {
        if value == SqliteValue::Null {
            return Ok(None);
        }
        return i64::parse(value).map(|v| Some(v));
    }
}
impl FromSqliteValue for String {
    fn get_sqlite_value(self) -> SqliteValue {
        SqliteValue::Text(self)
    }
    fn parse(value: SqliteValue) -> Result<Self, DbSqliteError> {
        match value {
            SqliteValue::Text(s) => Ok(s),
            _ => Err(parse_typeerror("Text", value)),
        }
    }
}
impl FromSqliteValue for Option<String> {
    fn get_sqlite_value(self) -> SqliteValue {
        self.map_or_else(|| SqliteValue::Null, |v| SqliteValue::Text(v))
    }
    fn parse(value: SqliteValue) -> Result<Self, DbSqliteError> {
        match value {
            SqliteValue::Null => Ok(None),
            _ => String::parse(value).map(|v| Some(v)),
        }
    }
}
impl FromSqliteValue for SystemTime {
    fn get_sqlite_value(self) -> SqliteValue {
        let epoch_duration = self
            .duration_since(std::time::UNIX_EPOCH)
            .expect("SystemTime before UNIX EPOCH");
        let ms_since_epoch = epoch_duration.as_millis() as i64;
        SqliteValue::Integer(ms_since_epoch)
    }
    fn parse(value: SqliteValue) -> Result<Self, DbSqliteError> {
        match value {
            SqliteValue::Integer(millis) => {
                let duration = Duration::from_millis(millis as u64);
                Ok(UNIX_EPOCH
                    .checked_add(duration)
                    .ok_or_else(|| DbSqliteError::SystemTimeError())?)
            }
            _ => Err(parse_typeerror("Integer", value)),
        }
    }
}
impl FromSqliteValue for Box<[u8]> {
    fn get_sqlite_value(self) -> SqliteValue {
        SqliteValue::Blob(self)
    }
    fn parse(value: SqliteValue) -> Result<Self, DbSqliteError> {
        match value {
            SqliteValue::Blob(b) => Ok(b),
            _ => Err(parse_typeerror("Blob", value)),
        }
    }
}
impl FromSqliteValue for Option<Box<[u8]>> {
    fn get_sqlite_value(self) -> SqliteValue {
        self.map_or_else(|| SqliteValue::Null, |v| SqliteValue::Blob(v))
    }
    fn parse(value: SqliteValue) -> Result<Self, DbSqliteError> {
        if value == SqliteValue::Null {
            return Ok(None);
        }
        return Box::<[u8]>::parse(value).map(|v| Some(v));
    }
}
impl FromSqliteValue for Vec<u8> {
    fn get_sqlite_value(self) -> SqliteValue {
        SqliteValue::Blob(self.into_boxed_slice())
    }
    fn parse(value: SqliteValue) -> Result<Self, DbSqliteError> {
        match value {
            SqliteValue::Blob(b) => Ok(b.to_vec()),
            _ => Err(parse_typeerror("Blob", value)),
        }
    }
}
impl FromSqliteValue for Option<Vec<u8>> {
    fn get_sqlite_value(self) -> SqliteValue {
        self.map_or_else(
            || SqliteValue::Null,
            |v| SqliteValue::Blob(v.into_boxed_slice()),
        )
    }
    fn parse(value: SqliteValue) -> Result<Self, DbSqliteError> {
        if value == SqliteValue::Null {
            return Ok(None);
        }
        return Vec::<u8>::parse(value).map(|v| Some(v));
    }
}

fn parse_typeerror(typename: &str, value: SqliteValue) -> DbSqliteError {
    DbSqliteError::ParseInvalidType {
        expected: typename.to_string(),
        actual: format!("{}", value.type_name()),
    }
}
