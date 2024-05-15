import Parser from "tree-sitter";
import ts from "tree-sitter-typescript";
import { traverseWithCursor, type TraverseQuery } from "../../traverse.js";
import { runEdits, type CodeEdit } from "../../codemod.js";
import { getField } from "../../query.js";
import { pred } from "../utils.js";
import { getTraverseDeclarations } from "./ast-utils/scoped-vars.js";
import { isExported } from "./ast-utils/ast-utils.js";

const { tsx } = ts;

type Scope = {
  vars: {
    [key: string]: {
      node: Parser.SyntaxNode;
      isExported: boolean;
    };
  };
  shadows: boolean;
};
export function unnecessaryConditionals(source: string) {
  const parser = new Parser();
  parser.setLanguage(tsx);

  const tree = parser.parse(source);

  // (if_statement condition: (parenthesized_expression (identifier)) consequence: (statement_block (comment)))
  // (if_statement condition: (parenthesized_expression (binary_expression left: (identifier) right: (number))) consequence: (statement_block (comment)))
  // (ternary_expression condition: (number) consequence: (number) alternative: (number))
  // a && b && c: (binary_expression left: (binary_expression left: (identifier) right: (identifier)) right: (identifier))

  // (if_statement condition: () consequence: () alternative: (else_clause (if_statement)))

  // Can resolve if_statement or ternary_expression
  // first pass, record all declarations in scope
  const { declarationsQuery, scopesByStatement, scopes } =
    getTraverseDeclarations();
  const { identifiers, callSites, callSitesQuery } = getTraverseReferences({
    scopes,
  });
  const conditions: {
    ifNode: Parser.SyntaxNode;
    scopes: Scope[];
  }[] = [];
  const traverseQuery: TraverseQuery = {
    if_statement: (node) => {
      conditions.push({ ifNode: node, scopes: scopes.concat() });
    },
    ternary_expression: (node) => {
      conditions.push({ ifNode: node, scopes: scopes.concat() });
    },
  };
  traverseWithCursor(
    tree.walk(),
    declarationsQuery,
    callSitesQuery,
    traverseQuery,
  );

  const { refsMap } = buildRefsMap({ callSites });

  const resolvedDec = new Map<Parser.SyntaxNode, Parser.SyntaxNode>();
  identifiers.forEach(({ node, scopes }) => {
    const isDeclarator = [
      "variable_declarator",
      "function_declaration",
      "required_parameter",
      "optional_parameter",
    ].some((type) => node.parent?.type === type);
    if (isDeclarator) return;
    const name = node.text;
    const decNode = scopes.findLast((scope) => scope.vars[name])?.vars[name]
      .node;
    if (decNode) {
      resolvedDec.set(node, decNode);
    }
  });

  // Conditions have 3 resolutions
  // if (true) {}
  // const a = true; if (a) {}
  // function b(a) {if (a) {}}b(true);
  // function b(a) {if (a) {}}const c = true;b(c); // various levels to this nesting
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
        const decNode = resolvedDec.get(node);
        if (!decNode) return;
        const isParam = ["required_parameter", "optional_parameter"].includes(
          decNode.type,
        );
        if (isExported(decNode)) return;
        if (isParam) {
          const isNoRefs = !refsMap.get(decNode)?.length;
          if (isNoRefs) {
            const value = getField(decNode, "value");
            if (value) {
              return resolveNode(value);
            }
          }
          const refNode = pred(
            refsMap.get(decNode),
            (n) => n?.length === 1,
          )?.[0];
          if (refNode) {
            return resolveNode(refNode);
          }
        }
        const isConstDeclarator =
          decNode.type === "variable_declarator" &&
          decNode.previousSibling?.type === "const";
        if (isConstDeclarator) {
          const valueNode = getField(decNode, "value");
          if (valueNode) {
            return resolveNode(valueNode);
          }
        }
        break;
      }
      default:
    }
  }

  const edits: CodeEdit[] = conditions.flatMap(({ ifNode }) => {
    const condition = getField(ifNode, "condition");
    const conditionResult = condition && resolveNode(condition);
    if (typeof conditionResult === "boolean") {
      const result = resolveConditional(
        ifNode,
        conditionResult,
        scopesByStatement,
      );
      return result ? [result] : [];
    } else if (conditionResult) {
      return [
        {
          startIndex: condition!.startIndex,
          endIndex: condition!.endIndex,
          newText: conditionResult.text,
        },
      ];
    }
    return [];
  });
  const result = runEdits(source, edits);
  return result;
}

