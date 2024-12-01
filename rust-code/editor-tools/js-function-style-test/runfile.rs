use runfiles::{rlocation, Runfiles};

/// https://github.com/bazelbuild/rules_rust/blob/ba6af156465ee5d183e41f04a07645ce564f6c67/tools/runfiles/runfiles.rs#L1-L31
pub fn runfile_path() -> String {
    let r = Runfiles::create().unwrap();
    let path = rlocation!(
        r,
        "_main/rust-code/editor-tools/js-function-style/js-function-style"
    )
    .expect("Failed to locate runfile");
    path.to_str().unwrap().to_string()
}
