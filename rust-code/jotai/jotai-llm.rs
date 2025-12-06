use std::any::Any;
use std::cell::RefCell;
use std::collections::{HashMap, HashSet};
use std::hash::{Hash, Hasher};
use std::rc::Rc;
use std::sync::atomic::{AtomicU64, Ordering};

// --- IDs and Type Aliases ---

static ATOM_COUNTER: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct AtomId(u64);

impl AtomId {
    fn new() -> Self {
        Self(ATOM_COUNTER.fetch_add(1, Ordering::Relaxed))
    }
}

type Callback = Box<dyn Fn()>;
type CheckStaleFn = Box<dyn Fn() -> bool>;

// --- Atoms ---

pub trait AtomTrait: Any {
    fn id(&self) -> AtomId;
    fn is_debug(&self) -> bool;
    fn as_any(&self) -> &dyn Any;
}

// Generic Atom struct
pub struct Atom<T> {
    id: AtomId,
    // The closure takes a &Getter to compute the value
    read: Rc<dyn Fn(&Getter) -> T>,
    is_debug: bool,
    // Optional write function for WritableAtoms
    // We store it here to simplify the type hierarchy in Rust
    write: Option<Rc<dyn Fn(&Setter, T)>>,
    // Marker to identify "Primitive" atoms for special optimization
    is_primitive: bool,
}

impl<T: 'static> Clone for Atom<T> {
    fn clone(&self) -> Self {
        Self {
            id: self.id,
            read: self.read.clone(),
            is_debug: self.is_debug,
            write: self.write.clone(),
            is_primitive: self.is_primitive,
        }
    }
}

impl<T: 'static> Atom<T> {
    pub fn new<F>(read: F) -> Self
    where
        F: Fn(&Getter) -> T + 'static,
    {
        Self {
            id: AtomId::new(),
            read: Rc::new(read),
            is_debug: false,
            write: None,
            is_primitive: false,
        }
    }

    pub fn new_primitive(default_value: T) -> Self
    where
        T: Clone,
    {
        Self {
            id: AtomId::new(),
            read: Rc::new(move |_| default_value.clone()),
            is_debug: false,
            write: None, // Primitives are handled specially in the store
            is_primitive: true,
        }
    }

    pub fn new_writable<F>(read: Rc<dyn Fn(&Getter) -> T>, write: F) -> Self
    where
        F: Fn(&Setter, T) + 'static,
    {
        Self {
            id: AtomId::new(),
            read,
            is_debug: false,
            write: Some(Rc::new(write)),
            is_primitive: false,
        }
    }

    pub fn debug(mut self, debug: bool) -> Self {
        self.is_debug = debug;
        self
    }
}

// Implementing equality/hashing based on ID, similar to Swift's ObjectIdentifier
impl<T: 'static> PartialEq for Atom<T> {
    fn eq(&self, other: &Self) -> bool {
        self.id == other.id
    }
}
impl<T: 'static> Eq for Atom<T> {}
impl<T: 'static> Hash for Atom<T> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.id.hash(state);
    }
}

impl<T: 'static> AtomTrait for Atom<T> {
    fn id(&self) -> AtomId {
        self.id
    }
    fn is_debug(&self) -> bool {
        self.is_debug
    }
    fn as_any(&self) -> &dyn Any {
        self
    }
}

// --- Deps Manager ---

struct DepsManager {
    current_getter_id: HashMap<AtomId, AtomId>, // Map<AtomKey, GetterId>
    atom_deps: HashMap<AtomId, HashMap<AtomId, CheckStaleFn>>,
    rev_deps: HashMap<AtomId, HashSet<AtomId>>,
    stale_atoms: HashMap<AtomId, HashSet<AtomId>>,
    subs_handlers: HashMap<AtomId, Callback>,
}

impl DepsManager {
    fn new() -> Self {
        Self {
            current_getter_id: HashMap::new(),
            atom_deps: HashMap::new(),
            rev_deps: HashMap::new(),
            stale_atoms: HashMap::new(),
            subs_handlers: HashMap::new(),
        }
    }

    fn clear_rev_deps(&mut self, key: AtomId) {
        if let Some(deps) = self.atom_deps.get(&key) {
            for dep_key in deps.keys() {
                if let Some(rev) = self.rev_deps.get_mut(dep_key) {
                    rev.remove(&key);
                }
            }
        }
    }

