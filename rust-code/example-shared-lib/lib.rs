uniffi::setup_scaffolding!();

#[uniffi::export]
pub fn print_and_add(a: i32, b: i32) -> i32 {
    println!("Hello, World!");
    a + b
}
