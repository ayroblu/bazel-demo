import Parser from "tree-sitter";
import scala from "tree-sitter-scala";
import { buildTraverseQuery, getField } from "../../query.mjs";
import { traverseWithCursor } from "../../traverse.mjs";

const parser = new Parser();
parser.setLanguage(scala);

export function parseScalaImportsExports(source: string) {
  const tree = parser.parse(source);
  const packageQuery = {
    type: "package_identifier",
    capture: "packageName",
  } as const;
  const importQuery = {
    type: "import_declaration",
    capture: "importDeclaration",
  } as const;
  let packageName = "";
  const imports: string[] = [];
  const exportNames: string[] = [];
  const packageTraverseQuery = buildTraverseQuery(packageQuery, (captures) => {
    packageName = captures.packageName.text;
    return { skip: true };
  });
  const importTraverseQuery = buildTraverseQuery(importQuery, (captures) => {
    imports.push(...importNodeToImports(captures.importDeclaration));
    return { skip: true };
  });
  traverseWithCursor(tree.walk(), packageTraverseQuery, importTraverseQuery);
  // TODO: Think about package objects
  const possibleExportTypes = [
    "object_definition",
    "class_definition",
    "trait_definition",
  ];
  for (const node of tree.rootNode.namedChildren) {
    if (possibleExportTypes.includes(node.type)) {
      const name = getField(node, "name")?.text ?? "";
      exportNames.push(name);
    }
  }
  const exports = exportNames.map((e) => [packageName, e].join("."));
  return { imports, exports };
}

function createCacheManager<K, V>() {
  const cache = new Map<K, Promise<V> | { value: V }>();
  function get(key: K, func: () => Promise<V> | V): Promise<V> | V {
    const result =
      cache.get(key) ??
      (() => {
        const value = func();
        if (value instanceof Promise) {
          cache.set(key, value);
          value.then(
            (v) => cache.set(key, { value: v }),
            () => {
              cache.delete(key);
            },
          );
          return value;
        } else {
          cache.set(key, { value });
          return { value };
        }
      })();

    if (result instanceof Promise) {
      return result;
    } else {
      return result.value;
    }
  }
  return {
    get,
  };
}
type ImportExports = { exports: string[]; imports: string[] };
const cacheManager = createCacheManager<string, ImportExports>();

// function readScalaImportExports(filepath: string) {
//   return cacheManager.get(filepath, () => {
//     const source = readFileSync(filepath, { encoding: "utf8" });
// return parseScalaImportsExports(source);
//   });
// }
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
  return variations.map((variation) => variation.join("."));
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
    }
  }
  return variations;
}
