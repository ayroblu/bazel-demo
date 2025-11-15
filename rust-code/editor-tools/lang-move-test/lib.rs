use lang_move_lib::edit;
use lang_move_lib::types::Input;
use lang_move_lib::types::Lang;
use lang_move_lib::types::MoveAction;

macro_rules! edit_general_tests {
    ($($name:ident: $value:expr,)*) => {
    $(
        #[test]
        fn $name() {
            let (lang, source, line, column, action, expected) = $value;
            assert_eq!(expected, edit(&Input {
                source,
                line,
                column,
                action,
                lang,
            }));
        }
    )*
    }
}

edit_general_tests! {
    move_right:
        (Lang::TypeScript, PARAM.to_string(), 0, 13, MoveAction::Next, Some(PARAM_SWAP.to_string())),
    move_left:
        (Lang::TypeScript, PARAM.to_string(), 0, 23, MoveAction::Prev, Some(PARAM_SWAP.to_string())),
    do_nothing_right:
        (Lang::TypeScript, PARAM.to_string(), 0, 23, MoveAction::Next, None),
    do_nothing_left:
        (Lang::TypeScript, PARAM.to_string(), 0, 13, MoveAction::Prev, None),
    // move_right_swift:
    //     (Lang::Swift, SWIFT_STRUCT.to_string(), 3, 18, MoveAction::Next, Some(SWIFT_STRUCT_SWAP.to_string())),
    // move_left_swift:
    //     (Lang::Swift, SWIFT_STRUCT_SWAP.to_string(), 3, 28, MoveAction::Prev, Some(SWIFT_STRUCT.to_string())),
}

const PARAM: &str = "console.log('first', 'second')";
const PARAM_SWAP: &str = "console.log('second', 'first')";
const SWIFT_STRUCT: &str = "struct S {
    let a: Int
    let b: Int
    init (a: Int = 0, b: Int) {
        self.a = a
        self.b = b
    }
}";
const SWIFT_STRUCT_SWAP: &str = "struct S {
    let a: Int
    let b: Int
    init (b: Int, a: Int = 0) {
        self.a = a
        self.b = b
    }
}";
