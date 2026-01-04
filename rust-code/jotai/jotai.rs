use parking_lot::ReentrantMutex;
use send_wrapper::SendWrapper;
use std::any::Any;
use std::cell::RefCell;
use std::collections::HashSet;
use std::hash::{Hash, Hasher};
use std::rc::Rc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, Weak};
use weak_table::{WeakHashSet, WeakKeyHashMap};

pub struct JotaiStore {
    map: Rc<RefCell<WeakKeyHashMap<Weak<AtomId>, Arc<dyn Any + Send + Sync>>>>,
    deps_manager: Rc<DepsManager>,
    subs: Rc<RefCell<WeakKeyHashMap<Weak<AtomId>, Rc<SubscriptionSet<()>>>>>,
    mutex: ReentrantMutex<()>,
}
impl JotaiStore {
    pub fn new() -> Arc<Self> {
        Arc::new(Self {
            map: Rc::new(RefCell::new(WeakKeyHashMap::new())),
            deps_manager: Rc::new(DepsManager::new()),
            subs: Rc::new(RefCell::new(WeakKeyHashMap::new())),
            mutex: ReentrantMutex::new(()),
        })
    }

    pub fn get<T: 'static + PartialEq + Send + Sync>(
        self: Arc<Self>,
        atom: &(impl ReadAtom<T> + ?Sized),
    ) -> Arc<T> {
        let _ = self.mutex.lock();
        let is_stale = self.deps_manager.check_stale(&atom.get_id());
        let cached_value = self
            .map
            .borrow_mut()
            .get(&*atom.get_id())
            .cloned()
            .and_then(|v| v.downcast::<T>().ok());

        if !is_stale {
            if let Some(cached_value) = cached_value {
                return cached_value;
            }
        }

        self.deps_manager.clear_rev_deps(*atom.get_id());
        let value: Arc<T> = Arc::new({
            let read = atom.get_read();
            let mut getter = Getter::new(self.clone(), atom.get_id());
            self.deps_manager
                .current_getter_id
                .borrow_mut()
                .insert(atom.get_id(), getter.id);
            read(&mut getter)
        });
        self.map
            .borrow_mut()
            .insert(atom.get_id().clone(), value.clone());

        if is_stale && cached_value.clone().is_some_and(|v| v == value.clone()) {
            return value;
        }

        if cached_value.is_some() {
            if let Some(closures) = self.subs.borrow().get(&atom.get_id()) {
                closures.notify(&());
            }
        }

        return value;
    }

    pub fn set_primitive<T: 'static + PartialEq + Send + Sync>(
        &self,
        atom: Arc<PrimitiveAtom<T>>,
        arg: Arc<T>,
    ) {
        let _ = self.mutex.lock();
        {
            let map = self.map.borrow();
            let cached_value = map.get(&*atom.get_id()).and_then(|v| v.downcast_ref::<T>());
            if cached_value.is_some_and(|v| *v == *arg.clone()) {
                return;
            }

            self.map.borrow_mut().insert(atom.get_id().clone(), arg);
        }

        self.deps_manager.propagate_stale(atom.get_id().clone());

        if let Some(closures) = self.subs.borrow().get(&atom.get_id()) {
            closures.notify(&());
        }
    }

    pub fn set<Arg: PartialEq + 'static>(self: Arc<Self>, atom: &DispatchAtom<Arg>, arg: &Arg) {
        let _ = self.mutex.lock();
        let mut setter = Setter::new(self.clone());
        (atom.dispatch)(&mut setter, &arg);
    }

    pub fn set_and_return<Arg: PartialEq + 'static, Return>(
        self: Arc<Self>,
        atom: &DispatchWithReturnAtom<Arg, Return>,
        arg: &Arg,
    ) -> Return {
        let _ = self.mutex.lock();
        let mut setter = Setter::new(self.clone());
        (atom.dispatch)(&mut setter, arg)
    }

    pub fn sub<T: 'static + PartialEq + Send + Sync, F>(
        self: Arc<Self>,
        atom: Arc<(impl ReadAtom<T> + ?Sized + 'static + Send + Sync)>,
        on_change: F,
    ) -> impl Fn() + Send + Sync
    where
        F: Fn(&()) + 'static + Send + Sync,
    {
        let _ = self.mutex.lock();
        let store = self.clone();
        let atom_c = atom.clone();
        let dispose_dep = self.deps_manager.add_sub(atom.get_id(), move || {
            store.clone().get(&*atom_c);
        });
        let dispose_dep = Arc::new(Mutex::new(Some(dispose_dep)));
        let dispose_sub = self
            .subs
            .borrow_mut()
            .entry(atom.get_id())
            .or_insert_with(|| Rc::new(SubscriptionSet::new()))
            .sub(on_change);
        let dispose_sub = Arc::new(Mutex::new(Some(dispose_sub)));
        let dispose_sub = SendWrapper::new(dispose_sub);
        let dispose_dep = SendWrapper::new(dispose_dep);
        self.clone().get(&*atom);
        return move || {
            let _ = self.mutex.lock();
            if let Ok(mut guard) = dispose_sub.lock() {
                if let Some(cleanup) = guard.take() {
                    cleanup();
                }
            }
            let closures = self.subs.borrow().get(&atom.get_id()).cloned();
            if let Some(closures) = closures {
                if closures.is_empty() {
                    if let Ok(mut guard) = dispose_dep.lock() {
                        if let Some(cleanup) = guard.take() {
                            cleanup();
                        }
                    }
                    self.subs.borrow_mut().remove(&atom.get_id());
                }
            }
        };
    }
}
// We trust that with the Reentrant mutex on all public methods, it's Send + Sync
unsafe impl Send for JotaiStore {}
unsafe impl Sync for JotaiStore {}

