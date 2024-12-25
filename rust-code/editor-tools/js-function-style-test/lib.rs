use const_format::formatcp;
use lib::edit;
use lib::types::ConvertAction;
use lib::types::Input;

macro_rules! edit_tests {
    ($($name:ident: $value:expr,)*) => {
    $(
        #[test]
        fn $name() {
            let (source, action, expected) = $value;
            assert_eq!(expected, edit(&Input {
                source,
                line: 0,
                column: 0,
                action,
            }).unwrap());
        }
    )*
    }
}

edit_tests! {
    converts_function_to_block:
        (A.to_string(), ConvertAction::ArrowBlock, A_BLOCK.to_string()),
    converts_function_to_inline:
        (A.to_string(), ConvertAction::ArrowInline, A_INLINE.to_string()),
    converts_block_to_function:
        (A_BLOCK.to_string(), ConvertAction::Function, A.to_string()),
    converts_block_to_inline:
        (A_BLOCK.to_string(), ConvertAction::ArrowInline, A_INLINE.to_string()),
    converts_inline_to_function:
        (A_INLINE.to_string(), ConvertAction::Function, A_RETURN.to_string()),
    converts_inline_to_block:
        (A_INLINE.to_string(), ConvertAction::ArrowBlock, A_BLOCK_RETURN.to_string()),
    converts_function_return_to_block:
        (A_RETURN.to_string(), ConvertAction::ArrowBlock, A_BLOCK_RETURN.to_string()),
    converts_function_return_to_inline:
        (A_RETURN.to_string(), ConvertAction::ArrowInline, A_INLINE.to_string()),
}

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
            }).expect("Did not return a result from edit"));
        }
    )*
    }
}

edit_general_tests! {
    converts_map_block_to_inline:
        (R.to_string(), 1, 0, ConvertAction::ArrowInline, R_INLINE.to_string()),
    converts_map_function_to_inline:
        (R_FUNC.to_string(), 1, 0, ConvertAction::ArrowInline, R_INLINE.to_string()),
    converts_map_function_to_block:
        (R_FUNC.to_string(), 1, 0, ConvertAction::ArrowBlock, R.to_string()),
    converts_map_inline_to_function:
        (R_INLINE.to_string(), 0, 10, ConvertAction::Function, R_FUNC.to_string()),

    converts_obj_block_to_function:
        (OBJ_BLOCK.to_string(), 1, 5, ConvertAction::Function, OBJ_METHOD.to_string()),
    converts_obj_inline_to_function:
        (OBJ_INLINE.to_string(), 1, 5, ConvertAction::Function, OBJ_METHOD_FROM_INLINE.to_string()),
    converts_obj_function_to_block:
        (OBJ_METHOD.to_string(), 1, 5, ConvertAction::ArrowBlock, OBJ_BLOCK.to_string()),
    converts_obj_function_to_inline:
        (OBJ_METHOD.to_string(), 1, 5, ConvertAction::ArrowInline, OBJ_INLINE.to_string()),
}

#[test]
fn it_converts_example_block_to_function() {
    let result = edit(&Input {
        source: EXAMPLE.to_string(),
        line: 5,
        column: 5,
        action: ConvertAction::Function,
    })
    .unwrap();
    let expected = format!("\n{}\n{}\n{}\n{}\n", A, B_FUNC, C, D);
    assert_eq!(result, expected.to_string());
}

const A: &str = "function a(v: string) {
    console.log('a', v);
}";
const A_BLOCK: &str = "const a = (v: string) => {
    console.log('a', v);
}";
const A_INLINE: &str = "const a = (v: string) => console.log('a', v)";

const A_RETURN: &str = "function a(v: string) {
    return console.log('a', v);
}";
const A_BLOCK_RETURN: &str = "const a = (v: string) => {
    return console.log('a', v);
}";
const R: &str = "list.map((item: string): string => {
    return console.log('b2');
})";
const R_FUNC: &str = "list.map(function (item: string): string {
    return console.log('b2');
})";
const R_INLINE: &str = "list.map((item: string): string => console.log('b2'))";

const B: &str = "const b = () => {
    console.log('b');
    console.log('b2');
}";
const B_FUNC: &str = "function b() {
    console.log('b');
    console.log('b2');
}";

const C: &str = "const c = () => console.log('c')";

const D: &str = "const d = function() {
    console.log('b');
}";

const EXAMPLE: &str = formatcp!("\n{}\n{}\n{}\n{}\n", A, B, C, D);

const OBJ_BLOCK: &str = "const a = {
    item: (): Type => {
        console.log('item')
    },
}";
const OBJ_METHOD: &str = "const a = {
    item(): Type {
        console.log('item')
    },
}";
const OBJ_INLINE: &str = "const a = {
    item: (): Type => console.log('item'),
}";
const OBJ_METHOD_FROM_INLINE: &str = "const a = {
    item(): Type {
    return console.log('item');
},
}";
