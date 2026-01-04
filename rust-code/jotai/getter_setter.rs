use std::cell::RefCell;
use std::rc::Rc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Weak};

use weak_table::WeakKeyHashMap;

use crate::atom_base::{AtomId, ReadAtom};
use crate::dispatch_atom::{DispatchAtom, DispatchWithReturnAtom};
use crate::jotai_store::JotaiStore;
use crate::primitive_atom::PrimitiveAtom;

static NEXT_GETTER_ID: AtomicUsize = AtomicUsize::new(0);
fn new_getter_id() -> usize {
    NEXT_GETTER_ID.fetch_add(1, Ordering::Relaxed)
}
pub struct Getter {
    pub(crate) id: usize,
    atom_id: Arc<AtomId>,
    store: Arc<JotaiStore>,
    tracked: Rc<RefCell<WeakKeyHashMap<Weak<AtomId>, Box<dyn Fn() -> bool>>>>,
}
impl Getter {
    pub(crate) fn new(store: Arc<JotaiStore>, atom_id: Arc<AtomId>) -> Self {
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
            .update_deps(self.atom_id.clone(), self.tracked.clone(), &self.id);
        return result;
    }
}
pub struct Setter {
    store: Arc<JotaiStore>,
}
impl Setter {
    pub(crate) fn new(store: Arc<JotaiStore>) -> Self {
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