// Global, thread-safe counter
static NEXT_ID: AtomicUsize = AtomicUsize::new(0);
fn new_id() -> usize {
    NEXT_ID.fetch_add(1, Ordering::Relaxed)
}

type Dispatch<Arg, Return> = Box<dyn Fn(&mut Setter, &Arg) -> Arc<Return>>;

pub trait Atom {
    fn get_id(&self) -> Arc<AtomId>;
}
pub trait ReadAtom<T>: Atom {
    fn get_read(&self) -> &Box<dyn Fn(&mut Getter) -> T + Send + Sync>;
}
pub trait WriteAtom<Arg, Return>: Atom {
    fn get_write(&self) -> Option<Arc<Dispatch<Arg, Return>>>;
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct AtomId(usize);
impl AtomId {
    fn new() -> Self {
        Self(new_id())
    }
}
pub struct SelectAtom<T> {
    id: Arc<AtomId>,
    read: Box<dyn Fn(&mut Getter) -> T + Send + Sync>,
}
impl<T> PartialEq for SelectAtom<T> {
    fn eq(&self, other: &Self) -> bool {
        self.id == other.id
    }
}
impl<T> Eq for SelectAtom<T> {}
impl<T> Hash for SelectAtom<T> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.id.hash(state);
    }
}
impl<T: 'static> SelectAtom<T> {
    pub fn new<F>(f: F) -> Self
    where
        F: Fn(&mut Getter) -> T + 'static + Send + Sync,
    {
        Self {
            id: Arc::new(AtomId::new()),
            read: Box::new(f),
        }
    }
}
impl<T> Atom for SelectAtom<T> {
    fn get_id(&self) -> Arc<AtomId> {
        self.id.clone()
    }
}
impl<T> ReadAtom<T> for SelectAtom<T> {
    fn get_read(&self) -> &Box<dyn Fn(&mut Getter) -> T + Send + Sync> {
        &self.read
    }
}

