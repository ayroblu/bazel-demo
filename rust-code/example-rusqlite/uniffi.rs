uniffi::setup_scaffolding!();

#[uniffi::export]
pub fn get_saved() -> Option<Vec<String>> {
    example_sqlite::get_saved()
}