function getTraverseReferences({ scopes }: { scopes: Scope[] }) {
  const identifiers: {
    node: Parser.SyntaxNode;
    scopes: Scope[];
  }[] = [];
  const callSites: {
    node: Parser.SyntaxNode;
    scopes: Scope[];
  }[] = [];
  const callSitesQuery: TraverseQuery = {
    call_expression: (node) => {
      const name = pred(
        getField(node, "function"),
        (n) => n?.type === "identifier",
      )?.text;
      if (name) {
        callSites.push({ node, scopes });
      }
    },
    identifier: (node) => {
      identifiers.push({ node, scopes: scopes.concat() });
    },
  };
  return { callSitesQuery, identifiers, callSites };
}

function buildRefsMap({
  callSites,
}: {
  callSites: { node: Parser.SyntaxNode; scopes: Scope[] }[];
}) {
  const goToDefMap = new Map<Parser.SyntaxNode, Parser.SyntaxNode>();
  const refsMap = new Map<Parser.SyntaxNode, Parser.SyntaxNode[]>();
  callSites.forEach(({ node, scopes }) => {
    const name = pred(
      getField(node, "function"),
      (n) => n?.type === "identifier",
    )?.text;
    if (!name) {
      return;
    }
    // for f(x), find scope / def of f and store it
    const scopeVar = scopes.findLast((scope) => scope.vars[name])?.vars[name];
    const decNode = scopeVar?.node;
    if (!decNode) return;
    goToDefMap.set(node, decNode);
    const decParams = getField(decNode, "parameters");
    const callParams = getField(node, "arguments");
    if (!(decParams && callParams)) return;

    // const x = 1; f(x); function f(x) {}
    // stores reference of x from f(x) to f(x);
    callParams.namedChildren.forEach((callParam, i) => {
      goToDefMap.set(callParam, decParams.namedChildren[i]);
      const list =
        refsMap.get(decParams.namedChildren[i]) ??
        (() => {
          const list: Parser.SyntaxNode[] = [];
          refsMap.set(decParams.namedChildren[i], list);
          return list;
        })();
      list.push(callParam);
    });
  });
  return { refsMap };
}

function resolveConditional(
  node: Parser.SyntaxNode,
  conditionResult: boolean,
  scopesByStatement: Map<Parser.SyntaxNode, Scope>,
): CodeEdit | void {
  if (conditionResult) {
    const consequence = getField(node, "consequence");
    if (consequence) {
      const isShadow = scopesByStatement.get(consequence)?.shadows;
      return {
        startIndex: node.startIndex,
        endIndex: node.endIndex,
        newText: getStatementText(consequence, isShadow),
      };
    }
  } else {
    const alternative = getField(node, "alternative");
    if (alternative) {
      const elseBlock = alternative.namedChildren[0];
      if (elseBlock) {
        const isShadow = scopesByStatement.get(elseBlock)?.shadows;
        return {
          startIndex: node.startIndex,
          endIndex: node.endIndex,
          newText: getStatementText(elseBlock, isShadow),
        };
      }
    } else {
      return {
        startIndex: node.startIndex,
        endIndex: node.endIndex,
        newText: "",
      };
    }
  }
}

function getStatementText(
  node: Parser.SyntaxNode,
  isShadow: boolean | undefined,
) {
  // isShadow = true means contains const / let. isShadow = undefined means not a statement_block
  if (node.type === "statement_block" && isShadow === false) {
    return node.text.slice(1, -1);
  }
  return node.text;
}
