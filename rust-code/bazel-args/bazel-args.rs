use lib::get_args;
use std::process::exit;
use std::process::Command;

fn main() {
    let args: Vec<String> = get_args();
    let status = Command::new("bazel")
        .args(args)
        .status()
        .expect("failed to execute process");
    if let Some(code) = status.code() {
        exit(code);
    }
}
