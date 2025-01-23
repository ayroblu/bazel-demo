use ternary_condition_lib::edit;
use ternary_condition_lib::types::Action;
use ternary_condition_lib::types::Input;
use ternary_condition_lib::types::Lang;

macro_rules! edit_general_tests {
    ($($name:ident: $value:expr,)*) => {
    $(
        #[test]
        fn $name() {
            let (source, line, column, action, expected) = $value;
            assert_eq!(edit(&Input {
                source,
                line,
                column,
                action,
                lang: Lang::TypeScript,
            }), expected);
        }
    )*
    }
}

edit_general_tests! {
    condition_to_ternary:
        (CONDITION.to_string(), 0, 0, Action::Ternary, Some(TERNARY.to_string())),
    ternary_to_condition:
        (TERNARY.to_string(), 0, 10, Action::Condition, Some(CONDITION.to_string())),
}

const CONDITION: &str = "if (a === b) {
    return 1;
} else if (a === c) {
    return 2;
} else {
    return 3;
}";
const TERNARY: &str = "return (a === b) ? 1 : (a === c) ? 2 : 3";
