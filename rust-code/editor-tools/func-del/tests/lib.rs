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
        (NESTED_FUNCTION.to_string(), (2, 12), Some(WITHOUT_THIRD.to_string())),
    remove_third_inner:
        (NESTED_FUNCTION.to_string(), (2, 18), Some(WITHOUT_THIRD.to_string())),
    self_test:
        (SELF_TEST.to_string(), (3, 10), Some(SELF_RESULT.to_string())),
    nest_type_remove_first:
        (NESTED_TYPE.to_string(), (0, 1), Some(NESTED_TYPE_WITHOUT_FIRST.to_string())),
    nest_type_remove_second:
        (NESTED_TYPE.to_string(), (0, 8), Some(NESTED_TYPE_WITHOUT_SECOND.to_string())),
    nest_type_remove_third:
        (NESTED_TYPE.to_string(), (0, 14), Some(NESTED_TYPE_WITHOUT_THIRD.to_string())),
    nest_type_remove_third_inner:
        (NESTED_TYPE.to_string(), (0, 20), Some(NESTED_TYPE_WITHOUT_THIRD.to_string())),
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
const NESTED_TYPE: &str = "first<second<third<String>>>";
const NESTED_TYPE_WITHOUT_FIRST: &str = "second<third<String>>";
const NESTED_TYPE_WITHOUT_SECOND: &str = "first<third<String>>";
const NESTED_TYPE_WITHOUT_THIRD: &str = "first<second<String>>";
