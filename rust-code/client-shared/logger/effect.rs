use std::sync::{Arc, OnceLock};
use std::time::SystemTime;

pub(crate) fn run_effects(now: SystemTime, key: &str, message: &str) {
    let Some(effects) = EFFECTS.get() else { return };
    for effect in effects.iter() {
        effect(now, key, message);
    }
}

pub fn init_effects(effects: Vec<Box<dyn Fn(SystemTime, &str, &str) + Send + Sync>>) {
    EFFECTS.get_or_init(|| Arc::new(effects));
}

static EFFECTS: OnceLock<Arc<Vec<Box<dyn Fn(SystemTime, &str, &str) + Send + Sync>>>> =
    OnceLock::new();
