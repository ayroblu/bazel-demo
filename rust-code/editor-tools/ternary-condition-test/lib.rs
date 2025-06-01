use ternary_condition_lib::edit;
use ternary_condition_lib::types::Action;
use ternary_condition_lib::types::Input;
use ternary_condition_lib::types::Lang;

macro_rules! edit_general_tests {
    ($($name:ident: $value:expr,)*) => {
    $(
        #[test]
        fn $name() {
            let (source, lang, line, column, action, expected) = $value;
            assert_eq!(edit(&Input {
                source,
                line,
                column,
                action,
                lang,
            }), expected);
        }
    )*
    }
}

edit_general_tests! {
    js_condition_to_ternary:
        (JS_CONDITION.to_string(), Lang::TypeScript, 0, 0, Action::Ternary, Some(JS_TERNARY.to_string())),
    js_ternary_to_condition:
        (JS_TERNARY.to_string(), Lang::TypeScript, 0, 10, Action::Condition, Some(JS_CONDITION.to_string())),
    swift_condition_to_ternary:
        (SWIFT_CONDITION.to_string(), Lang::Swift, 0, 0, Action::Ternary, Some(SWIFT_TERNARY.to_string())),
    swift_ternary_to_condition:
        (SWIFT_TERNARY.to_string(), Lang::Swift, 0, 10, Action::Condition, Some(SWIFT_CONDITION.to_string())),
}

const JS_CONDITION: &str = "if (a === b) {
    return 1;
} else if (a === c) {
    return 2;
} else {
    return 3;
}";
const JS_TERNARY: &str = "return (a === b) ? 1 : (a === c) ? 2 : 3";
const SWIFT_CONDITION: &str = "if a == b {
    return 1
} else if a == c {
    return 2
} else {
    return 3
}";
const SWIFT_TERNARY: &str = "return a == b ? 1 : a == c ? 2 : 3";
