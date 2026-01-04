use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;

use crate::getter_setter::Getter;

// Global, thread-safe counter
static NEXT_ID: AtomicUsize = AtomicUsize::new(0);
fn new_id() -> usize {
    NEXT_ID.fetch_add(1, Ordering::Relaxed)
}

pub trait Atom {
    fn get_id(&self) -> Arc<AtomId>;
}
pub trait ReadAtom<T>: Atom {
    fn get_read(&self) -> &Box<dyn Fn(&mut Getter) -> T + Send + Sync>;
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct AtomId(usize);
impl AtomId {
    pub(crate) fn new() -> Self {
        Self(new_id())
    }
}
