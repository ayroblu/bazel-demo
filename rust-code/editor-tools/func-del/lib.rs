extern crate unicode_segmentation;

pub mod types;

use std::cell::RefCell;
use types::Input;
use unicode_segmentation::UnicodeSegmentation;

pub fn edit(input: &Input) -> Option<String> {
    let s = &input.source;
    let lines = s.lines().collect::<Vec<&str>>();
    let position = (input.line, input.column);
    let byte_pos = get_byte_pos(&lines, position);
    if let Some(true) = is_self_func(&lines, position) {
        let Some(byte_offset) = get_self_func_byte_pos(s, byte_pos) else {
            return None;
        };
        return replacement_with_offset_first_paren(s, byte_offset);
    } else if let Some(byte_offset) = get_parent_func_byte_pos(s, byte_pos) {
        return replacement_with_offset_first_paren(s, byte_offset);
    }
    None
}

fn replacement_with_offset_first_paren(s: &String, byte_offset: usize) -> Option<String> {
    let Some(starting_brace) = s.as_bytes().get(byte_offset) else {
        return None;
    };
    let Some(matching_brace) = Some(starting_brace).and_then(|c| match c {
        b'(' => Some(b')'),
        b'{' => Some(b'}'),
        b'[' => Some(b']'),
        b'<' => Some(b'>'),
        _ => None,
    }) else {
        return None;
    };
    let counter_ref = RefCell::new(0);
    // fairly standard find the matching brace with a counter algo
    let Some(end) = s
        .bytes()
        .enumerate()
        .skip(byte_offset + 1)
        .find(|(_, c)| {
            if *c == *starting_brace {
                let mut counter = counter_ref.borrow_mut();
                *counter += 1;
                return false;
            } else if *c == matching_brace {
                let mut counter = counter_ref.borrow_mut();
                if *counter == 0 {
                    return true;
                } else {
                    *counter -= 1;
                    return false;
                }
            }
            return false;
        })
        .map(|(i, _)| i)
    else {
        return None;
    };

    let is_angle = *starting_brace == b'<';
    // Special case for turbofish + generic: `collect::<Type>(param)`
    // We use the parens instead, and angle braces are just "text"
    if is_angle && s.as_bytes().get(end + 1).is_some_and(|c| *c == b'(') {
        return replacement_with_offset_first_paren(s, end + 1);
    }

    // from the relevant brace, go backwards until you reach the start of "method name"
    let Some(start) = s
        .bytes()
        .enumerate()
        .take(byte_offset)
        .rev()
        // '>': Generics + turbofish e.g. func<T>(param)
        .skip_while(|(_, c)| c.is_ascii_whitespace() || (!is_angle && matches!(*c, b'>')))
        .take_while(|(_, c)| {
            c.is_ascii_alphanumeric()
                || matches!(*c, b'_' | b'.' | b'-' | b':')
                || (!is_angle && matches!(*c, b'<'))
        })
        .last()
        .map(|(i, _)| i)
    else {
        return None;
    };
    let Some(text) = s.get((byte_offset + 1)..end).map(|t| t.trim().to_string()) else {
        return None;
    };
    return Some(replace(s, (start, end + 1), text));
}

fn is_self_func(lines: &Vec<&str>, position: (usize, usize)) -> Option<bool> {
    lines.get(position.0).map(|line| {
        line.graphemes(true)
            .skip(position.1)
            .take_while(|c| !matches!(*c, ")" | "}" | ">" | "]"))
            .find(|c| matches!(*c, "(" | "{" | "<" | "["))
            .is_some()
    })
}
fn get_self_func_byte_pos(s: &String, byte_pos: usize) -> Option<usize> {
    s.bytes()
        .enumerate()
        .skip(byte_pos)
        .take_while(|(_, c)| !matches!(*c, b')' | b'}' | b'>' | b']'))
        .find(|(_, c)| matches!(*c, b'(' | b'{' | b'<' | b'['))
        .map(|(i, _)| i)
}
fn get_parent_func_byte_pos(s: &String, byte_pos: usize) -> Option<usize> {
    s.bytes()
        .take(byte_pos)
        .enumerate()
        .rev()
        .take_while(|(_, c)| !matches!(*c, b')' | b'}' | b'>' | b']'))
        .find(|(_, c)| matches!(*c, b'(' | b'{' | b'<' | b'['))
        .map(|(i, _)| i)
}
fn get_byte_pos(lines: &Vec<&str>, position: (usize, usize)) -> usize {
    lines
        .into_iter()
        .take(position.0)
        .map(|line| line.len())
        .sum::<usize>()
        + position.0 // this is wrong for \r\n
        + lines
            .get(position.0)
            .map(|line| {
                line.graphemes(true)
                    .take(position.1)
                    .map(|c| c.len())
                    .sum::<usize>()
            })
            .unwrap_or(0)
}

fn replace(source_in: &String, position: (usize, usize), text: String) -> String {
    let mut source = source_in.clone();
    let (start, end) = position;
    source.replace_range(start..end, &text);
    source
}
