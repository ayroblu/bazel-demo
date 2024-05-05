import Parser from "tree-sitter";

export type TraverseQuery = {
  [nodeType: string]: (
    node: Parser.SyntaxNode,
  ) => void | { skip: boolean } | (() => void);
};
// Simple implementation but slower than with cursor
// export function traverse(node: Parser.SyntaxNode, query: TraverseQuery): void {
//   const result = query[node.type]?.(node);
//   if (typeof result === "object" && result?.skip) return;
//   for (const child of node.namedChildren) {
//     traverse(child, query);
//   }
//   if (typeof result === "function") result();
// }

export function traverseWithCursor(
  cursor: Parser.TreeCursor,
  ...queries: TraverseQuery[]
): void {
  const callbacks: (() => void)[] = [];
  for (const query of queries) {
    const result = query[cursor.nodeType]?.(cursor.currentNode);
    if (typeof result === "object" && result?.skip) return;
    if (typeof result === "function") callbacks.push(result);
  }
  if (cursor.gotoFirstChild()) {
    do {
      traverseWithCursor(cursor, ...queries);
    } while (cursor.gotoNextSibling());
    cursor.gotoParent();
  }
  callbacks.forEach((cb) => cb());
}