use std::hash::{Hash, Hasher};
use std::rc::Rc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Weak};
use weak_table::WeakKeyHashMap;

pub struct JotaiStore {
    map: WeakKeyHashMap<Weak<AtomId>, Arc<u32>>,
}

impl JotaiStore {
    pub fn new() -> Self {
        Self {
            map: <WeakKeyHashMap<Weak<AtomId>, Arc<u32>>>::new(),
        }
    }

    pub fn get(&self, atom: &Atom<u32>) -> Arc<u32> {
        self.map.get(&*atom.id).cloned().unwrap_or_else(|| {
            Arc::new(match &atom.read {
                AtomReader::Value(v) => *v,
                AtomReader::Fn(f) => f(&Getter::new(self)),
            })
        })
    }

    pub fn set(&mut self, atom: &Atom<u32>, value: Arc<u32>) {
        self.map.insert(atom.id.clone(), value);
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct AtomId(usize);
impl AtomId {
    fn new() -> Self {
        Self(new_id())
    }
}
// Global, thread-safe counter
static NEXT_ID: AtomicUsize = AtomicUsize::new(0);
fn new_id() -> usize {
    NEXT_ID.fetch_add(1, Ordering::Relaxed)
}

pub enum AtomReader<T> {
    Fn(Box<dyn Fn(&Getter) -> T>),
    Value(T),
}
pub struct Atom<T> {
    id: Arc<AtomId>,
    read: AtomReader<T>,
}
impl<T> PartialEq for Atom<T> {
    fn eq(&self, other: &Self) -> bool {
        self.id == other.id
    }
}
impl<T> Eq for Atom<T> {}
impl<T> Hash for Atom<T> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.id.hash(state);
    }
}

impl<T> Atom<T> {
    pub fn new(default_value: T) -> Self {
        Self {
            id: Arc::new(AtomId::new()),
            read: AtomReader::Value(default_value),
        }
    }
}
impl<T: 'static> Atom<T> {
    pub fn new_f<F>(f: F) -> Self
    where
        F: Fn(&Getter) -> T + 'static,
    {
        Self {
            id: Arc::new(AtomId::new()),
            read: AtomReader::Fn(Box::new(f)),
        }
    }
}

pub struct Getter<'a> {
    store: &'a JotaiStore,
    // tracked: RefCell<HashMap<AtomId, CheckStaleFn>>,
}
impl<'a> Getter<'a> {
    fn new(store: &'a JotaiStore) -> Self {
        Self { store }
    }
    pub fn get(&self, atom: &Atom<u32>) -> Arc<u32> {
        self.store.get(atom)
    }
}

#[cfg(test)]
mod tests {
    use std::cell::RefCell;

    use super::*;

    thread_local! {
        pub static DEFAULT_STORE: RefCell<JotaiStore> = RefCell::new(JotaiStore::new());
        pub static COUNTER_ATOM: RefCell<Arc<Atom<u32>>> = RefCell::new(Arc::new(Atom::new(10)));
    }
    // pub static DEFAULT_STORE: LazyLock<Mutex<JotaiStore>> =
    //     LazyLock::new(|| Mutex::new(JotaiStore::new()));
    // pub static COUNTER_ATOM: LazyLock<Arc<Atom<u32>>> = LazyLock::new(|| Arc::new(Atom::new(10)));

    #[test]
    fn test_globals() {
        // if let Ok(mut store) = DEFAULT_STORE.lock() {
        //     let counter_atom = COUNTER_ATOM.clone();
        //     assert_eq!(*store.get(&*counter_atom), 10);
        //     store.set(&counter_atom, Arc::new(20));
        //     assert_eq!(*store.get(&*counter_atom), 20);
        // }
        DEFAULT_STORE.with(|store_ref| {
            let mut store = store_ref.borrow_mut();
            COUNTER_ATOM.with(|counter_atom_ref| {
                let counter_atom = counter_atom_ref.borrow();
                assert_eq!(*store.get(&*counter_atom), 10);
                store.set(&counter_atom, Arc::new(20));
                assert_eq!(*store.get(&*counter_atom), 20);
            })
        });
    }

    #[test]
    fn test_weak_store() {
        let mut store = JotaiStore::new();
        {
            let counter_atom = Arc::new(Atom::new(10));
            assert_eq!(*store.get(&*counter_atom), 10);
            store.set(&counter_atom, Arc::new(20));
            assert_eq!(*store.get(&*counter_atom), 20);
            assert_eq!(store.map.keys().count(), 1);
        }
        assert_eq!(store.map.keys().count(), 0);
    }

    #[test]
    fn test_derivative_atom() {
        let mut store = JotaiStore::new();
        let counter_atom = Arc::new(Atom::new(10));
        let counter = Rc::new(RefCell::new(0));
        let derivative_atom = Atom::new_f({
            let c = counter_atom.clone();
            let c_ref = counter.clone();
            move |get| {
                *c_ref.borrow_mut() += 1;
                *get.get(&c) * 2
            }
        });
        assert_eq!(*store.get(&*counter_atom), 10);
        assert_eq!(*store.get(&derivative_atom), 20);
        assert_eq!(*counter.borrow(), 1);
        store.set(&counter_atom, Arc::new(20));
        assert_eq!(*store.get(&*counter_atom), 20);
        assert_eq!(*store.get(&derivative_atom), 40);
        assert_eq!(*counter.borrow(), 2);
        assert_eq!(*store.get(&derivative_atom), 40);

        // Derivative atoms caching is not implemented
        // assert_eq!(*counter.borrow(), 2);
    }
}
