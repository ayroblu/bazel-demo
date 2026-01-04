use std::cell::RefCell;
use std::rc::Rc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Weak};

use weak_table::WeakKeyHashMap;

static NEXT_CLOSURE_ID: AtomicUsize = AtomicUsize::new(0);
fn new_closure_id() -> usize {
    NEXT_CLOSURE_ID.fetch_add(1, Ordering::Relaxed)
}
pub(crate) struct SubscriptionSet<T> {
    callbacks: Rc<RefCell<WeakKeyHashMap<Weak<usize>, Box<dyn Fn(&T)>>>>,
}
impl<T: 'static> SubscriptionSet<T> {
    pub(crate) fn new() -> Self {
        Self {
            callbacks: Rc::new(RefCell::new(WeakKeyHashMap::new())),
        }
    }
    pub(crate) fn sub<F: Fn(&T) + 'static>(&self, f: F) -> Box<dyn FnOnce()> {
        let closure_id = Arc::new(new_closure_id());
        let callbacks = self.callbacks.clone();
        self.callbacks
            .borrow_mut()
            .insert(closure_id.clone(), Box::new(f));
        return Box::new(move || {
            callbacks.borrow_mut().remove(&closure_id);
        });
    }
    pub(crate) fn notify(&self, v: &T) {
        self.callbacks.borrow().values().for_each(|f| f(v));
    }
    pub(crate) fn is_empty(&self) -> bool {
        self.callbacks.borrow().keys().count() == 0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
