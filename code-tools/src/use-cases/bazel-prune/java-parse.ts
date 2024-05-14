import Parser from "tree-sitter";
import java from "tree-sitter-java";
import { buildTraverseQuery, getField } from "../../query.js";
import { traverseWithCursor } from "../../traverse.js";

const parser = new Parser();
parser.setLanguage(java);

export function parseJavaImportsExports(source: string) {
  const tree = parser.parse(source);
  const imports: string[] = [];
  const exportNames: string[] = [];
  const packageQuery = {
    type: "package_declaration",
    items: [
      {
        wildcard: true,
        capture: "packageName",
      },
    ],
  } as const;
  let packageName = "";
  const packageTraverseQuery = buildTraverseQuery(packageQuery, (captures) => {
    packageName = captures.packageName.text;
    return { skip: true };
  });
  tree.rootNode.namedChildren
    .filter((node) => node.type === "import_declaration")
    .forEach((node) => {
      imports.push(node.namedChildren[0].text);
    });
  traverseWithCursor(tree.walk(), packageTraverseQuery);
  const possibleExportTypes = ["class_declaration"];
  for (const node of tree.rootNode.namedChildren) {
    if (possibleExportTypes.includes(node.type)) {
      const name =
        getField(node, "name")?.text ??
        node.namedChildren.find((n) => n.type === "identifier")?.text;
      if (name) {
        exportNames.push(name);
      }
    }
  }
  const exports = exportNames.map((e) => [packageName, e].join("."));
  exports.push(`${packageName}._`);
  return { imports, exports };
}
