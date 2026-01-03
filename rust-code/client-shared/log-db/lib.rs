mod db;

pub use crate::db::*;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

type InsertResult = Result<Option<i64>, rusqlite::Error>;
pub fn insert_log(key: &str, text: &str, created_at: SystemTime) -> InsertResult {
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

pub fn log_effect() -> Box<dyn Fn(SystemTime, &str, &str) + Send + Sync> {
    Box::new(|created_at: SystemTime, key: &str, text: &str| {
        _ = insert_log(key, text, created_at);
    })
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
    fn test_insert_log() -> Result<(), rusqlite::Error> {
        let now = int_to_time(time_to_int(SystemTime::now()));
        _ = insert_log("I", "test", now);
        let logs = select_log()?;
        assert_eq!(
            logs,
            vec![Log {
                id: 1,
                text: "test".into(),
                created_at: now,
            }]
        );
        Ok(())
    }
}
