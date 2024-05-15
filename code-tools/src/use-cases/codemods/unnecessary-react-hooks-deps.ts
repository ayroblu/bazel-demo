import Parser from "tree-sitter";
import ts from "tree-sitter-typescript";
import { traverseWithCursor, type TraverseQuery } from "../../traverse.js";
import { runEdits, type CodeEdit } from "../../codemod.js";
import { getField } from "../../query.js";
import { getResolvedIdentifiers } from "./ast-utils/resolve-identifiers.js";
import { pred } from "../utils.js";

const { tsx } = ts;

const reactHooks = ["useCallback", "useMemo", "useEffect", "useLayoutEffect"];
const reactHooksSet = new Set(reactHooks);
export function unnecessaryReactHooksDeps(source: string) {
  const parser = new Parser();
  parser.setLanguage(tsx);

  const tree = parser.parse(source);
  const { declarationsQuery, identifierMap } = getResolvedIdentifiers();

  const hookFuncs: {
    node: Parser.SyntaxNode;
    callback: Parser.SyntaxNode;
    deps: Parser.SyntaxNode[];
  }[] = [];
  const traverseQuery: TraverseQuery = {
    call_expression: (node) => {
      const name = getField(node, "function")?.text;
      if (!name) return;
      if (
        reactHooksSet.has(name) ||
        reactHooks.some((n) => name.endsWith(`.${n}`))
      ) {
        const args = getField(node, "arguments");
        const callback = args?.namedChildren[0];
        const depsArr = args?.namedChildren[1];
        if (depsArr?.type === "array" && callback) {
          hookFuncs.push({ node, callback, deps: depsArr.namedChildren });
        }
      }
    },
  };
  traverseWithCursor(tree.walk(), declarationsQuery, traverseQuery);

  function resolveNode(
    node: Parser.SyntaxNode,
  ): boolean | Parser.SyntaxNode | void {
    switch (node.type) {
      case "true":
        return true;
      case "false":
        return false;
      case "parenthesized_expression":
        return resolveNode(node.namedChildren[0]);
      case "identifier": {
        const decNode = identifierMap.get(node);
        if (!decNode) return;
        return resolveNode(decNode);
      }
      default:
    }
  }

  const edits: CodeEdit[] = hookFuncs.flatMap(({ callback, deps }) => {
    const edits: CodeEdit[] = [];
    const removedCommas = new Set<Parser.SyntaxNode>();
    const addCommaEdit = (node: Parser.SyntaxNode) => {
      if (!removedCommas.has(node)) {
        edits.push({
          startIndex: node.startIndex,
          endIndex: node.endIndex,
          newText: "",
        });
        removedCommas.add(node);
      }
    };
    for (const dep of deps) {
      if (dep.type !== "identifier") continue;
      let resolvedCallback = callback;
      if (resolvedCallback.type === "identifier") {
        const resolved = identifierMap.get(resolvedCallback);
        if (resolved) {
          resolvedCallback = resolved;
        }
      }
      if (containsIdentifier(resolvedCallback, dep.text)) continue;
      const isPrimitive = typeof resolveNode(dep) === "boolean";
      if (!isPrimitive) continue;
      edits.push({
        startIndex: dep.startIndex,
        endIndex: dep.endIndex,
        newText: "",
      });
      const next = pred(dep.nextSibling, (n) => n?.type === ",");
      if (next) {
        addCommaEdit(next);
      }
    }
    return edits;
  });
  const result = runEdits(source, edits);
  return result;
}
function containsIdentifier(
  node: Parser.SyntaxNode,
  identifier: string,
): boolean {
  try {
    const shadowed = new Set<string>();
    const onIdentifier = (node: Parser.SyntaxNode) => {
      if (!shadowed.has(node.text) && node.text === identifier) {
        throw new Error("exit");
      }
    };
    const query: TraverseQuery = {
      variable_declarator: (node) => {
        const name = getField(node, "name");
        if (!name) return;
        if (name.type === "identifier") {
          shadowed.add(name.text);
        }
      },
      shorthand_property_identifier_pattern: (node) => {
        shadowed.add(node.text);
      },
      pair_pattern: (node) => {
        const name = getField(node, "value");
        if (!name) return;
        if (name.type === "identifier") {
          shadowed.add(node.text);
        }
      },
      identifier: onIdentifier,
      shorthand_property_identifier: onIdentifier,
    };
    traverseWithCursor(node.walk(), query);
  } catch {
    return true;
  }
  return false;
}
