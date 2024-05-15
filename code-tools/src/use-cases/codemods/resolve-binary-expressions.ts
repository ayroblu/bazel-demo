import Parser from "tree-sitter";
import ts from "tree-sitter-typescript";
import { traverseWithCursor, type TraverseQuery } from "../../traverse.js";
import { getField } from "../../query.js";
import { runEdits, type CodeEdit } from "../../codemod.js";
import { getResolvedIdentifiers } from "./ast-utils/resolve-identifiers.js";

const { tsx } = ts;

export function resolveBinaryExpressions(source: string) {
  const parser = new Parser();
  parser.setLanguage(tsx);

  const { declarationsQuery, identifierMap } = getResolvedIdentifiers();
  const tree = parser.parse(source);
  const toCheckNodes: Parser.SyntaxNode[] = [];
  const traverseQuery: TraverseQuery = {
    binary_expression: (node) => {
      toCheckNodes.push(node);
    },
    unary_expression: (node) => {
      toCheckNodes.push(node);
    },
  };
  traverseWithCursor(tree.walk(), declarationsQuery, traverseQuery);
  const edits: CodeEdit[] = [];
  for (const node of toCheckNodes) {
    const lastEdit = edits.at(-1);
    if (lastEdit && lastEdit.endIndex > node.startIndex) continue;
    const resolved = resolveNode(node, identifierMap);
    if (typeof resolved === "boolean") {
      edits.push({
        startIndex: node.startIndex,
        endIndex: node.endIndex,
        newText: resolved.toString(),
      });
    } else if (resolved) {
      edits.push({
        startIndex: node.startIndex,
        endIndex: node.endIndex,
        newText: resolved.text,
      });
    }
  }

  const result = runEdits(source, edits);
  return result;
}
function resolveNode(
  node: Parser.SyntaxNode,
  identifierMap: Map<Parser.SyntaxNode, Parser.SyntaxNode>,
): boolean | Parser.SyntaxNode | void {
  switch (node.type) {
    case "true":
      return true;
    case "false":
      return false;
    case "parenthesized_expression":
      if (node.namedChildren.length !== 1) return;
      return resolveNode(node.namedChildren[0], identifierMap);
    case "binary_expression":
      return resolveBinaryExpression(node, identifierMap);
    case "unary_expression":
      const argument = getField(node, "argument");
      if (!argument) return;
      const resolved = resolveNode(argument, identifierMap);
      if (typeof resolved !== "boolean") return;
      return !resolved;
    case "identifier": {
      const declaration = identifierMap.get(node);
      if (!declaration) return;
      const isConst = declaration.parent?.previousSibling?.type === "const";
      if (!isConst) return;
      return resolveNode(declaration, identifierMap);
    }
    default:
  }
}
function resolveBinaryExpression(
  node: Parser.SyntaxNode,
  identifierMap: Map<Parser.SyntaxNode, Parser.SyntaxNode>,
): boolean | Parser.SyntaxNode | void {
  const left = getField(node, "left");
  const right = getField(node, "right");
  if (!left || !right) return;
  const operatorNode = node.children.find((n) => n !== left && n !== right);
  if (!operatorNode) return;
  const resolvedLeft = resolveNode(left, identifierMap) ?? left;
  const resolvedRight = resolveNode(right, identifierMap) ?? right;
  switch (operatorNode.type) {
    case "&&": {
      if (resolvedLeft === false || resolvedRight === false) {
        return false;
      } else if (resolvedLeft === true && resolvedRight === true) {
        return true;
      } else if (resolvedLeft === true) {
        return resolvedRight;
      } else if (resolvedRight === true) {
        return resolvedLeft;
      }
      break;
    }
    case "||": {
      if (resolvedLeft === false && resolvedRight === false) {
        return false;
      } else if (resolvedLeft === true || resolvedRight === true) {
        return true;
      } else if (resolvedLeft === false) {
        return resolvedRight;
      } else if (resolvedRight === false) {
        return resolvedLeft;
      }
      break;
    }
    case "===": {
      if (
        typeof resolvedLeft !== "boolean" ||
        typeof resolvedRight !== "boolean"
      )
        return;
      return resolvedLeft === resolvedRight;
    }
    case "!==": {
      if (
        typeof resolvedLeft !== "boolean" ||
        typeof resolvedRight !== "boolean"
      )
        return;
      return resolvedLeft !== resolvedRight;
    }
    default:
  }
}
