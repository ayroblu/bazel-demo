import Parser from "tree-sitter";
import ts from "tree-sitter-typescript";
import { traverseWithCursor, type TraverseQuery } from "../../traverse.js";
import { getField } from "../../query.js";
import { runEdits, type CodeEdit } from "../../codemod.js";
import { pred } from "../utils.js";

const { tsx } = ts;

export function unusedVariables(source: string) {
  const parser = new Parser();
  parser.setLanguage(tsx);

  const tree = parser.parse(source);

  const nodesToRemove: Parser.SyntaxNode[] = [];
  const scopedVariables: {
    [key: string]: { node: Parser.SyntaxNode; counter: number };
  }[] = [{}];

  const skipDecNodes = new Set();
  function handleLeavingScope() {
    const scope = scopedVariables.pop();
    if (scope) {
      // consider: `const a = 1, b = 1;`
      // if parent has only one child, then removable
      // if parent two children, collect counter of removals
      const counterMap = new Map<
        Parser.SyntaxNode,
        {
          counter: number;
          parentNode: Parser.SyntaxNode;
          childNodes: Set<Parser.SyntaxNode>;
        }
      >();
      Object.entries(scope).forEach(([_, value]) => {
        if (value.counter === 0) {
          const parent = value.node.parent;
          if (parent) {
            const c = counterMap.get(parent);
            const childNodes = [value.node];
            const nextComma = pred(
              value.node.nextSibling,
              (v) => v?.type === ",",
            );
            const prevComma = pred(
              value.node.previousSibling,
              (v) => v?.type === ",",
            );
            if (prevComma) {
              childNodes.unshift(prevComma);
            } else if (nextComma) {
              childNodes.push(nextComma);
            }
            if (c) {
              c.counter += 1;
              childNodes.forEach((n) => c.childNodes.add(n));
            } else {
              counterMap.set(parent, {
                parentNode: parent,
                childNodes: new Set(childNodes),
                counter: 1,
              });
            }
          }
        }
      });
      for (const { counter, parentNode, childNodes } of counterMap.values()) {
        if (parentNode.namedChildren.length === counter) {
          if (skipDecNodes.has(parentNode)) return;
          nodesToRemove.push(parentNode);
        } else {
          nodesToRemove.push(...childNodes);
        }
      }
    }
  }
  const traverseQuery: TraverseQuery = {
    for_statement: (node) => {
      const init = getField(node, "initializer");
      if (init) {
        skipDecNodes.add(init);
      }
    },
    variable_declarator: (node) => {
      const lastScope = scopedVariables.at(-1)!;
      const name = getField(node, "name")?.text;
      if (name) {
        if (lastScope[name]) {
          throw new Error("redeclaration of identifier: " + name);
        }
        lastScope[name] = {
          node,
          counter: 0,
        };
      }
      return { skip: true };
    },
    identifier: (node) => {
      const identifier = node.text;
      const scope = scopedVariables.findLast((scope) => scope[identifier]);
      if (scope) {
        scope[identifier].counter += 1;
      }
    },
    statement_block: () => {
      // Assume lexical scope is encapsulated by statement_block
      scopedVariables.push({});
      return () => {
        handleLeavingScope();
      };
    },
  };
  traverseWithCursor(tree.walk(), traverseQuery);
  handleLeavingScope();

  const edits: CodeEdit[] = nodesToRemove.map((node) => ({
    startIndex: node.startIndex,
    endIndex: node.endIndex,
    newText: "",
  }));
  const result = runEdits(source, edits);
  return result;
}
