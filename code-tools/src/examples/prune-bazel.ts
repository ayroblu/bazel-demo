/**
 * For some bazel file, find all it's scala files, find all its imports
 * Also for some bazel file, traverse all its dependencies to find all their scala files and what they import
 * If scala file does not import a dependency specified in bazel, remove it from bazel
 * It's possible that a imports b imports c. b never uses c but a uses c - I need the whole bazel graph
 *
 * 1. List all BUILD bazel files
 * 2. For each bazel file determine the list of imports and transitive imports and exports
 * 3. Import / export is `com.package.ClassName`
 * 4. Filter out imports that you don't depend on AND your children don't depend on
 */

import { existsSync, readFileSync } from "node:fs";
import { isMainScript } from "../misc-utils.js";
import { shell } from "./utils/shell.js";
import Parser from "tree-sitter";
import ts from "tree-sitter-starlark";
import { buildTraverseQuery, getField } from "../query.js";
import { traverseWithCursor } from "../traverse.js";
import path from "path";

const parser = new Parser();
parser.setLanguage(ts);

if (isMainScript(import.meta.url)) {
  const { stdout: gitFilesOutput } = await shell("git ls-files BUILD");
  // const extensions = ["BUILD", "BUILD.bazel"];
  const filePaths = gitFilesOutput
    .split("\n")
    .filter((filePath) => filePath && existsSync(filePath));
  for (const filepath of filePaths) {
    readBazelScalaExports(filepath);
  }
}

function readBazelImports(filepath: string) {
  // fs.readFileSync(filepath, 'utf8')
  // parse and extract all dependencies (list of build targets)
}
async function readBazelScalaExports(filepath: string) {
  const source = readFileSync(filepath, { encoding: "utf8" });
  const tree = parser.parse(source);
  const query = {
    type: "call",
    items: [
      {
        field: "function",
        text: "scala_library",
      },
      {
        field: "arguments",
        items: [
          {
            type: "keyword_argument",
            items: [
              {
                field: "name",
                text: "sources",
              },
              {
                field: "value",
                capture: "sources",
              },
            ],
          },
        ],
      },
    ],
  } as const;
  const results: { target: string | undefined; sources: string[] }[] = [];
  const traverseQuery = buildTraverseQuery(query, (captures) => {
    const { sources } = captures;
    if (sources.type === "list") {
      const result = sources.namedChildren.map((n) => n.text.slice(1, -1));
      results.push({ target: undefined, sources: result });
    } else {
      console.log("unrecognise source type", sources.type, sources.text);
    }
    return { skip: true };
  });
  traverseWithCursor(tree.walk(), traverseQuery);
  console.log("bazel targets", results);
  const bazelTargets = await Promise.all(
    results.map(({ sources, ...rest }) =>
      Promise.all(
        sources.map((source) =>
          shell(`ls "${path.dirname(filepath)}"/${source}`).then((result) => ({
            ...rest,
            sources: result.stdout
              .split("\n")
              .filter((a) => a && existsSync(a))
              .map((filename) => readScalaImportExports(filename)),
          })),
        ),
      ),
    ),
  );
  console.log("bazel target with sources", bazelTargets);
  return bazelTargets;

  // read bazel file
  // get sources
  // list all files that match sources
  // read scala files and list all imports
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

function readScalaImportExports(filepath: string) {
  return cacheManager.get(filepath, () => {
    const source = readFileSync(filepath, { encoding: "utf8" });
    const tree = parser.parse(source);
    const packageQuery = {
      type: "package_identifier",
      capture: "packageName",
    } as const;
    const importQuery = {
      type: "import_declaration",
      capture: "importDeclaration",
    } as const;
    const exportQuery = {
      type: "program",
      items: [
        {
          type: ["object_definition", "class_definition", "trait_definition"],
          items: [{ field: "name", captures: "name" }],
        },
      ],
    } as const;
    let packageName = "";
    const imports: string[] = [];
    const exportNames: string[] = [];
    const packageTraverseQuery = buildTraverseQuery(
      packageQuery,
      (captures) => {
        packageName = captures.packageName.text;
        return { skip: true };
      },
    );
    // TODO: handle wildcards too
    const importTraverseQuery = buildTraverseQuery(importQuery, (captures) => {
      imports.push(...importNodeToImports(captures.importDeclaration));
      return { skip: true };
    });
    const exportTraverseQuery = buildTraverseQuery(exportQuery, (captures) => {
      exportNames.push(captures.name.text);
      return { skip: true };
    });
    traverseWithCursor(
      tree.walk(),
      packageTraverseQuery,
      importTraverseQuery,
      exportTraverseQuery,
    );
    const exports = exportNames.map((e) => [packageName, e].join("."));
    return { imports, exports };
  });
}
function importNodeToImports(node: Parser.SyntaxNode): string[] {
  const importParts = node.namedChildren.map((n) =>
    n.type === "namespace_selectors"
      ? n.namedChildren.map((n) =>
          n.type === "arrow_renamed_identifier"
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
