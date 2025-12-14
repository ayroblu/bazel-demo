use std::ffi::{c_char, c_int, c_void, CStr, CString};
use std::ptr::{null, null_mut};
use std::slice;
use std::time::{Duration, UNIX_EPOCH};

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
    pub fn execute<T: FromQuery>(
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
        let rows = get_rows(stmt, &selectable)?;
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

fn get_rows<T: FromQuery>(
    stmt_ptr: *mut sqlite3_stmt,
    executable: &DbSelectable<T>,
) -> Result<Vec<T>, DbSqliteError> {
    let mut results: Vec<T> = Vec::new();

    let mut step_code = unsafe { sqlite3_step(stmt_ptr) };

    while step_code == SQLITE_ROW {
        let mut values: Vec<SqlValue> = Vec::new();
        let mut counter: c_int = 0;

        for column_type in &executable.columns {
            if unsafe { sqlite3_column_type(stmt_ptr, counter) } == SQLITE_NULL {
                values.push(SqlValue::Null);
            } else {
                match column_type {
                    ColumnType::Int => {
                        values.push(SqlValue::Int(unsafe {
                            sqlite3_column_int(stmt_ptr, counter)
                        }));
                    }
                    ColumnType::Text => {
                        let text_ptr = unsafe { sqlite3_column_text(stmt_ptr, counter) };
                        if !text_ptr.is_null() {
                            let c_str = unsafe { CStr::from_ptr(text_ptr as *const c_char) };
                            let rust_string = c_str.to_string_lossy().into_owned();
                            values.push(SqlValue::Text(rust_string));
                        } else {
                            values.push(SqlValue::Null);
                        }
                    }
                    ColumnType::Bool => {
                        let int_val = unsafe { sqlite3_column_int(stmt_ptr, counter) };
                        values.push(SqlValue::Bool(int_val > 0));
                    }
                    ColumnType::Long => {
                        values.push(SqlValue::Long(unsafe {
                            sqlite3_column_int64(stmt_ptr, counter)
                        }));
                    }
                    ColumnType::Date => {
                        let millis = unsafe { sqlite3_column_int64(stmt_ptr, counter) };
                        let duration = Duration::from_millis(millis as u64);
                        let date = UNIX_EPOCH
                            .checked_add(duration)
                            .ok_or_else(|| DbSqliteError::SystemTimeError())?;
                        values.push(SqlValue::Date(date));
                    }
                    ColumnType::Blob => {
                        let pointer = unsafe { sqlite3_column_blob(stmt_ptr, counter) };
                        let size = unsafe { sqlite3_column_bytes(stmt_ptr, counter) } as usize;
                        if !pointer.is_null() && size > 0 {
                            let slice =
                                unsafe { slice::from_raw_parts(pointer as *const u8, size) };
                            values.push(SqlValue::Blob(slice.to_vec()));
                        } else {
                            values.push(SqlValue::Blob(Vec::new()));
                        }
                    }
                    ColumnType::Real => {
                        values.push(SqlValue::Double(unsafe {
                            sqlite3_column_double(stmt_ptr, counter)
                        }));
                    }
                }
            }

            counter += 1;
        }

        let row_data = T::parse(values)?;
        results.push(row_data);
        step_code = unsafe { sqlite3_step(stmt_ptr) };
    }

    if step_code == SQLITE_DONE {
        Ok(results)
    } else {
        let db_handle = unsafe { sqlite3_db_handle(stmt_ptr) };
        let err_ptr = unsafe { sqlite3_errmsg(db_handle) };
        let error_message = if !err_ptr.is_null() {
            unsafe { CStr::from_ptr(err_ptr).to_string_lossy().into_owned() }
        } else {
            "Unknown error".to_string()
        };

        Err(DbSqliteError::StepFailed(error_message, step_code))
    }
}
fn inject_values(stmt: &mut sqlite3_stmt, values: &Vec<SqlValue>) {
    let mut counter: c_int = 1;
    for value in values {
        match value {
            SqlValue::Int(int_value) => {
                unsafe { sqlite3_bind_int(stmt, counter, *int_value) };
            }
            SqlValue::Text(text_value) => {
                // Rust requires CString conversion and the SQLITE_TRANSIENT destructor for safety.
                let c_string =
                    CString::new(text_value.clone()).expect("Invalid UTF-8 in SQL string");
                unsafe {
                    sqlite3_bind_text(stmt, counter, c_string.as_ptr(), -1, SQLITE_TRANSIENT())
                };
            }
            SqlValue::Bool(bool_value) => {
                let int_val = if *bool_value { 1 } else { 0 };
                unsafe { sqlite3_bind_int(stmt, counter, int_val) };
            }
            SqlValue::Long(long_value) => {
                unsafe { sqlite3_bind_int64(stmt, counter, *long_value) };
            }
            SqlValue::Double(double_value) => {
                unsafe { sqlite3_bind_double(stmt, counter, *double_value) };
            }
            SqlValue::Date(date_value) => {
                let epoch_duration = date_value
                    .duration_since(std::time::UNIX_EPOCH)
                    .expect("SystemTime before UNIX EPOCH");
                let ms_since_epoch = epoch_duration.as_millis() as i64;
                unsafe { sqlite3_bind_int64(stmt, counter, ms_since_epoch) };
            }
            SqlValue::Blob(blob_value) => {
                unsafe {
                    sqlite3_bind_blob(
                        stmt,
                        counter,
                        blob_value.as_ptr() as *const c_void,
                        blob_value.len() as c_int,
                        SQLITE_TRANSIENT(),
                    )
                };
            }
            SqlValue::Null => {
                unsafe { sqlite3_bind_null(stmt, counter) };
            }
        }

        counter += 1;
    }
}

#[cfg(test)]
mod tests {
    use crate::db::SqliteDb;
    use crate::types::{
        ColumnType, DbExecutable, DbSelectable, DbSqliteError, FromQuery, SqlValue,
    };
    type TestResult = Result<(), Box<dyn std::error::Error>>;

    #[test]
    fn test_simple_insert_read() -> TestResult {
        let db = SqliteDb::open(":memory:")?;

        let create_table = DbExecutable::new(
            "CREATE TABLE person (
                id    INTEGER PRIMARY KEY,
                name  TEXT NOT NULL,
                data  BLOB
            )",
            (),
        );
        db.execute_only(create_table)?;

        let insert = DbExecutable {
            statement: "INSERT INTO person (name, data) VALUES (?1, ?2)".to_string(),
            values: vec![
                SqlValue::Text("Steven".to_string()),
                SqlValue::Blob(vec![23, 192]),
            ],
        };
        db.execute_only(insert)?;

        let select = DbSelectable::<Person>::new(
            "SELECT id, name, data FROM person",
            (),
            vec![ColumnType::Int, ColumnType::Text, ColumnType::Blob],
        );
        let result = db.execute(select)?;
        assert_eq!(result.len(), 1);
        assert_eq!(result[0].id, 1);
        assert_eq!(result[0].name, "Steven");
        assert_eq!(result[0].data, Some(vec![23, 192]));

        Ok(())
    }

    #[derive(Debug)]
    struct Person {
        id: i32,
        name: String,
        data: Option<Vec<u8>>,
    }
    impl FromQuery for Person {
        fn parse(values: Vec<SqlValue>) -> Result<Self, DbSqliteError> {
            if values.len() != 3 {
                return Err(DbSqliteError::ParseInvalidLength(values.len(), 3));
            }

            let mut iter = values.into_iter();

            Ok(Person {
                id: iter.next().unwrap().get_nonnull()?,
                name: iter.next().unwrap().get_nonnull()?,
                data: iter.next().unwrap().get()?,
            })
        }
    }
}
