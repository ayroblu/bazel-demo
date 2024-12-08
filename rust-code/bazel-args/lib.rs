use std::env;

pub fn get_args() -> Vec<String> {
    let mut first = true;
    let args: Vec<String> = env::args()
        .skip(1)
        .flat_map(|arg| {
            if arg == "--" {
                first = false;
                return vec![arg];
            } else if !first || arg.starts_with("--") {
                return vec![arg];
            }
            first = false;
            return arg
                .split(":")
                .enumerate()
                .map(|(i, item)| -> String {
                    if i == 0 {
                        item.to_string()
                    } else {
                        format!("--config={}", item)
                    }
                })
                .collect::<Vec<String>>();
        })
        .collect();
    args
}
