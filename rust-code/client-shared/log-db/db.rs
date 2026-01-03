use rusqlite::Connection;
use rusqlite_migrations::{Migrations, M};
use std::{rc::Rc, sync::OnceLock, time::SystemTime};

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

#[derive(Debug, PartialEq, Clone)]
pub struct Log {
    pub id: i32,
    pub text: String,
    pub created_at: SystemTime,
}

#[cfg(not(test))]
pub(crate) fn get_conn() -> Option<Rc<Connection>> {
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
pub(crate) fn get_conn() -> Option<Rc<Connection>> {
    let conn = DB_CONN.with(|v| {
        v.get_or_init(|| {
            // Test just opens in memory db
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn migrations_test() {
        assert!(MIGRATIONS.validate().is_ok());
    }
}
