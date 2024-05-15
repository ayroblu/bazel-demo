import Parser from "tree-sitter";
import { pred } from "../../utils.js";
import { getField } from "../../../query.js";
import type { TraverseQuery } from "../../../traverse.js";

type Scope = {
  vars: {
    [key: string]: {
      node: Parser.SyntaxNode;
      isExported: boolean;
    };
  };
  shadows: boolean;
};
export function getTraverseDeclarations(): {
  declarationsQuery: TraverseQuery;
  scopesByStatement: Map<Parser.SyntaxNode, Scope>;
  scopes: Scope[];
} {
  const scopes: Scope[] = [{ vars: {}, shadows: false }];
  const scopesByStatement: Map<Parser.SyntaxNode, Scope> = new Map();
  const onDeclaratorNode = (
    node: Parser.SyntaxNode,
    field: string = "name",
  ) => {
    const lastScope = scopes.at(-1)!;
    const name = pred(
      getField(node, field),
      (n) => n?.type === "identifier",
    )?.text;
    if (name) {
      if (lastScope.vars[name]) {
        // throw new Error("redeclaration of identifier: " + name);
        console.log("redeclaration of identifier: " + name);
      } else if (!lastScope.shadows) {
        if (scopes.findLast((scope) => scope.vars[name])) {
          lastScope.shadows = true;
        }
      }
      const isExported = node.parent?.type === "export_statement";
      lastScope.vars[name] = { node, isExported };
    }
  };
  const declarationsQuery: TraverseQuery = {
    required_parameter: (node) => {
      onDeclaratorNode(node, "pattern");
    },
    optional_parameter: (node) => {
      onDeclaratorNode(node, "pattern");
    },
    function_declaration: (node) => {
      onDeclaratorNode(node);
    },
    variable_declarator: (node) => {
      onDeclaratorNode(node);
    },
    statement_block: (node) => {
      // Assume lexical scope is encapsulated by statement_block
      const scope = { vars: {}, shadows: false };
      scopes.push(scope);
      scopesByStatement.set(node, scope);
      return () => {
        scopes.pop();
      };
    },
    arrow_function: (node) => {
      // Special case for arrow funcs
      const scope = { vars: {}, shadows: false };
      scopes.push(scope);
      scopesByStatement.set(node, scope);
      return () => {
        scopes.pop();
      };
    },
  };
  return {
    declarationsQuery,
    scopesByStatement,
    scopes,
  };
}