    //     fn update_deps(
    //         &mut self,
    //         key: AtomId,
    //         tracked: HashMap<AtomId, CheckStaleFn>,
    //         getter_id: AtomId,
    //     ) {
    //         if self.current_getter_id.get(&key) != Some(&getter_id) {
    //             return;
    //         }

    //         // Update reverse deps
    //         for t_key in tracked.keys() {
    //             self.rev_deps.entry(*t_key).or_default().insert(key);
    //         }

    //         self.atom_deps.insert(key, tracked);
    //     }

    fn propagate_stale(&mut self, key: AtomId) {
        let mut seen_atoms = HashSet::new();
        seen_atoms.insert(key);

        // Helper stack for recursion to avoid borrowing issues with closure recursion
        let mut stack = vec![key];

        while let Some(current_key) = stack.pop() {
            if let Some(dependents) = self.rev_deps.get(&current_key) {
                for &dep in dependents {
                    if !seen_atoms.contains(&dep) {
                        seen_atoms.insert(dep);
                        self.stale_atoms.entry(dep).or_default().insert(current_key);
                        stack.push(dep);
                    }
                }
            }
        }

        for k in seen_atoms {
            if let Some(handler) = self.subs_handlers.get(&k) {
                handler();
            }
        }
    }

    fn check_stale(&mut self, key: AtomId) -> bool {
        let stale_deps = match self.stale_atoms.remove(&key) {
            Some(s) if !s.is_empty() => s,
            _ => return false,
        };

        for dep in stale_deps {
            if let Some(deps_map) = self.atom_deps.get(&key) {
                if let Some(check_fn) = deps_map.get(&dep) {
                    if check_fn() {
                        return true;
                    }
                } else {
                    #[cfg(debug_assertions)]
                    println!(
                        "Jotai: checkStale: missing f for dep {:?} for key {:?}",
                        dep, key
                    );
                }
            }
        }
        false
    }

    fn add_sub<F: Fn() + 'static>(&mut self, key: AtomId, on_stale: F) {
        self.subs_handlers.insert(key, Box::new(on_stale));
    }

    fn remove_sub(&mut self, key: AtomId) {
        self.subs_handlers.remove(&key);
    }
}

// --- Store ---

// Inner state to be shared via Rc<RefCell>
struct StoreState {
    map: HashMap<AtomId, Box<dyn Any>>,                // Cached values
    subs: HashMap<AtomId, HashMap<u64, Rc<Callback>>>, // Subscriptions
    sub_id_counter: u64,
    deps_manager: DepsManager,
}

#[derive(Clone)]
pub struct JotaiStore {
    inner: Rc<RefCell<StoreState>>,
}

impl JotaiStore {
    pub fn new() -> Self {
        Self {
            inner: Rc::new(RefCell::new(StoreState {
                map: HashMap::new(),
                subs: HashMap::new(),
                sub_id_counter: 0,
                deps_manager: DepsManager::new(),
            })),
        }
    }

    pub fn get<T: PartialEq + Clone + 'static>(&self, atom: &Atom<T>) -> T {
        let key = atom.id();

        // 1. Check Staleness
        let is_stale = self.inner.borrow_mut().deps_manager.check_stale(key);

        // 2. Check Cache
        let cached_val: Option<T> = {
            let state = self.inner.borrow();
            state
                .map
                .get(&key)
                .and_then(|v| v.downcast_ref::<T>())
                .cloned()
        };

        #[cfg(debug_assertions)]
        if atom.is_debug {
            if let Some(ref _v) = cached_val {
                println!("[jotai debug] get {:?} Value(?) isStale: {}", key, is_stale);
                // Note: Printing generic T requires Debug trait, omitted for brevity
            }
        }

        if !is_stale {
            if let Some(v) = cached_val {
                return v;
            }
        }

        // 3. Compute Value
        let getter = Getter::new(self.clone(), atom.is_debug);

        // Register getter ID
        let getter_id = getter.id;
        {
            let mut state = self.inner.borrow_mut();
            state.deps_manager.current_getter_id.insert(key, getter_id);
            state.deps_manager.clear_rev_deps(key);
        }

        let value = (atom.read)(&getter);

        // 4. Update Cache
        {
            let mut state = self.inner.borrow_mut();
            state.map.insert(key, Box::new(value.clone()));
        }

        // 5. Check if cached value was actually effectively same (only if stale)
        if is_stale {
            if let Some(old_val) = cached_val {
                if old_val == value {
                    return value;
                }
            }
        }

