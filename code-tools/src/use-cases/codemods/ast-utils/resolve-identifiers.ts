import Parser from "tree-sitter";
import { pred } from "../../utils.js";
import { getField } from "../../../query.js";
import type { TraverseQuery } from "../../../traverse.js";

type Scope = {
  vars: {
    [key: string]: {
      node: Parser.SyntaxNode;
    };
  };
  shadowsParent: boolean;
};
export function getResolvedIdentifiers(): {
  declarationsQuery: TraverseQuery;
  identifierMap: Map<Parser.SyntaxNode, Parser.SyntaxNode>;
} {
  const scopes: Scope[] = [{ vars: {}, shadowsParent: false }];
  const identifierMap: Map<Parser.SyntaxNode, Parser.SyntaxNode> = new Map();
  const onDeclaratorNode = (
    node: Parser.SyntaxNode,
    field: string = "name",
  ) => {
    const lastScope = scopes.at(-1)!;
    const name = pred(
      getField(node, field),
      (n) => n?.type === "identifier",
    )?.text;
    if (!name) return;

    if (lastScope.vars[name]) {
      throw new Error("redeclaration of identifier: " + name);
    } else if (!lastScope.shadowsParent) {
      const parentScope = scopes.at(-2);
      if (parentScope) {
        if (parentScope.vars[name]) {
          lastScope.shadowsParent = true;
        }
      }
    }
    switch (node.type) {
      case "function_declaration":
        lastScope.vars[name] = { node };
        break;
      case "variable_declarator":
        const value = getField(node, "value");
        if (value) {
          lastScope.vars[name] = { node: value };
        }
        break;
    }
  };
  const onAssignmentNode = (node: Parser.SyntaxNode) => {
    const name = pred(
      getField(node, "left"),
      (n) => n?.type === "identifier",
    )?.text;
    const value = getField(node, "right");
    if (!name || !value) return;
    const scopedVar = scopes.findLast((scope) => scope.vars[name])?.vars[name];
    if (scopedVar) {
      scopedVar.node = value;
    }
  };
  const allIdentifiers: { node: Parser.SyntaxNode; scopes: Scope[] }[] = [];
  const onIdentifier = (node: Parser.SyntaxNode) => {
    allIdentifiers.push({ node, scopes: scopes.concat() });
  };
  const onEnd = () => {
    for (const { node, scopes } of allIdentifiers) {
      const name = node.text;
      const scopedVar = scopes.findLast((scope) => scope.vars[name])?.vars[name]
        .node;
      if (scopedVar) {
        identifierMap.set(node, scopedVar);
      }
    }
  };
  const onLexicalScope = () => {
    const scope = { vars: {}, shadowsParent: false };
    scopes.push(scope);
    return () => {
      scopes.pop();
    };
  };
  const declarationsQuery: TraverseQuery = {
    function_declaration: (node) => {
      onDeclaratorNode(node);
    },
    variable_declarator: (node) => {
      onDeclaratorNode(node);
    },
    assignment_expression: (node) => {
      onAssignmentNode(node);
    },
    statement_block: (node) => {
      // Assume lexical scope is encapsulated by statement_block, except arrow func
      if (node.parent?.type === "arrow_function") return;
      return onLexicalScope();
    },
    arrow_function: () => {
      return onLexicalScope();
    },
    identifier: (node) => {
      onIdentifier(node);
    },
    shorthand_property_identifier: (node) => {
      onIdentifier(node);
    },
    program: () => {
      return () => {
        onEnd();
      };
    },
  };
  return {
    declarationsQuery,
    identifierMap,
  };
}
