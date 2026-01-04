mod atom_base;
mod primitive_atom;
pub use primitive_atom::*;
mod select_atom;
pub use select_atom::*;
mod dispatch_atom;
pub use dispatch_atom::*;
mod getter_setter;
use getter_setter::*;
mod jotai_store;
mod subscription_set;
pub use jotai_store::*;

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

#[cfg(test)]
mod tests {
    use std::sync::{Arc, LazyLock, Mutex};

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
            assert_eq!(store.get_map().borrow().keys().count(), 1);
        }
        assert_eq!(store.get_map().borrow().keys().count(), 0);
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
        let sub_counter = Arc::new(Mutex::new(0));
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
            move |_| *counter.lock().unwrap() += 1
        });
        assert_eq!(*d2_counter.lock().unwrap(), 1);
        assert_eq!(*sub_counter.lock().unwrap(), 0);
        assert_eq!(*store.clone().get(&*derivative2_atom), true);
        assert_eq!(*d2_counter.lock().unwrap(), 1);
        assert_eq!(*sub_counter.lock().unwrap(), 0);
        store
            .clone()
            .set_primitive(value_atom.clone(), Arc::new(11));
        assert_eq!(*d2_counter.lock().unwrap(), 1);
        assert_eq!(*sub_counter.lock().unwrap(), 0);
        store
            .clone()
            .set_primitive(value_atom.clone(), Arc::new(12));
        assert_eq!(*d2_counter.lock().unwrap(), 2);
        assert_eq!(*sub_counter.lock().unwrap(), 1);

        dispose();

        store
            .clone()
            .set_primitive(value_atom.clone(), Arc::new(11));
        assert_eq!(*d2_counter.lock().unwrap(), 2);
        assert_eq!(*sub_counter.lock().unwrap(), 1);
    }
}