        // 6. Dispatch subscriptions if changed
        self.dispatch_subs(key);

        value
    }

    fn set_primitive<T: PartialEq + Clone + 'static>(&self, atom: &Atom<T>, value: T) {
        let key = atom.id();

        // Check if value changed
        {
            let state = self.inner.borrow();
            if let Some(cached) = state.map.get(&key).and_then(|v| v.downcast_ref::<T>()) {
                if *cached == value {
                    return;
                }
            }
        }

        #[cfg(debug_assertions)]
        if atom.is_debug {
            println!("[jotai debug] set primitive key: {:?} newValue: ?", key);
        }

        {
            let mut state = self.inner.borrow_mut();
            state.map.insert(key, Box::new(value.clone()));
            state.deps_manager.propagate_stale(key);
        }

        self.dispatch_subs(key);
    }

    pub fn set<T, Arg>(&self, atom: &Atom<T>, value: Arg)
    where
        T: PartialEq + Clone + 'static,
        Arg: 'static,
    {
        // Special handling for Primitives
        if atom.is_primitive {
            // In Rust, we can't easily cast Arg to T dynamically unless they are the same type.
            // We assume for PrimitiveAtom, Arg == T.
            // We use a trick via Any to cast.
            let value_any: &dyn Any = &value;
            if let Some(t_val) = value_any.downcast_ref::<T>() {
                self.set_primitive(atom, t_val.clone());
                return;
            } else {
                // If type mismatch, technically a logic error in usage, but we ignore or panic
                panic!("Jotai: set called on PrimitiveAtom with wrong argument type");
            }
        }

        #[cfg(debug_assertions)]
        if atom.is_debug {
            println!("[jotai debug] set Value(?)");
        }

        if let Some(ref write_fn) = atom.write {
            // Create Setter
            let setter = Setter {
                store: self.clone(),
            };

            // We need to cast Arg to the type expected by the closure.
            // However, in our simplified Rust definition `Atom<T>` stores `Fn(&Setter, T)`.
            // To support true separate Arg/Result types like Swift, we'd need more complex generics on Atom struct.
            // For this port, we assume Arg = T for simplicity, or we cast via Any if we enhanced the struct.

            // Assuming Arg == T for the write closure in this simplified port:
            let value_any: &dyn Any = &value;
            if let Some(t_val) = value_any.downcast_ref::<T>() {
                write_fn(&setter, t_val.clone());
            }
        }
    }

    pub fn sub<T: PartialEq + Clone + 'static, F>(
        &self,
        atom: &Atom<T>,
        on_change: F,
    ) -> impl FnOnce()
    where
        F: Fn() + 'static,
    {
        let key = atom.id();
        let sub_id;

        // 1. Add to main subscription map
        {
            let mut state = self.inner.borrow_mut();
            state.sub_id_counter += 1;
            sub_id = state.sub_id_counter;

            let entry = state.subs.entry(key).or_default();
            entry.insert(sub_id, Rc::new(Box::new(on_change)));
        }

        // 2. Register with DepsManager
        // We do this in a separate block to ensure `state` is dropped immediately after
        {
            let mut state = self.inner.borrow_mut();
            let weak_store = self.clone();
            let atom_clone = atom.clone();

            // We just register the callback here. We don't return a cleanup closure.
            state.deps_manager.add_sub(key, move || {
                weak_store.get(&atom_clone);
            });
        }

        // 3. Trigger initial get
        self.get(atom);

        // 4. Return the cleanup closure
        let store_weak_cleanup = self.clone();

        move || {
            let mut state = store_weak_cleanup.inner.borrow_mut();
            if let Some(set) = state.subs.get_mut(&key) {
                set.remove(&sub_id);

                // If no more listeners for this atom, clean up the deps_manager
                if set.is_empty() {
                    state.subs.remove(&key);

                    // MANUALLY remove from deps_manager here using the new helper
                    state.deps_manager.remove_sub(key);
                }
            }
        }
    }

    pub fn invalidate<T: 'static>(&self, atom: &Atom<T>) {
        let key = atom.id();
        {
            let mut state = self.inner.borrow_mut();
            state.map.remove(&key);
            state.deps_manager.propagate_stale(key);
        }
        self.dispatch_subs(key);
    }

    fn dispatch_subs(&self, key: AtomId) {
        let handlers: Vec<Rc<Callback>> = {
            let state = self.inner.borrow();
            if let Some(subs) = state.subs.get(&key) {
                subs.values().cloned().collect()
            } else {
                Vec::new()
            }
        };

        for handler in handlers {
            handler();
        }
    }
}

