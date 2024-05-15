import type Parser from "tree-sitter";

export function isExported(node: Parser.SyntaxNode): boolean {
  switch (node.type) {
    case "variable_declarator":
      return node.parent?.parent?.type === "export_statement";
    case "function_declaration":
      return node.parent?.type === "export_statement";
    case "arrow_function":
      if (!node.parent) return false;
      return isExported(node.parent);
    case "required_parameter":
    case "optional_parameter":
      if (!node.parent?.parent) return false;
      return isExported(node.parent.parent);
    default:
      return false;
  }
}
