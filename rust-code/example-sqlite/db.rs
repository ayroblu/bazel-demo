use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::ptr::{null, null_mut};

use libsqlite3_sys::*;

use crate::types::*;

pub struct SqliteDb {
    db: *mut sqlite3,
}
impl SqliteDb {
    pub fn open(filename: &str) -> Result<Self, DbSqliteError> {
        let mut db: *mut sqlite3 = null_mut();
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX;
        let file_name = CString::new(filename).expect("CString::new failed");
        if cfg!(debug_assertions) {
            println!("sqlite open at: {}", filename)
        }
        let open_code = unsafe { sqlite3_open_v2(file_name.as_ptr(), &mut db, flags, null()) };
        if open_code == SQLITE_OK {
            let result_db = SqliteDb { db };
            Ok(result_db)
        } else {
            Err(DbSqliteError::OpenFailed(open_code))
        }
    }

    pub fn execute<T: FromSqlite>(
        &self,
        selectable: DbSelectable<T>,
    ) -> Result<Vec<T>, DbSqliteError> {
        if cfg!(debug_assertions) {
            println!("execute {}", selectable.executable.statement)
        }
        let mut stmt: *mut sqlite3_stmt = null_mut();
        let statement =
            CString::new(selectable.executable.statement.clone()).expect("CString::new failed");
        let statement_ptr = statement.as_ptr();
        let prepare_code =
            unsafe { sqlite3_prepare_v2(self.db, statement_ptr, -1, &mut stmt, null_mut()) };
        if prepare_code != SQLITE_OK {
            return Err(DbSqliteError::PrepareFailed(
                selectable.executable.statement,
                prepare_code,
            ));
        }
        inject_values(unsafe { &mut *stmt }, &selectable.executable.values);
        let rows = get_rows(stmt)?;
        unsafe { sqlite3_finalize(stmt) };
        return Ok(rows);
    }

    pub fn execute_only(&self, executable: DbExecutable) -> Result<(), DbSqliteError> {
        if cfg!(debug_assertions) {
            println!("execute_only {}", executable.statement)
        }

        let mut stmt: *mut sqlite3_stmt = null_mut();
        let statement = CString::new(executable.statement.clone()).expect("CString::new failed");
        let statement_ptr = statement.as_ptr();
        let prepare_code =
            unsafe { sqlite3_prepare_v2(self.db, statement_ptr, -1, &mut stmt, null_mut()) };
        if prepare_code != SQLITE_OK {
            return Err(DbSqliteError::PrepareFailed(
                executable.statement,
                prepare_code,
            ));
        }
        inject_values(unsafe { &mut *stmt }, &executable.values);
        let mut step_code = unsafe { sqlite3_step(stmt) };
        while step_code == SQLITE_ROW {
            step_code = unsafe { sqlite3_step(stmt) };
        }
        if step_code != SQLITE_DONE {
            return Err(DbSqliteError::StepFailed(executable.statement, step_code));
        }
        unsafe { sqlite3_finalize(stmt) };
        return Ok(());
    }
}

struct SqliteRowIterator {
    stmt_ptr: *mut sqlite3_stmt,
}
impl Iterator for SqliteRowIterator {
    type Item = Result<Row, DbSqliteError>;

    fn next(&mut self) -> Option<Self::Item> {
        let step_code = unsafe { sqlite3_step(self.stmt_ptr) };

        match step_code {
            SQLITE_ROW => Some(Ok(Row::new(self.stmt_ptr))),
            SQLITE_DONE => None,
            _ => {
                let db_handle = unsafe { sqlite3_db_handle(self.stmt_ptr) };
                let err_ptr = unsafe { sqlite3_errmsg(db_handle) };

                let error_message = if !err_ptr.is_null() {
                    unsafe { CStr::from_ptr(err_ptr).to_string_lossy().into_owned() }
                } else {
                    "Unknown SQLite error".to_string()
                };

                Some(Err(DbSqliteError::StepFailed(error_message, step_code)))
            }
        }
    }
}
fn get_rows<T: FromSqlite>(stmt_ptr: *mut sqlite3_stmt) -> Result<Vec<T>, DbSqliteError> {
    let iter = SqliteRowIterator { stmt_ptr };
    return iter
        .map(|row| row.and_then(|r| T::parse(r)))
        .collect::<Result<Vec<T>, DbSqliteError>>();
}
fn inject_values(stmt: &mut sqlite3_stmt, values: &Vec<SqliteValue>) {
    let mut counter: c_int = 1;
    for value in values {
        match value {
            SqliteValue::Integer(int_value) => {
                unsafe { sqlite3_bind_int64(stmt, counter, *int_value) };
            }
            SqliteValue::Text(text_value) => {
                let (c_str, len, destructor) = str_for_sqlite(text_value.as_bytes());
                unsafe {
                    sqlite3_bind_text64(stmt, counter, c_str, len, destructor, SQLITE_UTF8 as _)
                };
            }
            SqliteValue::Real(double_value) => {
                unsafe { sqlite3_bind_double(stmt, counter, *double_value) };
            }
            SqliteValue::Blob(blob_value) => {
                let length = blob_value.len();
                if length == 0 {
                    unsafe { sqlite3_bind_zeroblob(stmt, counter, 0) };
                } else {
                    unsafe {
                        sqlite3_bind_blob64(
                            stmt,
                            counter,
                            blob_value.as_ptr().cast::<c_void>(),
                            length as sqlite3_uint64,
                            SQLITE_TRANSIENT(),
                        )
                    };
                }
            }
            SqliteValue::Null => {
                unsafe { sqlite3_bind_null(stmt, counter) };
            }
        }

        counter += 1;
    }
}

