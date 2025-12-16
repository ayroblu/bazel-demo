use std::sync::Arc;

uniffi::setup_scaffolding!();

#[uniffi::export]
pub fn print_and_add(a: i32, b: i32) -> i32 {
    println!("Hello, World!");
    a + b
}

#[uniffi::export]
pub fn subber(thing: Box<dyn ClosureCallback>) -> Arc<Cleanup> {
    thing.notif();
    return Arc::new(Cleanup {});
}

#[uniffi::export(callback_interface)]
pub trait ClosureCallback: Send + Sync + 'static {
    // notify is a reserved word in kotlin 🤦
    fn notif(&self);
}

#[derive(uniffi::Object)]
pub struct Cleanup;
#[uniffi::export]
impl Cleanup {
    fn dispose(&self) {
        println!("dispose!");
    }
}
