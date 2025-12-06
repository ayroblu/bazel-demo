use func_del_lib::edit;
use func_del_lib::types::Action;
use func_del_lib::types::Input;

macro_rules! edit_func_del_tests {
    ($($name:ident: $value:expr,)*) => {
    $(
        #[test]
        fn $name() {
            let (source, (line, column), expected) = $value;
            assert_eq!(edit(&Input { source, line, column, action: Action::FuncDel }), expected);
        }
    )*
    }
}

edit_func_del_tests! {
    remove_first:
        (NESTED_FUNCTION.to_string(), (0, 0), Some(WITHOUT_FIRST.to_string())),
    remove_second:
        (NESTED_FUNCTION.to_string(), (1, 5), Some(WITHOUT_SECOND.to_string())),
    remove_third:
        (NESTED_FUNCTION.to_string(), (2, 17), Some(WITHOUT_THIRD.to_string())),
    self_test:
        (SELF_TEST.to_string(), (3, 10), Some(SELF_RESULT.to_string())),
}

const NESTED_FUNCTION: &str = "first {
    second.something(
        third::<>(value)
    )
}";
const WITHOUT_FIRST: &str = "second.something(
        third::<>(value)
    )";
const WITHOUT_SECOND: &str = "first {
    third::<>(value)
}";
const WITHOUT_THIRD: &str = "first {
    second.something(
        value
    )
}";
const SELF_TEST: &str = "
edit_func_del_tests! {
    remove_first:
        (NESTED_FUNCTION.to_string(), (0, 0), Some(WITHOUT_FIRST.to_string())),
}
";
const SELF_RESULT: &str = "
edit_func_del_tests! {
    remove_first:
        (, (0, 0), Some(WITHOUT_FIRST.to_string())),
}
";