/// Returns `(string ptr, len as c_int, SQLITE_STATIC | SQLITE_TRANSIENT)`
/// normally.
/// The `sqlite3_destructor_type` item is always `SQLITE_TRANSIENT` unless
/// the string was empty (in which case it's `SQLITE_STATIC`, and the ptr is
/// static).
fn str_for_sqlite(s: &[u8]) -> (*const c_char, sqlite3_uint64, sqlite3_destructor_type) {
    let len = s.len();
    let (ptr, dtor_info) = if len != 0 {
        (s.as_ptr().cast::<c_char>(), SQLITE_TRANSIENT())
    } else {
        // Return a pointer guaranteed to live forever
        ("".as_ptr().cast::<c_char>(), SQLITE_STATIC())
    };
    (ptr, len as sqlite3_uint64, dtor_info)
}

#[cfg(test)]
mod tests {
    use std::time::{Duration, SystemTime};

    use crate::db::SqliteDb;
    use crate::types::{DbExecutable, DbSelectable, DbSqliteError};
    use crate::{FromSqlite, FromSqliteValue, Row};
    type TestResult = Result<(), Box<dyn std::error::Error>>;

    #[test]
    fn test_simple_insert_read() -> TestResult {
        let (db,) = setup_test()?;

        let select =
            DbSelectable::<Person>::new("SELECT id, name, data, created_at FROM person", ());
        let result = db.execute(select)?;
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].id, 1);
        assert_eq!(result[0].name, "Steven");
        assert_eq!(result[0].data, Some(vec![23, 192].into_boxed_slice()));
        let difference = result[0]
            .created_at
            .duration_since(SystemTime::now())
            .unwrap_or_else(|e| e.duration());
        assert!(
            difference < Duration::from_secs(1),
            "The difference between created_at and now was too large: {:?}",
            difference
        );

        Ok(())
    }

    #[test]
    fn test_wrong_type_error() -> TestResult {
        let (db,) = setup_test()?;

        // switch around name and id
        let select = DbSelectable::<Person>::new("SELECT name, id, data FROM person", ());
        let result = db.execute(select);
        assert_eq!(
            result.unwrap_err(),
            DbSqliteError::ParseInvalidType {
                expected: "Integer".to_string(),
                actual: "Text".to_string(),
            }
        );

        Ok(())
    }

    #[test]
    fn test_short_length_error() -> TestResult {
        let (db,) = setup_test()?;

        // removed data
        let select = DbSelectable::<Person>::new("SELECT id, name FROM person", ());
        let result = db.execute(select);
        assert_eq!(result.unwrap_err(), DbSqliteError::ParseInvalidLength(2, 2),);

        Ok(())
    }

    #[test]
    fn test_invalid_sql_statement() -> TestResult {
        let (db,) = setup_test()?;

        let select = DbSelectable::<Person>::new("garbage here", ());
        let result = db.execute(select);
        assert_eq!(
            result.unwrap_err(),
            DbSqliteError::PrepareFailed("garbage here".to_string(), 1),
        );

        Ok(())
    }

    #[derive(Debug)]
    struct Person {
        id: i32,
        name: String,
        data: Option<Box<[u8]>>,
        created_at: SystemTime,
    }
    impl FromSqlite for Person {
        fn parse(row: Row) -> Result<Self, DbSqliteError> {
            Ok(Person {
                id: row.get(0)?,
                name: row.get(1)?,
                data: row.get(2)?,
                created_at: row.get(3)?,
            })
        }
    }

    fn setup_test() -> Result<(SqliteDb,), DbSqliteError> {
        let db = SqliteDb::open(":memory:")?;

        let create_table = DbExecutable::new(
            "CREATE TABLE person (
                id    INTEGER PRIMARY KEY,
                name  TEXT NOT NULL,
                data  BLOB,
                created_at INTEGER DEFAULT (unixepoch('subsec') * 1000)
            )",
            (),
        );
        db.execute_only(create_table)?;

        let insert = DbExecutable::new(
            "INSERT INTO person (name, data) VALUES (?1, ?2)",
            vec![
                "Steven".to_string().get_sqlite_value(),
                vec![23, 192].get_sqlite_value(),
            ],
        );
        db.execute_only(insert)?;
        return Ok((db,));
    }
}
