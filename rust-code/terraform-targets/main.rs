use regex::Regex;
use std::io::{self, BufRead};

fn main() {
    let stdin = io::stdin();
    let re = Regex::new(r#"^(?:(resource) +"(\w+)" +"(\w+)" *\{|(module) +"(\w+)" +\{)$"#).unwrap();
    let mut is_first = true;
    for line in stdin.lock().lines() {
        let line_text = line.unwrap();
        re.captures_iter(&line_text).next().iter().for_each(|cap| {
            let mut cap_iter = cap.iter();
            cap_iter.next();
            let parts = cap_iter
                .flat_map(|opt| opt.map(|item| item.as_str()))
                .collect::<Vec<&str>>()
                .join(".");
            if !is_first {
                print!(" ");
            } else {
                is_first = false;
            }
            print!("-target={}", parts);
        })
    }
}
