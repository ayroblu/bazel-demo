import Parser from "tree-sitter";
import ts from "tree-sitter-typescript";
import { traverseWithCursor } from "../../traverse.js";
import { runEdits, type CodeEdit } from "../../codemod.js";
import { sortBy } from "../utils.js";
import { ancestor } from "../treesitter-utils.js";
import { getResolvedIdentifiers } from "./ast-utils/resolve-identifiers.js";
import { isExported } from "./ast-utils/ast-utils.js";

const { tsx } = ts;

export function unusedVariables(source: string) {
  const parser = new Parser();
  parser.setLanguage(tsx);

  const tree = parser.parse(source);

  const { declarationsQuery, identifierMap } = getResolvedIdentifiers();
  traverseWithCursor(tree.walk(), declarationsQuery);
  const reverseMap = new Map<Parser.SyntaxNode, number>();
  for (const value of identifierMap.values()) {
    const declarator = ancestor(value, (n) => n === "variable_declarator");
    if (!declarator) continue;
    if (isExported(declarator)) continue;
    const counter = reverseMap.get(declarator) ?? 0;
    reverseMap.set(declarator, counter + 1);
  }
  const nodesToRemoveSet = new Set<Parser.SyntaxNode>();
  const nodesToCheckSet = new Set<Parser.SyntaxNode>();
  for (const [key, counter] of reverseMap) {
    if (counter === 1) {
      nodesToRemoveSet.add(key);
      if (key.parent) {
        nodesToCheckSet.add(key.parent);
      }
    }
  }
  for (const node of nodesToCheckSet) {
    if (node.namedChildren.every((c) => nodesToRemoveSet.has(c))) {
      for (const n of node.namedChildren) {
        nodesToRemoveSet.delete(n);
      }
      nodesToRemoveSet.add(node);
    } else {
      for (const n of node.namedChildren) {
        if (nodesToRemoveSet.has(n)) {
          const prev = n.previousSibling;
          if (prev && prev.type === ",") {
            nodesToRemoveSet.add(prev);
          } else {
            const next = n.nextSibling;
            if (next && next.type === ",") {
              nodesToRemoveSet.add(next);
            }
          }
        }
      }
    }
  }
  const nodesToRemove = [...nodesToRemoveSet];
  nodesToRemove.sort(sortBy((a) => a.startIndex));

  const edits: CodeEdit[] = nodesToRemove.map((node) => ({
    startIndex: node.startIndex,
    endIndex: node.endIndex,
    newText: "",
  }));
  const result = runEdits(source, edits);
  return result;
}