pub struct DispatchAtom<Arg> {
    id: Arc<AtomId>,
    dispatch: Box<dyn Fn(&mut Setter, &Arg)>,
}
impl<Arg> PartialEq for DispatchAtom<Arg> {
    fn eq(&self, other: &Self) -> bool {
        self.id == other.id
    }
}
impl<Arg> Eq for DispatchAtom<Arg> {}
impl<Arg> Hash for DispatchAtom<Arg> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.id.hash(state);
    }
}
impl<Arg> DispatchAtom<Arg> {
    pub fn new<F>(setter: F) -> Self
    where
        F: Fn(&mut Setter, &Arg) + 'static,
    {
        Self {
            id: Arc::new(AtomId::new()),
            dispatch: Box::new(setter),
        }
    }
}
impl<Arg> Atom for DispatchAtom<Arg> {
    fn get_id(&self) -> Arc<AtomId> {
        self.id.clone()
    }
}

pub struct DispatchWithReturnAtom<Arg, Return> {
    id: Arc<AtomId>,
    dispatch: Box<dyn Fn(&mut Setter, &Arg) -> Return>,
}
impl<Arg, Return> PartialEq for DispatchWithReturnAtom<Arg, Return> {
    fn eq(&self, other: &Self) -> bool {
        self.id == other.id
    }
}
impl<Arg, Return> Eq for DispatchWithReturnAtom<Arg, Return> {}
impl<Arg, Return> Hash for DispatchWithReturnAtom<Arg, Return> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.id.hash(state);
    }
}
impl<Arg, Return> DispatchWithReturnAtom<Arg, Return> {
    pub fn new<F>(setter: F) -> Self
    where
        F: Fn(&mut Setter, &Arg) -> Return + 'static,
    {
        Self {
            id: Arc::new(AtomId::new()),
            dispatch: Box::new(setter),
        }
    }
}
impl<Arg, Return> Atom for DispatchWithReturnAtom<Arg, Return> {
    fn get_id(&self) -> Arc<AtomId> {
        self.id.clone()
    }
}

pub struct PrimitiveAtom<T> {
    id: Arc<AtomId>,
    read: Box<dyn Fn(&mut Getter) -> T + Send + Sync>,
}
impl<T> PartialEq for PrimitiveAtom<T> {
    fn eq(&self, other: &Self) -> bool {
        self.id == other.id
    }
}
impl<T> Eq for PrimitiveAtom<T> {}
impl<T> Hash for PrimitiveAtom<T> {
    fn hash<H: Hasher>(&self, state: &mut H) {
        self.id.hash(state);
    }
}
impl<T: Clone + Send + Sync + 'static> PrimitiveAtom<T> {
    pub fn new(default_value: T) -> Self {
        Self {
            id: Arc::new(AtomId::new()),
            read: Box::new(move |_| default_value.clone()),
        }
    }
}
impl<T: Send + Sync + 'static> PrimitiveAtom<T> {
    pub fn new_fn(f: Box<dyn Fn(&mut Getter) -> T + Send + Sync>) -> Self {
        Self {
            id: Arc::new(AtomId::new()),
            read: f,
        }
    }
}
impl<T> Atom for PrimitiveAtom<T> {
    fn get_id(&self) -> Arc<AtomId> {
        self.id.clone()
    }
}
impl<T> ReadAtom<T> for PrimitiveAtom<T> {
    fn get_read(&self) -> &Box<dyn Fn(&mut Getter) -> T + Send + Sync> {
        &self.read
    }
}
impl<T> WriteAtom<T, ()> for PrimitiveAtom<T> {
    fn get_write(&self) -> Option<Arc<Dispatch<T, ()>>> {
        None
    }
}

pub fn atom<T: Clone + Send + Sync + 'static>(default_value: T) -> PrimitiveAtom<T> {
    PrimitiveAtom::new(default_value)
}
pub fn select_atom<T: 'static>(
    f: impl Fn(&mut Getter) -> T + 'static + Send + Sync,
) -> SelectAtom<T> {
    SelectAtom::new(f)
}
pub fn dispatch_atom<Arg, F>(f: F) -> DispatchAtom<Arg>
where
    F: Fn(&mut Setter, &Arg) + 'static,
{
    DispatchAtom::new(f)
}
pub fn dispatch_with_return_atom<Arg, Return, F>(f: F) -> DispatchWithReturnAtom<Arg, Return>
where
    F: Fn(&mut Setter, &Arg) -> Return + 'static,
{
    DispatchWithReturnAtom::new(f)
}