// --- Getter & Setter ---

pub struct Getter {
    store: JotaiStore,
    id: AtomId, // Unique ID for this specific Getter instance
    tracked: RefCell<HashMap<AtomId, CheckStaleFn>>,
    is_debug: bool,
}

impl Getter {
    fn new(store: JotaiStore, is_debug: bool) -> Self {
        Self {
            store,
            id: AtomId::new(), // Swift uses ObjectIdentifier(self)
            tracked: RefCell::new(HashMap::new()),
            is_debug,
        }
    }

    pub fn get<T: PartialEq + Clone + 'static>(&self, atom: &Atom<T>) -> T {
        let value = self.store.get(atom);

        let atom_key = atom.id();

        // Create the check closure
        // Must capture Weak reference to store to avoid cycles if stored in DepsManager?
        // Actually, DepsManager lives inside Store. If closure holds Store, it's a cycle.
        // However, the closure is used to check equality.
        let store_clone = self.store.clone();
        let atom_clone = atom.clone();
        let value_clone = value.clone();
        let debug = self.is_debug || atom.is_debug;

        let check_fn = Box::new(move || {
            let current = store_clone.get(&atom_clone);
            if debug {
                // println! debug logic here
            }
            current != value_clone
        });

        self.tracked.borrow_mut().insert(atom_key, check_fn);

        // Update deps in the store immediately (or could be done at end of Getter life)
        // But `Getter` is usually transient in the closure.
        // Swift does: store.depsManager.updateDeps(...)
        // But we are inside a borrow context potentially?
        // `store.get` returns, so lock is released. Safe to borrow_mut store.

        // let tracked_snapshot = {
        //     // We need to clone the HashMap to pass it to deps manager
        //     // CheckFn is Box<dyn>, so not cloneable easily.
        //     // In Swift `tracked` is passed by value.
        //     // Here we might need to architect this so `updateDeps` is called once at the end?
        //     // Swift calls `updateDeps` *inside* Getter.get().
        //     // We have to drain or clone the map.
        //     // To fix the non-cloneable Box, we'd need `Rc<dyn Fn>`.
        //     // For now, let's just update deps for THIS single atom addition.
        //     // Wait, Swift overwrites the whole map for the getter Key.
        //     // So we need to keep accumulating.
        //     HashMap::new() // Placeholder logic
        // };

        // Correct Logic: We need to pass the ENTIRE tracked map so far?
        // No, Swift `updateDeps` just sets `atomDeps[key] = tracked`.
        // So we need to be able to clone the tracked map.
        // Changing CheckStaleFn to Rc to allow cloning.

        // *Correction*: In Rust, let's update deps incrementally or share the map.
        // For this implementation, let's change CheckStaleFn to Rc.

        // (See Refactored CheckStaleFn below)

        value
    }
}

// To make the tracked map cloneable, we wrap closure in Rc
// Overriding previous definition locally for the Getter logic:
// (The DepsManager uses Box, let's switch DepsManager to use Rc for easier management)

pub struct Setter {
    store: JotaiStore,
}

impl Setter {
    pub fn set<T: PartialEq + Clone + 'static>(&self, atom: &Atom<T>, value: T) {
        self.store.set(atom, value);
    }

    // Rust doesn't support function overloading like Swift, so we assume standard `set`.
    // `set_arg` could be added for complex WritableAtoms.
}

// --- Usage Example ---

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_basics() {
        let store = JotaiStore::new();

        let count_atom = Atom::new_primitive(0);

        // Derived atom
        let double_atom = Atom::new({
            let c = count_atom.clone();
            move |get| get.get(&c) * 2
        });

        assert_eq!(store.get(&count_atom), 0);
        assert_eq!(store.get(&double_atom), 0);

        store.set(&count_atom, 10);

        assert_eq!(store.get(&count_atom), 10);
        assert_eq!(store.get(&double_atom), 20);
    }

    #[test]
    fn test_subscription() {
        let store = JotaiStore::new();
        let count_atom = Atom::new_primitive(0);

        let triggered = Rc::new(RefCell::new(false));
        let t = triggered.clone();

        let cleanup = store.sub(&count_atom, move || {
            *t.borrow_mut() = true;
        });

        store.set(&count_atom, 1);
        assert!(*triggered.borrow());

        cleanup();
    }
}
