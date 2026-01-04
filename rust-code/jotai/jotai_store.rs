use parking_lot::ReentrantMutex;
use send_wrapper::SendWrapper;
use std::any::Any;
use std::cell::RefCell;
use std::collections::HashSet;
use std::rc::Rc;
use std::sync::{Arc, Mutex, Weak};
use weak_table::{WeakHashSet, WeakKeyHashMap};

use crate::atom_base::*;
use crate::dispatch_atom::*;
use crate::getter_setter::*;
use crate::primitive_atom::*;
use crate::subscription_set::SubscriptionSet;

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
        atom: &PrimitiveAtom<T>,
        arg: Arc<T>,
    ) {
        let _ = self.mutex.lock();
        {
            // limit this borrow to just the check
            let map = self.map.borrow();
            let cached_value = map.get(&*atom.get_id()).and_then(|v| v.downcast_ref::<T>());
            if cached_value.is_some_and(|v| *v == *arg.clone()) {
                return;
            }
        }

        self.map.borrow_mut().insert(atom.get_id().clone(), arg);

        self.deps_manager.propagate_stale(atom.get_id().clone());

        if let Some(closures) = self.subs.borrow().get(&atom.get_id()) {
            closures.notify(&());
        }
    }

    pub fn set<Arg: PartialEq + 'static>(self: Arc<Self>, atom: &DispatchAtom<Arg>, arg: Arc<Arg>) {
        let _ = self.mutex.lock();
        let mut setter = Setter::new(self.clone());
        (atom.dispatch)(&mut setter, arg);
    }

    pub fn set_and_return<Arg: PartialEq + 'static, Return>(
        self: Arc<Self>,
        atom: &DispatchWithReturnAtom<Arg, Return>,
        arg: Arc<Arg>,
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

    pub(crate) fn update_deps(
        &self,
        atom_id: Arc<AtomId>,
        tracked: Rc<RefCell<WeakKeyHashMap<Weak<AtomId>, Box<dyn Fn() -> bool>>>>,
        getter_id: &usize,
    ) {
        return self.deps_manager.update_deps(atom_id, tracked, getter_id);
    }

    #[cfg(test)]
    pub(crate) fn get_map(
        &self,
    ) -> Rc<RefCell<WeakKeyHashMap<Weak<AtomId>, Arc<dyn Any + Send + Sync>>>> {
        self.map.clone()
    }
}
// We trust that with the Reentrant mutex on all public methods, it's Send + Sync
unsafe impl Send for JotaiStore {}
unsafe impl Sync for JotaiStore {}

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