static NEXT_GETTER_ID: AtomicUsize = AtomicUsize::new(0);
fn new_getter_id() -> usize {
    NEXT_GETTER_ID.fetch_add(1, Ordering::Relaxed)
}
pub struct Getter {
    id: usize,
    atom_id: Arc<AtomId>,
    store: Arc<JotaiStore>,
    tracked: Rc<RefCell<WeakKeyHashMap<Weak<AtomId>, Box<dyn Fn() -> bool>>>>,
}
impl Getter {
    fn new(store: Arc<JotaiStore>, atom_id: Arc<AtomId>) -> Self {
        Self {
            id: new_getter_id(),
            store,
            atom_id,
            tracked: Rc::new(RefCell::new(WeakKeyHashMap::new())),
        }
    }
    pub fn get<T: 'static + PartialEq + Send + Sync>(&self, atom: Arc<dyn ReadAtom<T>>) -> Arc<T> {
        let store = self.store.clone();
        let result = store.clone().get(&*atom);
        let value = result.clone();
        let atom_c = atom.clone();
        self.tracked.borrow_mut().insert(
            atom.get_id(),
            Box::new(move || {
                let current_value = store.clone().get(&*atom_c);
                return current_value != value;
            }),
        );
        self.store
            .deps_manager
            .update_deps(self.atom_id.clone(), self.tracked.clone(), &self.id);
        return result;
    }
}
pub struct Setter {
    store: Arc<JotaiStore>,
}
impl Setter {
    fn new(store: Arc<JotaiStore>) -> Self {
        Self { store }
    }
    pub fn get<T: 'static + PartialEq + Send + Sync>(&self, atom: Arc<dyn ReadAtom<T>>) -> Arc<T> {
        return self.store.clone().get(&*atom);
    }
    pub fn set<Arg: PartialEq + 'static, Return>(&self, atom: &DispatchAtom<Arg>, arg: &Arg) {
        return self.store.clone().set(atom, arg);
    }
    pub fn set_and_return<Arg: PartialEq + 'static, Return>(
        &self,
        atom: &DispatchWithReturnAtom<Arg, Return>,
        arg: &Arg,
    ) -> Return {
        return self.store.clone().set_and_return(atom, arg);
    }
    pub fn set_primitive<T: PartialEq + 'static + Send + Sync>(
        &self,
        atom: Arc<PrimitiveAtom<T>>,
        arg: Arc<T>,
    ) {
        return self.store.clone().set_primitive(atom, arg);
    }
}

struct DepsManager {
    pub current_getter_id: Rc<RefCell<WeakKeyHashMap<Weak<AtomId>, usize>>>, // Map<AtomKey, GetterId>
    stale_dep_check: Rc<
        RefCell<
            WeakKeyHashMap<
                Weak<AtomId>,
                Rc<RefCell<WeakKeyHashMap<Weak<AtomId>, Box<dyn Fn() -> bool>>>>,
            >,
        >,
    >,
    rev_deps: Rc<RefCell<WeakKeyHashMap<Weak<AtomId>, WeakHashSet<Weak<AtomId>>>>>,
    // stale_atoms is only necessary for derived atoms
    stale_atoms: Rc<RefCell<WeakKeyHashMap<Weak<AtomId>, WeakHashSet<Weak<AtomId>>>>>,
    subs_handlers: Rc<RefCell<WeakKeyHashMap<Weak<AtomId>, Box<dyn Fn()>>>>,
}
// Notable Edge cases to handle:
// 1. async getter, i.e. get, wait a bit, get some more
// 2. A -> B -> BB
//      ∟> C -> CC
//         D /
//    Everything is cached A is A0, A is updated to A1, dependents are marked stale, BB is subbed.
//    B, BB, C, CC are marked stale (rev deps). When BB is marked stale, it is get
//    If B has not changed, then BB is not stale, do not publish to sub
//    A is updated again (A2).
//    CC is get, C needs to check A against the version that was got first time (A2 vs A0)

