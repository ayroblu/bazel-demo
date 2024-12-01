use lang_move_lib::edit;
use lang_move_lib::types::Input;
use lang_move_lib::types::Lang;
use lang_move_lib::types::MoveAction;

macro_rules! edit_general_tests {
    ($($name:ident: $value:expr,)*) => {
    $(
        #[test]
        fn $name() {
            let (source, line, column, action, expected) = $value;
            assert_eq!(expected, edit(&Input {
                source,
                line,
                column,
                action,
                lang: Lang::TypeScript,
            }));
        }
    )*
    }
}

edit_general_tests! {
    move_right:
        (PARAM.to_string(), 0, 13, MoveAction::Next, Some(PARAM_SWAP.to_string())),
    move_left:
        (PARAM.to_string(), 0, 23, MoveAction::Prev, Some(PARAM_SWAP.to_string())),
    do_nothing_right:
        (PARAM.to_string(), 0, 23, MoveAction::Next, None),
    do_nothing_left:
        (PARAM.to_string(), 0, 13, MoveAction::Prev, None),
}

const PARAM: &str = "console.log('first', 'second')";
const PARAM_SWAP: &str = "console.log('second', 'first')";
