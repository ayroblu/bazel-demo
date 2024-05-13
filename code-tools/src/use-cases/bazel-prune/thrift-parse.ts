import Parser from "tree-sitter";
import thrift from "tree-sitter-thrift";
import { getField } from "../../query.js";

const parser = new Parser();
parser.setLanguage(thrift);

export function parseThriftImportsExports(source: string) {
  const tree = parser.parse(source);
  const imports: string[] = [];
  const exportNames: string[] = [];

  for (const node of tree.rootNode.namedChildren) {
    if (node.type === "include_statement") {
      const file = node.namedChildren[0].namedChildren[0].text;
      if (file) {
        imports.push(file);
      } else {
        console.log("UNKNOWNINCLUDE", node.type, node.text);
      }
    } else if (node.type.endsWith("_definition")) {
      const name =
        getField(node, "type")?.text ??
        ((n) => (n.type === "identifier" ? n.text : undefined))(
          node.namedChildren[0],
        ) ??
        (() => {
          if (node.type === "typedef_definition") {
            return node.namedChildren.find(
              (n) => n.type === "typedef_identifier",
            )?.text;
          } else {
            return node.namedChildren.find((n) => n.type === "identifier")
              ?.text;
          }
        })();
      if (name) {
        exportNames.push(name);
      } else {
        console.log("UNKNOWN", node.type, node.toString(), node.text);
      }
    }
  }
  // namespace java com.example.thriftjava
  // #@namespace scala com.example.thriftscala
  const packageExports: string[] = [];
  const javaMatch = /namespace java ([\w.]*)/.exec(source);
  if (javaMatch) {
    packageExports.push(javaMatch[1]);
  }
  const scalaMatch = /#@namespace scala ([\w.]*)/.exec(source);
  if (scalaMatch) {
    packageExports.push(scalaMatch[1]);
  }
  const exports = packageExports.flatMap((namespace) => {
    return exportNames.map((name) => `${namespace}.${name}`);
  });

  return { imports, exports, packageExports };
}