// 1. currentGetterId[atom.id] for current getter, ignore old getters
// 2. atomDeps -> atom.id -> {[atom.id]: Fn() -> bool} (returns if a specific atom is stale)
// 3. old stale atoms would keep track of which are stale, but we can just run the stale check for
//    all atoms. Basically less cost at write time, more cost at read time.
impl DepsManager {
    fn new() -> Self {
        Self {
            current_getter_id: Rc::new(RefCell::new(WeakKeyHashMap::new())),
            stale_dep_check: Rc::new(RefCell::new(WeakKeyHashMap::new())),
            rev_deps: Rc::new(RefCell::new(WeakKeyHashMap::new())),
            stale_atoms: Rc::new(RefCell::new(WeakKeyHashMap::new())),
            subs_handlers: Rc::new(RefCell::new(WeakKeyHashMap::new())),
        }
    }

    fn clear_rev_deps(&self, atom_id: AtomId) {
        if let Some(deps) = self.stale_dep_check.borrow().get(&atom_id) {
            for dep_key in deps.borrow().keys() {
                if let Some(rev) = self.rev_deps.borrow_mut().get_mut(&dep_key) {
                    rev.remove(&atom_id);
                }
            }
        }
    }

    fn update_deps(
        &self,
        atom_id: Arc<AtomId>,
        tracked: Rc<RefCell<WeakKeyHashMap<Weak<AtomId>, Box<dyn Fn() -> bool>>>>,
        getter_id: &usize,
    ) {
        if self.current_getter_id.borrow().get(&atom_id) != Some(&getter_id) {
            return;
        }

        self.stale_dep_check
            .borrow_mut()
            .insert(atom_id.clone(), tracked.clone());
        for t_key in tracked.borrow().keys() {
            self.rev_deps
                .borrow_mut()
                .entry(t_key)
                .or_insert_with(|| WeakHashSet::new())
                .insert(atom_id.clone());
        }
    }

    fn propagate_stale(&self, atom_id: Arc<AtomId>) {
        let mut seen_atoms = HashSet::<Arc<AtomId>>::new();
        seen_atoms.insert(atom_id.clone());
        let mut stack = vec![atom_id.clone()];
        while let Some(current) = stack.pop() {
            if let Some(dependents) = self.rev_deps.borrow().get(&current) {
                for dep in dependents {
                    if seen_atoms.contains(&dep) {
                        continue;
                    }
                    seen_atoms.insert(dep.clone());
                    self.stale_atoms
                        .borrow_mut()
                        .entry(dep.clone())
                        .or_insert_with(|| WeakHashSet::new())
                        .insert(current.clone());
                    stack.push(dep.clone());
                }
            }
        }
        for seen_atom_id in seen_atoms {
            self.subs_handlers.borrow().get(&seen_atom_id).map(|f| f());
        }
    }

    fn check_stale(&self, atom_id: &AtomId) -> bool {
        let Some(stale_deps) = self.stale_atoms.borrow_mut().remove(atom_id) else {
            return false;
        };

        for dep in stale_deps {
            let v = self
                .stale_dep_check
                .borrow()
                .get(&atom_id)
                .map(|v| v.clone());
            if v.and_then(|deps_map| deps_map.borrow().get(&dep).map(|v| v()))
                .is_some_and(|v| v)
            {
                return true;
            }
        }
        false
    }

    fn add_sub<F: Fn() + 'static + Send + Sync>(
        &self,
        atom_id: Arc<AtomId>,
        on_stale: F,
    ) -> Box<dyn FnOnce()> {
        let mut handlers = self.subs_handlers.borrow_mut();
        handlers.insert(atom_id.clone(), Box::new(on_stale));
        let handlers_c = self.subs_handlers.clone();
        Box::new(move || {
            handlers_c.borrow_mut().remove(&atom_id);
        })
    }
}

