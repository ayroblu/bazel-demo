use rusqlite::Connection;

#[derive(Debug)]
struct Person {
    id: i32,
    name: String,
    data: Option<Vec<u8>>,
}

fn open_db() -> Result<Connection, rusqlite::Error> {
    let conn = Connection::open_in_memory()?;
    return Ok(conn);
}

fn example_insert(conn: &Connection) -> Result<(), rusqlite::Error> {
    conn.execute(
        "CREATE TABLE person (
            id    INTEGER PRIMARY KEY,
            name  TEXT NOT NULL,
            data  BLOB
        )",
        (), // empty list of parameters.
    )?;
    let me = Person {
        id: 0,
        name: "Steven".to_string(),
        data: None,
    };
    conn.execute(
        "INSERT INTO person (name, data) VALUES (?1, ?2)",
        (&me.name, &me.data),
    )?;
    Ok(())
}

fn get_saved_persons(conn: &Connection) -> Result<Vec<String>, rusqlite::Error> {
    let mut stmt = conn.prepare("SELECT id, name, data FROM person")?;
    let person_iter = stmt.query_map([], |row| {
        Ok(Person {
            id: row.get(0)?,
            name: row.get(1)?,
            data: row.get(2)?,
        })
    })?;

    let person_names = person_iter
        .map(|result| result.map(|person| format!("{}: {}", person.id, person.name)))
        .collect::<Result<Vec<String>, rusqlite::Error>>();
    person_names
}

pub fn get_saved() -> Option<Vec<String>> {
    open_db()
        .and_then(|conn| {
            example_insert(&conn)?;
            return get_saved_persons(&conn);
        })
        .ok()
}
