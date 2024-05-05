import Parser from "tree-sitter";
import ts from "tree-sitter-typescript";
import { isMainScript } from "../misc-utils.mjs";
import { traverseWithCursor } from "../traverse.mjs";
import { getField } from "../query.mjs";
const { tsx } = ts;

if (isMainScript(import.meta.url)) {
  const parser = new Parser();
  parser.setLanguage(tsx);

  const sourceCodes = [
    `
export function a(param: string, opt?: {} = {}) {
  //todo
}
`,
  ];
  for (const sourceCode of sourceCodes) {
    const tree = parser.parse(sourceCode);
    console.log(tree.rootNode.toString());
    traverseWithCursor(tree.walk(), {
      for_statement: (node) => {
        console.log(getField(node, "initializer")?.text);
      },
    });
  }
}