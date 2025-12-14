// use rusqlite::Connection;
// // use thiserror::Error;

// #[derive(Debug)]
// struct Person {
//     id: i32,
//     name: String,
//     data: Option<Vec<u8>>,
// }

// fn open_db() -> Result<Connection, rusqlite::Error> {
//     let conn = Connection::open_in_memory()?;
//     return Ok(conn);
// }

// fn example_insert(conn: &Connection) -> Result<(), rusqlite::Error> {
//     conn.execute(
//         "CREATE TABLE person (
//             id    INTEGER PRIMARY KEY,
//             name  TEXT NOT NULL,
//             data  BLOB
//         )",
//         (), // empty list of parameters.
//     )?;
//     let me = Person {
//         id: 0,
//         name: "Steven".to_string(),
//         data: None,
//     };
//     conn.execute(
//         "INSERT INTO person (name, data) VALUES (?1, ?2)",
//         (&me.name, &me.data),
//     )?;
//     Ok(())
// }

// fn get_saved_persons(conn: &Connection) -> Result<Vec<String>, rusqlite::Error> {
//     let mut stmt = conn.prepare("SELECT id, name, data FROM person")?;
//     let person_iter = stmt.query_map([], |row| {
//         Ok(Person {
//             id: row.get(0)?,
//             name: row.get(1)?,
//             data: row.get(2)?,
//         })
//     })?;

//     let person_names = person_iter
//         .map(|result| result.map(|person| person.name))
//         .collect::<Result<Vec<String>, rusqlite::Error>>();
//     person_names
// }

// pub fn get_saved() -> Result<Vec<String>, rusqlite::Error> {
//     open_db().and_then(|conn| {
//         example_insert(&conn)?;
//         return get_saved_persons(&conn);
//     })
// }

use libsqlite3_sys::{
    sqlite3, sqlite3_open_v2, SQLITE_OK, SQLITE_OPEN_CREATE, SQLITE_OPEN_FULLMUTEX,
    SQLITE_OPEN_READWRITE,
};
use thiserror::Error;

fn open_db() -> Result<sqlite3, SwormError> {
    let mut db: *mut sqlite3 = std::ptr::null_mut();
    let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX;
    // let file_name = CString::new("my_db.sqlite").expect("CString::new failed");
    let file_name = std::ptr::null();
    let open_code = unsafe { sqlite3_open_v2(file_name, &mut db, flags, std::ptr::null()) };
    if open_code == SQLITE_OK {
        Ok(unsafe { *db })
    } else {
        Err(SwormError::OpenFailed(open_code))
    }
}
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
