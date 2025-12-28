use rusqlite::{Connection, Result};

pub struct M<'a> {
    pub up: &'a str,
    pub down: Option<&'a str>,
}

impl<'a> M<'a> {
    pub const fn up(sql: &'a str) -> Self {
        Self {
            up: sql,
            down: None,
        }
    }

    pub const fn down(self, sql: &'a str) -> Self {
        Self {
            up: self.up,
            down: Some(sql),
        }
    }
}

pub struct Migrations<'a> {
    ms: &'a [M<'a>],
}

impl<'a> Migrations<'a> {
    pub const fn from_slice(ms: &'a [M<'a>]) -> Self {
        Self { ms }
    }

    pub fn to_latest(&self, conn: &mut Connection) -> Result<()> {
        let current_version =
            conn.query_row("PRAGMA user_version", [], |row| row.get::<_, usize>(0))?;

        let target_version = self.ms.len();

        if current_version < target_version {
            for (i, m) in self.ms.iter().enumerate().skip(current_version) {
                let tx = conn.transaction()?;
                tx.execute_batch(m.up)?;
                tx.pragma_update(None, "user_version", i + 1)?;
                tx.commit()?;
            }
        }
        Ok(())
    }

    pub fn validate(&self) -> Result<()> {
        let mut conn = Connection::open_in_memory()?;
        self.to_latest(&mut conn)?;
        self.to_version(&mut conn, 0)?;
        Ok(())
    }

    pub fn to_version(&self, conn: &mut Connection, target_version: usize) -> Result<()> {
        let current_version: usize = conn.query_row("PRAGMA user_version", [], |r| r.get(0))?;

        if current_version < target_version {
            for i in current_version..target_version {
                let m = &self.ms[i];
                let tx = conn.transaction()?;
                tx.execute_batch(m.up)?;
                tx.pragma_update(None, "user_version", i + 1)?;
                tx.commit()?;
            }
        } else if current_version > target_version {
            for i in (target_version..current_version).rev() {
                let m = &self.ms[i];
                if let Some(down_sql) = m.down {
                    let tx = conn.transaction()?;
                    tx.execute_batch(down_sql)?;
                    tx.pragma_update(None, "user_version", i)?;
                    tx.commit()?;
                } else {
                    return Err(rusqlite::Error::ExecuteReturnedResults);
                }
            }
        }
        Ok(())
    }
}
