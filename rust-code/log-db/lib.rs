use rusqlite::Connection;
use rusqlite_migrations::{Migrations, M};
use std::{
    rc::Rc,
    sync::OnceLock,
    time::{Duration, SystemTime, UNIX_EPOCH},
};

const MIGRATIONS_SLICE: &[M<'_>] = &[M::up(
    "
    CREATE TABLE IF NOT EXISTS log(
      id INTEGER PRIMARY KEY,
      key TEXT NOT NULL,
      text TEXT NOT NULL,
      created_at INTEGER DEFAULT (unixepoch('subsec') * 1000)
    )
    ",
)
.down("DROP TABLE IF EXISTS log")];
const MIGRATIONS: Migrations<'_> = Migrations::from_slice(MIGRATIONS_SLICE);

pub fn insert_log(
    key: &str,
    text: &str,
    created_at: SystemTime,
) -> Result<Option<i64>, rusqlite::Error> {
    let Some(conn) = get_conn() else {
        return Ok(None);
    };
    let id: i64 = conn
        .prepare("INSERT INTO log (key, text, created_at) VALUES (?, ?, ?) RETURNING id;")?
        .query_row((key, text, time_to_int(created_at)), |row| row.get(0))?;
    Ok(Some(id))
}

pub fn select_log() -> Result<Vec<Log>, rusqlite::Error> {
    let Some(conn) = get_conn() else {
        return Ok(vec![]);
    };
    let mut stmt =
        conn.prepare("SELECT id, text, created_at FROM log ORDER BY created_at DESC;")?;
    stmt.query_map([], |row| {
        let created_at: i64 = row.get(2)?;
        Ok(Log {
            id: row.get(0)?,
            text: row.get(1)?,
            created_at: int_to_time(created_at),
        })
    })?
    .collect()
}
#[derive(Debug, PartialEq, Clone)]
pub struct Log {
    pub id: i32,
    pub text: String,
    pub created_at: SystemTime,
}

pub fn delete_old_logs() -> Result<usize, rusqlite::Error> {
    let Some(conn) = get_conn() else { return Ok(0) };
    conn.execute(
        "DELETE FROM log WHERE created_at < strftime('%s', 'now', '-7 days') * 1000;",
        (),
    )
}

pub fn delete_log_by_id(id: i64) -> Result<usize, rusqlite::Error> {
    let Some(conn) = get_conn() else { return Ok(0) };
    conn.execute("DELETE FROM log WHERE id = ?;", (id,))
}

pub fn delete_all_logs() -> Result<usize, rusqlite::Error> {
    let Some(conn) = get_conn() else { return Ok(0) };
    conn.execute("DELETE FROM log;", ())
}

#[cfg(not(test))]
fn get_conn() -> Option<Rc<Connection>> {
    let Some(path) = DB_PATH.get() else {
        return None;
    };
    let conn = DB_CONN.with(|v| {
        v.get_or_init(|| {
            let mut conn = Connection::open(path).unwrap();
            MIGRATIONS.to_latest(&mut conn).unwrap();
            return Rc::new(conn);
        })
        .clone()
    });
    return Some(conn);
}
#[cfg(test)]
fn get_conn() -> Option<Rc<Connection>> {
    let conn = DB_CONN.with(|v| {
        v.get_or_init(|| {
            let mut conn = Connection::open_in_memory().unwrap();
            MIGRATIONS.to_latest(&mut conn).unwrap();
            return Rc::new(conn);
        })
        .clone()
    });
    return Some(conn);
}

pub fn set_db_path(path: &str) {
    DB_PATH.get_or_init(|| path.to_string());
}

static DB_PATH: OnceLock<String> = OnceLock::new();
thread_local! {
    static DB_CONN: OnceLock<Rc<Connection>> = OnceLock::new();
}

fn time_to_int(system_time: SystemTime) -> i64 {
    let epoch_duration = system_time
        .duration_since(std::time::UNIX_EPOCH)
        .expect("SystemTime before UNIX EPOCH");
    let ms_since_epoch = epoch_duration.as_millis() as i64;
    return ms_since_epoch;
}
fn int_to_time(millis: i64) -> SystemTime {
    let duration = Duration::from_millis(millis as u64);
    UNIX_EPOCH
        .checked_add(duration)
        .unwrap_or_else(|| UNIX_EPOCH)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn migrations_test() {
        assert!(MIGRATIONS.validate().is_ok());
    }
}
