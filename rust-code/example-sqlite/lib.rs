pub mod conversions;
pub mod db;
pub mod types;

use std::{
    fmt::{self, Display, Formatter},
    time::SystemTime,
};

pub use db::*;
pub use types::*;

pub fn get_saved() -> Option<Vec<String>> {
    example().ok()
}
pub fn example() -> Result<Vec<String>, DbSqliteError> {
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

    let select = DbSelectable::<Person>::new("SELECT id, name, data, created_at FROM person", ());
    let result = db.execute(select)?;

    let person_names = result
        .into_iter()
        .map(|person| format!("{}", person))
        .collect::<Vec<String>>();

    Ok(person_names)
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
impl Display for Person {
    fn fmt(&self, f: &mut Formatter) -> fmt::Result {
        let data_summary = match self.data {
            Some(ref d) => format!("Data(len: {})", d.len()),
            None => String::from("No Data"),
        };

        let created_at_ms = self
            .created_at
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0);

        write!(
            f,
            "Person {{ ID: {}, Name: \"{}\", Data: {}, CreatedAt(ms): {} }}",
            self.id, self.name, data_summary, created_at_ms
        )
    }
}
