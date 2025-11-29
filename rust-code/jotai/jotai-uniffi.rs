extern crate jotai;

use jotai::{Atom, JotaiStore};
use std::{cell::RefCell, rc::Rc};

uniffi::setup_scaffolding!();

#[uniffi::export]
pub fn print_and_add(a: i32, b: i32) -> i32 {
    println!("Hello, World!");
    a + b
}
#[uniffi::export]
pub fn get_counter() -> u32 {
    DEFAULT_STORE.with(|store_ref| {
        let store = store_ref.borrow_mut();
        COUNTER_ATOM.with(|counter_atom_ref| {
            let counter_atom = counter_atom_ref.borrow();
            *store.get(&*counter_atom)
        })
    })
}

thread_local! {
    pub static DEFAULT_STORE: RefCell<JotaiStore> = RefCell::new(JotaiStore::new());
    pub static COUNTER_ATOM: RefCell<Rc<Atom<u32>>> = RefCell::new(Rc::new(Atom::new(10)));
}
