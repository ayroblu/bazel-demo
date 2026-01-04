use std::hash::{Hash, Hasher};
use std::sync::Arc;

use crate::atom_base::*;
use crate::getter_setter::Setter;

pub struct DispatchAtom<Arg> {
    id: Arc<AtomId>,
    pub(crate) dispatch: Box<dyn Fn(&mut Setter, &Arg)>,
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
    pub(crate) dispatch: Box<dyn Fn(&mut Setter, &Arg) -> Return>,
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