static NEXT_CLOSURE_ID: AtomicUsize = AtomicUsize::new(0);
fn new_closure_id() -> usize {
    NEXT_CLOSURE_ID.fetch_add(1, Ordering::Relaxed)
}
struct SubscriptionSet<T> {
    callbacks: Rc<RefCell<WeakKeyHashMap<Weak<usize>, Box<dyn Fn(&T)>>>>,
}
impl<T: 'static> SubscriptionSet<T> {
    fn new() -> Self {
        Self {
            callbacks: Rc::new(RefCell::new(WeakKeyHashMap::new())),
        }
    }
    fn sub<F: Fn(&T) + 'static>(&self, f: F) -> Box<dyn FnOnce()> {
        let closure_id = Arc::new(new_closure_id());
        let callbacks = self.callbacks.clone();
        self.callbacks
            .borrow_mut()
            .insert(closure_id.clone(), Box::new(f));
        return Box::new(move || {
            callbacks.borrow_mut().remove(&closure_id);
        });
    }
    fn notify(&self, v: &T) {
        self.callbacks.borrow().values().for_each(|f| f(v));
    }
    fn is_empty(&self) -> bool {
        self.callbacks.borrow().keys().count() == 0
    }
}

#[cfg(test)]
mod tests {
    use std::cell::RefCell;
    use std::sync::{LazyLock, Mutex};

    use super::*;

    thread_local! {
        pub static DEFAULT_STORE: Arc<JotaiStore> = JotaiStore::new();
        pub static COUNTER_ATOM: Arc<PrimitiveAtom<u32>> = Arc::new(atom(10));
    }
    #[test]
    fn test_globals() {
        let store = DEFAULT_STORE.with(|arc| arc.clone());
        let counter_atom = COUNTER_ATOM.with(|arc| arc.clone());
        assert_eq!(*store.clone().get(&*counter_atom), 10);
        store
            .clone()
            .set_primitive(counter_atom.clone(), Arc::new(20));
        assert_eq!(*store.clone().get(&*counter_atom), 20);
    }

    thread_local! {
        pub static DEFAULT_STORE_2: LazyLock<Arc<JotaiStore>> = LazyLock::new(|| JotaiStore::new());
        pub static COUNTER_ATOM_2: LazyLock<Arc<PrimitiveAtom<u32>>> =
            LazyLock::new(|| Arc::new(atom(10)));
    }
    #[test]
    fn test_globals_lazylock() {
        // I haven't figured out how to remove the thread_local! yet
        let store = DEFAULT_STORE_2.with(|v| (**v).clone());
        let counter_atom = COUNTER_ATOM_2.with(|v| (**v).clone());
        assert_eq!(*store.clone().get(&*counter_atom), 10);
        store
            .clone()
            .set_primitive(counter_atom.clone(), Arc::new(20));
        assert_eq!(*store.get(&*counter_atom), 20);
    }

    #[test]
    fn test_weak_store() {
        let store = JotaiStore::new();
        {
            let counter_atom = Arc::new(atom(10));
            assert_eq!(*store.clone().get(&*counter_atom), 10);
            store
                .clone()
                .set_primitive(counter_atom.clone(), Arc::new(20));
            assert_eq!(*store.clone().get(&*counter_atom), 20);
            assert_eq!(store.map.borrow().keys().count(), 1);
        }
        assert_eq!(store.map.borrow().keys().count(), 0);
    }

    #[test]
    fn test_derivative_atom() {
        let store = JotaiStore::new();
        let counter_atom = Arc::new(atom(10));
        let counter = Arc::new(Mutex::new(0));
        let derivative_atom = select_atom({
            let c = counter_atom.clone();
            let c_ref = counter.clone();
            move |get| {
                *c_ref.lock().unwrap() += 1;
                *get.get(c.clone()) * 2
            }
        });
        assert_eq!(*store.clone().get(&*counter_atom), 10);
        assert_eq!(*store.clone().get(&derivative_atom), 20);
        assert_eq!(*counter.lock().unwrap(), 1);
        store
            .clone()
            .set_primitive(counter_atom.clone(), Arc::new(20));
        assert_eq!(*store.clone().get(&*counter_atom), 20);
        assert_eq!(*store.clone().get(&derivative_atom), 40);
        assert_eq!(*counter.lock().unwrap(), 2);
        assert_eq!(*store.clone().get(&derivative_atom), 40);
        assert_eq!(*counter.lock().unwrap(), 2);
    }

