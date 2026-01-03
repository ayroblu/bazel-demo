use jotai::atom;
use jotai::select_atom;
use jotai::JotaiStore;
use jotai::PrimitiveAtom;
use jotai::SelectAtom;
use log_db::select_log;
use log_db::Log;
use std::sync::Arc;
use std::sync::LazyLock;
use std::time::SystemTime;

static COUNTER_ATOM: LazyLock<Arc<PrimitiveAtom<usize>>> = LazyLock::new(|| Arc::new(atom(0)));
pub static LOG_ATOM: LazyLock<Arc<SelectAtom<Vec<Log>>>> = LazyLock::new(|| {
    Arc::new(select_atom({
        move |get| {
            let counter_atom = COUNTER_ATOM.clone();
            let _ = get.get(counter_atom);
            select_log().ok().unwrap_or_else(|| vec![])
        }
    }))
});

pub fn invalidate_log_effect(
    store: Arc<JotaiStore>,
) -> Box<dyn Fn(SystemTime, &str, &str) + Send + Sync> {
    Box::new(move |_created_at: SystemTime, _key: &str, _text: &str| {
        invalidate_log(store.clone());
    })
}

pub fn invalidate_log(store: Arc<JotaiStore>) {
    let counter_atom = COUNTER_ATOM.clone();
    store.set_primitive(
        counter_atom.clone(),
        (*store.clone().get(&*counter_atom) + 1).into(),
    );
}
