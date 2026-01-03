use jotai::atom;
use jotai::select_atom;
use jotai::JotaiStore;
use jotai::PrimitiveAtom;
use jotai::SelectAtom;
use log_db::select_log;
use std::sync::Arc;
use std::time::SystemTime;

uniffi::setup_scaffolding!();

#[derive(uniffi::Object)]
struct Store(Arc<JotaiStore>);
unsafe impl Send for Store {}
unsafe impl Sync for Store {}
#[uniffi::export]
fn create_store() -> Store {
    return Store(JotaiStore::new());
}
#[derive(uniffi::Object)]
struct LogAtom {
    store: Arc<Store>,
}
#[uniffi::export]
impl LogAtom {
    #[uniffi::constructor]
    fn new(store: Arc<Store>) -> Arc<Self> {
        Arc::new(Self { store })
    }
    fn get(&self) -> Vec<Log> {
        let log_atom = LOG_ATOM.with(|a| a.clone());
        self.store.0.clone().get(&*log_atom).to_vec()
    }
    fn sub(&self, func: Box<dyn ClosureCallback>) -> Cleanup {
        let log_atom = LOG_ATOM.with(|a| a.clone());
        let store = self.store.0.clone();
        let dispose = store.sub(log_atom, move |_| func.notif());
        return Cleanup::new(dispose);
    }
}
#[uniffi::export]
pub fn get_logs() -> Vec<Log> {
    select_log()
        .ok()
        .map(|v| v.into_iter().map(|l| Log::from(l)).collect())
        .unwrap_or_else(|| vec![])
}
#[uniffi::export]
pub fn get_logs_jotai() -> Vec<Log> {
    let store = DEFAULT_STORE.with(|arc| arc.clone());
    let log_atom = LOG_ATOM.with(|a| a.clone());
    return store.get(&*log_atom).to_vec();
}
#[uniffi::export]
pub fn delete_all_logs() {
    let _ = log_db::delete_all_logs();
    invalidate_logs();
}
fn invalidate_logs() {
    let store = DEFAULT_STORE.with(|arc| arc.clone());
    let counter_atom = COUNTER_ATOM.with(|a| a.clone());
    store.set_primitive(
        counter_atom.clone(),
        (*store.clone().get(&*counter_atom) + 1).into(),
    );
}
#[uniffi::export]
pub fn init_log_db(path: &str) {
    log_db::set_db_path(path);
    logger::log!("init_log_db");
}
#[uniffi::export]
pub fn log(message: &str) {
    logger::log::log_info(message);
    invalidate_logs();
}
#[uniffi::export]
pub fn elog(message: &str) {
    logger::log::log_error(message);
    invalidate_logs();
}
// logger (interface)
// log stdout / logcat
// db log
// atom invalidation

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
#[uniffi::export]
pub fn sub_logs(func: Box<dyn ClosureCallback>) -> Arc<Cleanup> {
    let store = DEFAULT_STORE.with(|arc| arc.clone());
    let log_atom = LOG_ATOM.with(|a| a.clone());
    let dispose = store.sub(log_atom, move |_| func.notif());
    return Arc::new(Cleanup::new(dispose));
}
// store wraps jotaiStore
// You must construct the wrapper atom in swift land (just to get the store)
// atom { store }
// atom.get() // known e.g. String
// atom.sub(() => {}) // just calls store.sub(atom, () => {})

#[uniffi::export(callback_interface)]
pub trait ClosureCallback {
    // notify is a reserved word in kotlin 🤦
    fn notif(&self);
}
use tokio::sync::mpsc;
use tokio::task::spawn_local;

#[derive(uniffi::Object)]
pub struct Cleanup {
    tx: mpsc::Sender<()>,
}
impl Cleanup {
    fn new(callback: impl FnOnce() + 'static) -> Self {
        let (tx, mut rx) = mpsc::channel::<()>(1);

        spawn_local(async move {
            if rx.recv().await.is_some() {
                callback();
            }
        });

        Self { tx }
    }
}
#[uniffi::export]
impl Cleanup {
    fn dispose(&self) {
        let _ = self.tx.try_send(());
    }
}

thread_local! {
    static DEFAULT_STORE: Arc<JotaiStore> = JotaiStore::new();
    static COUNTER_ATOM: Arc<PrimitiveAtom<usize>> = Arc::new(atom(0));
    static LOG_ATOM: Arc<SelectAtom<Vec<Log>>> = Arc::new(select_atom({
        move |get| {
            let counter_atom = COUNTER_ATOM.with(|arc| arc.clone());
            let _ = get.get(counter_atom);
            select_log().ok().map(|v| v.into_iter().map(|l| Log::from(l)).collect()).unwrap_or_else(|| vec![])
        }
    }));
}