    #[test]
    fn test_write_atom() {
        let store = JotaiStore::new();
        let counter_atom = Arc::new(atom(10));
        let counter_atom_c = counter_atom.clone();
        let increment_counter_atom = dispatch_atom(move |setter, _| {
            setter.set_primitive(
                counter_atom_c.clone(),
                Arc::new(*setter.get(counter_atom_c.clone()) + 1),
            );
        });
        let counter_atom_c2 = counter_atom.clone();
        let increment_and_get_atom = dispatch_with_return_atom(move |setter, _| {
            setter.set_primitive(
                counter_atom_c2.clone(),
                Arc::new(*setter.get(counter_atom_c2.clone()) + 1),
            );
            setter.get(counter_atom_c2.clone())
        });
        assert_eq!(*store.clone().get(&*counter_atom), 10);
        store.clone().set(&increment_counter_atom, &());
        assert_eq!(*store.clone().get(&*counter_atom), 11);
        assert_eq!(
            *store.clone().set_and_return(&increment_and_get_atom, &()),
            12
        );
        assert_eq!(*store.clone().get(&*counter_atom), 12);
    }

    #[test]
    fn test_sub_atom() {
        let store = JotaiStore::new();
        let value_atom = Arc::new(atom(10));
        let d2_counter = Arc::new(Mutex::new(0));
        let sub_counter = Rc::new(RefCell::new(0));
        let derivative_atom = Arc::new(select_atom({
            let value_atom_c = value_atom.clone();
            move |getter| *getter.get(value_atom_c.clone()) < 12
        }));
        let derivative2_atom = Arc::new(select_atom({
            let d = derivative_atom.clone();
            let counter = d2_counter.clone();
            move |getter| {
                *counter.lock().unwrap() += 1;
                *getter.get(d.clone())
            }
        }));
        let dispose = store.clone().sub(derivative2_atom.clone(), {
            let counter = sub_counter.clone();
            move |_| *counter.borrow_mut() += 1
        });
        assert_eq!(*d2_counter.lock().unwrap(), 1);
        assert_eq!(*sub_counter.borrow(), 0);
        assert_eq!(*store.clone().get(&*derivative2_atom), true);
        assert_eq!(*d2_counter.lock().unwrap(), 1);
        assert_eq!(*sub_counter.borrow(), 0);
        store
            .clone()
            .set_primitive(value_atom.clone(), Arc::new(11));
        assert_eq!(*d2_counter.lock().unwrap(), 1);
        assert_eq!(*sub_counter.borrow(), 0);
        store
            .clone()
            .set_primitive(value_atom.clone(), Arc::new(12));
        assert_eq!(*d2_counter.lock().unwrap(), 2);
        assert_eq!(*sub_counter.borrow(), 1);

        dispose();

        store
            .clone()
            .set_primitive(value_atom.clone(), Arc::new(11));
        assert_eq!(*d2_counter.lock().unwrap(), 2);
        assert_eq!(*sub_counter.borrow(), 1);
    }

    #[test]
    fn test_subscription_set() {
        let set = SubscriptionSet::new();
        let counter_ref = Rc::new(RefCell::new(0));
        let counter2_ref = Rc::new(RefCell::new(10));
        let counter_ref1 = counter_ref.clone();
        let dispose1 = set.sub(move |v| {
            *(counter_ref1.borrow_mut()) += v;
        });
        let counter2_ref1 = counter2_ref.clone();
        let dispose2 = set.sub(move |v| {
            *counter2_ref1.borrow_mut() += v * 2;
        });
        set.notify(&3);
        assert_eq!(*counter_ref.borrow(), 3);
        assert_eq!(*counter2_ref.borrow(), 16);
        dispose2();
        set.notify(&4);
        assert_eq!(*counter_ref.borrow(), 7);
        assert_eq!(*counter2_ref.borrow(), 16);
        // FnOnce means you can't call twice
        // dispose2();
        dispose1();
        set.notify(&4);
        assert_eq!(*counter_ref.borrow(), 7);
        assert_eq!(*counter2_ref.borrow(), 16);
    }
}
