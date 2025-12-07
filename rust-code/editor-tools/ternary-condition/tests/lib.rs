use ternary_condition_lib::edit;
use ternary_condition_lib::types::Action;
use ternary_condition_lib::types::Input;
use ternary_condition_lib::types::Lang;

macro_rules! edit_general_tests {
    ($($name:ident: $value:expr,)*) => {
    $(
        #[test]
        fn $name() {
            let (source, lang, (line, column), action, expected) = $value;
            assert_eq!(edit(&Input { source, line, column, action, lang }), expected);
        }
    )*
    }
}
macro_rules! skipped_tests {
    ($($name:ident: $value:expr,)*) => {
    $(
        #[test]
        #[ignore = "skipped"]
        fn $name() {
            let (source, lang, (line, column), action, expected) = $value;
            assert_eq!(edit(&Input { source, line, column, action, lang }), expected);
        }
    )*
    }
}

edit_general_tests! {
    js_condition_to_ternary:
        (JS_CONDITION.to_string(), Lang::TypeScript, (0, 0), Action::Ternary, Some(JS_TERNARY.to_string())),
    js_ternary_to_condition:
        (JS_TERNARY.to_string(), Lang::TypeScript, (0, 10), Action::Condition, Some(JS_CONDITION.to_string())),
    js_ternary_resolve_true:
        (JS_TERNARY.to_string(), Lang::TypeScript, (0, 10), Action::ResolveTrue, Some("return 1".to_string())),
    js_ternary_resolve_false:
        (JS_TERNARY.to_string(), Lang::TypeScript, (0, 10), Action::ResolveFalse, Some("return (a === c) ? 2 : 3".to_string())),
    js_cond_resolve_true:
        (JS_CONDITION.to_string(), Lang::TypeScript, (0, 10), Action::ResolveTrue, Some("return 1;".to_string())),
    js_cond_resolve_false:
        (JS_CONDITION.to_string(), Lang::TypeScript, (0, 10), Action::ResolveFalse, Some("if (a === c) {
    return 2;
} else {
    return 3;
}".to_string())),
    js_cond_simple_resolve_false:
        (JS_CONDITION_SIMPLE.to_string(), Lang::TypeScript, (0, 10), Action::ResolveFalse, Some("something();\nreturn 3;".to_string())),

    rust_cond_resolve_true:
        (RUST_CONDITION.to_string(), Lang::Rust, (0, 5), Action::ResolveTrue, Some("1".to_string())),
    rust_cond_resolve_false:
        (RUST_CONDITION.to_string(), Lang::Rust, (0, 5), Action::ResolveFalse, Some("if a == c {
    2
} else {
    3
}".to_string())),
    rust_cond_simple_resolve_false:
        (RUST_CONDITION_SIMPLE.to_string(), Lang::Rust, (0, 5), Action::ResolveFalse, Some("something();\n3".to_string())),

    scala_cond_resolve_true:
        (SCALA_CONDITION.to_string(), Lang::Scala, (0, 5), Action::ResolveTrue, Some("1".to_string())),
    scala_cond_resolve_false:
        (SCALA_CONDITION.to_string(), Lang::Scala, (0, 5), Action::ResolveFalse, Some("if (a == c) {
    2
} else {
    3
}".to_string())),
    scala_cond_simple_resolve_false:
        (SCALA_CONDITION_SIMPLE.to_string(), Lang::Scala, (0, 5), Action::ResolveFalse, Some("something()\n3".to_string())),

    go_cond_resolve_true:
        (GO_CONDITION.to_string(), Lang::Go, (0, 5), Action::ResolveTrue, Some("1".to_string())),
    go_cond_resolve_false:
        (GO_CONDITION.to_string(), Lang::Go, (0, 5), Action::ResolveFalse, Some("if a == c {
    2
} else {
    3
}".to_string())),
    go_cond_simple_resolve_false:
        (GO_CONDITION_SIMPLE.to_string(), Lang::Go, (0, 5), Action::ResolveFalse, Some("something()\n3".to_string())),
}
skipped_tests! {
    swift_condition_to_ternary:
        (SWIFT_CONDITION.to_string(), Lang::Swift, (0, 0), Action::Ternary, Some(SWIFT_TERNARY.to_string())),
    swift_ternary_to_condition:
        (SWIFT_TERNARY.to_string(), Lang::Swift, (0, 10), Action::Condition, Some(SWIFT_CONDITION.to_string())),
    swift_cond_resolve_true:
        (SWIFT_CONDITION.to_string(), Lang::Swift, (0, 5), Action::ResolveTrue, Some("1".to_string())),
    swift_cond_resolve_false:
        (SWIFT_CONDITION.to_string(), Lang::Swift, (0, 5), Action::ResolveFalse, Some("if a == c {
    2
} else {
    3
}".to_string())),
}

const JS_CONDITION: &str = "if (a === b) {
    return 1;
} else if (a === c) {
    return 2;
} else {
    return 3;
}";
const JS_CONDITION_SIMPLE: &str = "if (a === b) {
    return 1;
} else {
    something();
    return 3;
}";
const JS_TERNARY: &str = "return (a === b) ? 1 : (a === c) ? 2 : 3";

const RUST_CONDITION: &str = "if a == b {
    1
} else if a == c {
    2
} else {
    3
}";
const RUST_CONDITION_SIMPLE: &str = "if a == b {
    1
} else {
    something();
    3
}";

const SWIFT_CONDITION: &str = "if a == b {
    return 1
} else if a == c {
    return 2
} else {
    return 3
}";
const SWIFT_TERNARY: &str = "return a == b ? 1 : a == c ? 2 : 3";

const SCALA_CONDITION: &str = "if (a == b) {
    1
} else if (a == c) {
    2
} else {
    3
}";
const SCALA_CONDITION_SIMPLE: &str = "if (a == b) {
    1
} else {
    something()
    3
}";

const GO_CONDITION: &str = "if err := f(); err != nil {
    1
} else if a == c {
    2
} else {
    3
}";
const GO_CONDITION_SIMPLE: &str = "if err := f(); err != nil {
    1
} else {
    something()
    3
}";
