use jotai::JotaiStore;
use log_atoms::LOG_ATOM;
use std::sync::Arc;
use std::time::SystemTime;

uniffi::setup_scaffolding!();

#[derive(uniffi::Object)]
struct RustJotaiStore(Arc<JotaiStore>);

#[uniffi::export]
fn create_store() -> RustJotaiStore {
    return RustJotaiStore(JotaiStore::new());
}
#[derive(uniffi::Object)]
struct LogAtom {
    store: Arc<RustJotaiStore>,
}
#[uniffi::export]
impl LogAtom {
    #[uniffi::constructor]
    fn new(store: Arc<RustJotaiStore>) -> Arc<Self> {
        Arc::new(Self { store })
    }
    fn get(&self) -> Vec<Log> {
        let log_atom = LOG_ATOM.clone();
        self.store
            .0
            .clone()
            .get(&*log_atom)
            .to_vec()
            .into_iter()
            .map(Log::from)
            .collect()
    }
    fn sub(&self, func: Box<dyn ClosureCallback>) -> Cleanup {
        let log_atom = LOG_ATOM.clone();
        let store = self.store.0.clone();
        let dispose = store.sub(log_atom, move |_| func.notif());
        return Cleanup::new(dispose);
    }
}

#[derive(uniffi::Object)]
struct DeleteLogsAtom {
    store: Arc<RustJotaiStore>,
}
#[uniffi::export]
impl DeleteLogsAtom {
    #[uniffi::constructor]
    fn new(store: Arc<RustJotaiStore>) -> Arc<Self> {
        Arc::new(Self { store })
    }
    fn set(&self) {
        let _ = log_db::delete_all_logs();
        log_atoms::invalidate_log(self.store.0.clone());
    }
}

#[derive(uniffi::Object)]
struct DeleteOldLogsAtom {
    store: Arc<RustJotaiStore>,
}
#[uniffi::export]
impl DeleteOldLogsAtom {
    #[uniffi::constructor]
    fn new(store: Arc<RustJotaiStore>) -> Arc<Self> {
        Arc::new(Self { store })
    }
    fn set(&self) {
        let _ = log_db::delete_old_logs();
        log_atoms::invalidate_log(self.store.0.clone());
    }
}

#[uniffi::export]
fn init_effects(store: Arc<RustJotaiStore>) {
    logger::init_effects(vec![
        Box::new(log_db::log_effect()),
        Box::new(log_atoms::invalidate_log_effect(store.0.clone())),
    ]);
}
#[uniffi::export]
pub fn init_log_db(path: &str) {
    log_db::set_db_path(path);
    logger::log!("init_log_db");
}
#[uniffi::export]
pub fn log(message: &str) {
    logger::log_info(message);
}
#[uniffi::export]
pub fn elog(message: &str) {
    logger::log_error(message);
}

#[derive(uniffi::Record, Debug, PartialEq, Clone)]
pub struct Log {
    pub id: i32,
    pub text: String,
    pub created_at: SystemTime,
}
impl From<log_db::Log> for Log {
    fn from(log: log_db::Log) -> Self {
        Self {
            id: log.id,
            text: log.text,
            created_at: log.created_at,
        }
    }
}

#[uniffi::export(callback_interface)]
pub trait ClosureCallback: Send + Sync {
    // notify is a reserved word in kotlin 🤦
    fn notif(&self);
}

#[derive(uniffi::Object)]
pub struct Cleanup {
    callback: Box<dyn Fn() + 'static + Send + Sync>,
}
impl Cleanup {
    fn new(callback: impl Fn() + 'static + Send + Sync) -> Self {
        Self {
            callback: Box::new(callback),
        }
    }
}
#[uniffi::export]
impl Cleanup {
    fn dispose(&self) {
        (self.callback)();
    }
}
