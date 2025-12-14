use std::ffi::CString;
use std::ptr::{null, null_mut};

use libsqlite3_sys::{
    sqlite3, sqlite3_finalize, sqlite3_open_v2, sqlite3_prepare_v2, sqlite3_step, sqlite3_stmt,
    SQLITE_DONE, SQLITE_ROW,
};
use libsqlite3_sys::{SQLITE_OK, SQLITE_OPEN_CREATE, SQLITE_OPEN_FULLMUTEX, SQLITE_OPEN_READWRITE};
use thiserror::Error;

struct DbExecutable {
    statement: String,
}

fn open_db() -> Result<sqlite3, SwormError> {
    let mut db: *mut sqlite3 = null_mut();
    let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX;
    // let file_name = CString::new("my_db.sqlite").expect("CString::new failed");
    let file_name = null();
    let open_code = unsafe { sqlite3_open_v2(file_name, &mut db, flags, null()) };
    if open_code == SQLITE_OK {
        Ok(unsafe { *db })
    } else {
        Err(SwormError::OpenFailed(open_code))
    }
}
fn execute_only(executable: DbExecutable) -> Result<(), SwormError> {
    // print("executeOnly \(executable.statement)")
    // temp
    let mut db = open_db().unwrap();

    let mut stmt: *mut sqlite3_stmt = null_mut();
    let statement = CString::new(executable.statement.clone()).expect("CString::new failed");
    let statement_ptr = statement.as_ptr();
    let prepare_code =
        unsafe { sqlite3_prepare_v2(&mut db, statement_ptr, -1, &mut stmt, null_mut()) };
    if prepare_code != SQLITE_OK {
        return Err(SwormError::PrepareFailed(
            executable.statement,
            prepare_code,
        ));
    }
    // injectValues(statementPointer: statementPointer, values: executable.values)
    let mut step_code = unsafe { sqlite3_step(stmt) };
    while step_code == SQLITE_ROW {
        step_code = unsafe { sqlite3_step(stmt) };
    }
    if step_code != SQLITE_DONE {
        return Err(SwormError::StepFailed(executable.statement, step_code));
    }
    unsafe { sqlite3_finalize(stmt) };
    return Ok(());
}
fn inject_values<P>(stmt: &sqlite3_stmt, values: P) {}
// private func injectValues(statementPointer: OpaquePointer?, values: [Any?]) {
//   var counter: Int32 = 1
//   for value in values {
//     defer { counter += 1 }
//     if let intValue = value as? Int32 {
//       sqlite3_bind_int(statementPointer, counter, intValue)
//     } else if let textValue = value as? String {
//       sqlite3_bind_text(statementPointer, counter, (textValue as NSString).utf8String, -1, nil)
//     } else if let boolValue = value as? Bool {
//       sqlite3_bind_int(statementPointer, counter, boolValue ? 1 : 0)
//     } else if let longValue = value as? Int64 {
//       sqlite3_bind_int64(statementPointer, counter, longValue)
//     } else if let doubleValue = value as? Double {
//       sqlite3_bind_double(statementPointer, counter, doubleValue)
//     } else if let dateValue = value as? Date {
//       sqlite3_bind_int64(
//         statementPointer, counter, Int64(dateValue.timeIntervalSince1970 * 1000))
//     } else if let blobValue = value as? Data {
//       _ = blobValue.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
//         sqlite3_bind_blob(
//           statementPointer, counter, bytes.baseAddress, Int32(blobValue.count), SQLITE_TRANSIENT)
//       }
//     }
//   }
// }
pub fn get_saved() -> Option<Vec<String>> {
    Some(vec!["first".to_string()])
}

#[derive(Error, Debug)]
pub enum SwormError {
    /// https://www.sqlite.org/rescode.html
    #[error("Open failed with code: {0}")]
    OpenFailed(i32),
    #[error("Prepared failed for statement: {0}, with code: {1}")]
    PrepareFailed(String, i32),
    #[error("Step failed for statement: {0}, with code: {1}")]
    StepFailed(String, i32),
    // #[error("Step failed for statement: {statement}, with code: {code}")]
    // StepFailed {
    //     statement: String,
    //     code: isize,
    // },
    #[error("Parse insufficient data")]
    ParseInsufficientData,
    #[error("Parse invalid type: {0}")]
    ParseInvalidType(String),
}
