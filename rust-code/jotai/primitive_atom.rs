use std::hash::{Hash, Hasher};
use std::sync::Arc;

use crate::atom_base::*;
use crate::getter_setter::Getter;

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
