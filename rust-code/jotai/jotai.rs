use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Weak};
use weak_table::WeakKeyHashMap;

pub struct JotaiStore {
    map: WeakKeyHashMap<Weak<Atom>, Arc<u32>>,
}

impl JotaiStore {
    pub fn new() -> Self {
        Self {
            map: <WeakKeyHashMap<Weak<Atom>, Arc<u32>>>::new(),
        }
    }

    pub fn get(&self, atom: &Atom) -> Arc<u32> {
        self.map
            .get(atom)
            .cloned()
            .unwrap_or_else(|| Arc::new(atom.default_value))
    }

    pub fn set(&mut self, atom: Arc<Atom>, value: Arc<u32>) {
        self.map.insert(atom, value);
    }
}

#[derive(PartialEq, Eq, Hash)]
pub struct Atom {
    id: usize,
    default_value: u32,
}

impl Atom {
    pub fn new(default_value: u32) -> Self {
        Self {
            id: NEXT_ID.fetch_add(1, Ordering::Relaxed),
            default_value: default_value,
        }
    }
    // new(|get| get(i64Store, somei64Atom))
    // somei64Atom has id of the index inside the store
    // i64Store = Store::from { vec![somei64Atom]; }
    // So get now has dependency on i64Store, index 0
}

// Global, thread-safe counter
static NEXT_ID: AtomicUsize = AtomicUsize::new(0);
