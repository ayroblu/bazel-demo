import Parser from "tree-sitter";
import scala from "tree-sitter-scala";
import { buildTraverseQuery, getField } from "../../query.js";
import { traverseWithCursor } from "../../traverse.js";

const parser = new Parser();
parser.setLanguage(scala);

export function parseScalaImportsExports(source: string) {
  const tree = parser.parse(source);
  const imports: string[] = [];
  const exportNames: string[] = [];
  const packageQuery = {
    type: "package_identifier",
    capture: "packageName",
  } as const;
  let packageName = "";
  const packageTraverseQuery = buildTraverseQuery(packageQuery, (captures) => {
    packageName = captures.packageName.text;
    return { skip: true };
  });
  tree.rootNode.namedChildren
    .filter((node) => node.type === "import_declaration")
    .forEach((node) => {
      imports.push(...importNodeToImports(node));
    });
  traverseWithCursor(tree.walk(), packageTraverseQuery);
  const possibleExportTypes = [
    "object_definition",
    "class_definition",
    "trait_definition",
    "type_definition",
    "val_definition",
  ];
  const packageObjectExports: string[] = [];
  for (const node of tree.rootNode.namedChildren) {
    if (possibleExportTypes.includes(node.type)) {
      const name =
        getField(node, "name")?.text ??
        node.namedChildren.find((n) => n.type === "identifier")?.text;
      if (name) {
        exportNames.push(name);
      } else {
        // console.log("no name", node.toString(), node.text);
      }
    } else if (node.type === "package_object") {
      const namespace = getField(node, "name")?.text;
      if (!namespace) continue;
      const body = getField(node, "body");
      if (!body) continue;
      packageObjectExports.push(`${packageName}.${namespace}._`);
      for (const node of body.namedChildren) {
        if (!possibleExportTypes.includes(node.type)) {
          continue;
        }
        const name = getField(node, "name")?.text;
        if (name) {
          packageObjectExports.push(`${packageName}.${namespace}.${name}`);
        } else {
          const nameNode = getField(node, "pattern");
          if (nameNode?.type === "identifier") {
            packageObjectExports.push(
              `${packageName}.${namespace}.${nameNode.text}`,
            );
          } else {
            console.log("unknown export", node.text);
          }
        }
      }
    }
  }
  const exports = exportNames.map((e) => [packageName, e].join("."));
  exports.push(`${packageName}._`);
  if (packageObjectExports.length) {
    exports.push(...packageObjectExports);
  }
  return { imports, exports };
}

function importNodeToImports(node: Parser.SyntaxNode): string[] {
  const importParts = node.namedChildren.map((n) =>
    n.type === "import_selectors"
      ? n.namedChildren.map((n) =>
          n.type === "renamed_identifier"
            ? getField(n, "name")?.text ?? ""
            : n.text,
        )
      : n.text,
  );
  const variations = buildVariations(importParts);
  return (
    variations
      .map((variation) => variation.join("."))
      // due to a bug in parsing with npm libs, imports in classes are captured
      .filter((v) => v.startsWith("com"))
      .map((variation) => {
        const items = variation.split(".");
        const index = items.findIndex(
          (item) => item[0] === item[0].toUpperCase(),
        );
        if (index > 0 && index < items.length - 1) {
          return items.slice(0, index + 1).join(".");
        }
        return variation;
      })
  );
}
function buildVariations(parts: (string | string[])[]): string[][] {
  let variations: string[][] = [[]];
  for (const part of parts) {
    if (Array.isArray(part)) {
      variations = part.flatMap((variant) =>
        variations.map((v) => v.concat(variant)),
      );
    } else {
      for (const variation of variations) {
        variation.push(part);
      }
      if (part[0] === part[0].toUpperCase()) {
        break;
      }
    }
  }
  return variations;
}
