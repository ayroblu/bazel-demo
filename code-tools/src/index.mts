import Parser from "tree-sitter";
import ts from "tree-sitter-typescript";
import { traverseWithCursor } from "./traverse.mjs";
import { buildTraverseQuery } from "./query.mjs";
import { isMainScript } from "./misc-utils.mjs";
const { tsx } = ts;

if (isMainScript(import.meta.url)) {
  const parser = new Parser();
  parser.setLanguage(tsx);

  const sourceCode = "let x = 1; console.log(x);";
  const tree = parser.parse(sourceCode);
  const query = {
    type: "expression_statement",
    capture: "expression",
    items: [
      {
        type: "call_expression",
        items: [{ field: "function", capture: "callName" }],
      },
    ],
  } as const;
  const traverseQuery = buildTraverseQuery(query, (captures) => {
    console.log(captures);
  });
  // console.log(tree.rootNode.toString());
  traverseWithCursor(tree.walk(), traverseQuery);
}