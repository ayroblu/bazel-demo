use std::hash::{Hash, Hasher};
use std::sync::Arc;

use crate::atom_base::{Atom, AtomId, ReadAtom};
use crate::getter_setter::Getter;

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
