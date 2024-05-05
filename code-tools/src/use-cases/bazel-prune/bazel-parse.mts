import Parser from "tree-sitter";
import starlark from "tree-sitter-starlark";
import { buildTraverseQuery } from "../../query.mjs";
import { traverseWithCursor } from "../../traverse.mjs";

const parser = new Parser();
parser.setLanguage(starlark);

export function parseBazelScalaLib(source: string) {
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
            optional: true,
          },
          {
            type: "keyword_argument",
            items: [
              {
                field: "name",
                text: "dependencies",
              },
              {
                field: "value",
                capture: "deps",
              },
            ],
          },
          {
            type: "keyword_argument",
            items: [
              {
                field: "name",
                text: "name",
              },
              {
                field: "value",
                capture: "target",
              },
            ],
            optional: true,
          },
        ],
      },
    ],
  } as const;
  const results: {
    target: string | undefined;
    sources: string[] | void;
    deps: string[];
  }[] = [];
  const traverseQuery = buildTraverseQuery(query, (captures) => {
    const sources = captures.sources.namedChildren.map((n) =>
      n.text.slice(1, -1),
    );
    const deps = captures.deps.namedChildren.map((n) => n.text.slice(1, -1));
    results.push({ target: undefined, sources, deps });
    return { skip: true };
  });
  traverseWithCursor(tree.walk(), traverseQuery);

  return results;
}
