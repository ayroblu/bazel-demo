import tree_sitter_python as tspython
from tree_sitter import Language, Parser
from python_code.example_lib.mylib import func

def max[T](arg: T) -> T:
    return arg

PY_LANGUAGE = Language(tspython.language(), "python")
parser = Parser()
parser.set_language(PY_LANGUAGE)
tree = parser.parse(
    bytes(
        """
def foo():
    if bar:
        baz()
""",
        "utf8",
    )
)
print(tree.root_node.sexp())
func()
