import Parser from "tree-sitter";

export function ancestor(
  node: Parser.SyntaxNode,
  matcher: (nodeType: string) => boolean,
): Parser.SyntaxNode | void {
  while (node?.parent) {
    node = node.parent;
    if (!node) {
      return;
    }
    if (matcher(node.type)) {
      return node;
    }
  }
}
