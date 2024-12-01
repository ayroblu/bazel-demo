use const_format::formatcp;
use lib::edit;
use lib::ConvertAction;
use lib::Input;

macro_rules! edit_tests {
    ($($name:ident: $value:expr,)*) => {
    $(
        #[test]
        fn $name() {
            let (source, action, expected) = $value;
            assert_eq!(expected, edit(Input {
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

#[test]
fn it_converts_example_block_to_function() {
    let result = edit(Input {
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
