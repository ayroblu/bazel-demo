import Parser from "tree-sitter";
import starlark from "tree-sitter-starlark";
import { buildTraverseQuery } from "../../query.js";
import { traverseWithCursor } from "../../traverse.js";
import { basename } from "node:path";

const parser = new Parser();
parser.setLanguage(starlark);

export function parseBazelScalaLib(
  source: string,
  { baseTarget }: { baseTarget: string },
) {
  const tree = parser.parse(source);
  const { results: scalaResults, traverseQuery: scalaTraverseQuery } =
    getScalaTraverseQuery({
      baseTarget,
    });
  const { results: thriftResults, traverseQuery: thriftTraverseQuery } =
    getThriftTraverseQuery({
      baseTarget,
    });
  const { results: aliasResults, traverseQuery: aliasTraverseQuery } =
    getAliasTraverseQuery({
      baseTarget,
    });
  traverseWithCursor(
    tree.walk(),
    scalaTraverseQuery,
    thriftTraverseQuery,
    aliasTraverseQuery,
  );

  return [...scalaResults, ...thriftResults, ...aliasResults].reduce<
    Record<string, ParsedBazel>
  >((map, next) => {
    map[next.target] = next;
    return map;
  }, {});
}

function getScalaTraverseQuery({ baseTarget }: { baseTarget: string }) {
  const query = {
    type: "call",
    items: [
      {
        field: "function",
        text: /(scala_library|target)/,
        capture: "func",
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
  const results: ParsedBazel[] = [];
  const traverseQuery = buildTraverseQuery(query, (captures) => {
    const sources = captures.sources
      ? extractStrings(captures.sources)
      : captures.func.text === "scala_library"
        ? ["*.scala"]
        : undefined;
    const deps = extractStrings(captures.deps).map((n) =>
      n.startsWith(":") ? `${baseTarget}${n}` : n,
    );
    results.push({
      target: captures.target?.text.slice(1, -1) ?? basename(baseTarget),
      sources,
      deps,
    });
    return { skip: true };
  });
  return { results, traverseQuery };
}

function extractStrings(node: Parser.SyntaxNode): string[] {
  const query = {
    type: "string_content",
    capture: "text",
  };
  const strings: string[] = [];
  const traverseQuery = buildTraverseQuery(query, (captures) => {
    strings.push(captures.text.text);
    return { skip: true };
  });
  traverseWithCursor(node.walk(), traverseQuery);
  return strings;
}

function getThriftTraverseQuery({ baseTarget }: { baseTarget: string }) {
  const query = {
    type: "call",
    items: [
      {
        field: "function",
        text: "create_thrift_libraries",
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
                text: "dependency_roots",
              },
              {
                field: "value",
                capture: "deps",
              },
            ],
            optional: true,
          },
          {
            type: "keyword_argument",
            items: [
              {
                field: "name",
                text: "base_name",
              },
              {
                field: "value",
                capture: "target",
              },
            ],
            optional: true,
          },
          {
            type: "keyword_argument",
            items: [
              {
                field: "name",
                text: "generate_languages",
              },
              {
                field: "value",
                capture: "langs",
              },
            ],
          },
        ],
      },
    ],
  } as const;
  const results: ParsedBazel[] = [];
  const traverseQuery = buildTraverseQuery(query, (captures) => {
    const sources = captures.sources
      ? extractStrings(captures.sources)
      : undefined;
    const baseTargetName =
      captures.target?.text.slice(1, -1) ?? basename(baseTarget);
    const langs = extractStrings(captures.langs);
    const deps = captures.deps
      ? extractStrings(captures.deps).map((n) =>
          n.startsWith(":") ? `${baseTarget}${n}` : n,
        )
      : [];
    for (const lang of langs) {
      results.push({
        target: `${baseTargetName}-${lang}`,
        sources,
        deps,
      });
    }
    return { skip: true };
  });
  return { results, traverseQuery };
}

function getAliasTraverseQuery({ baseTarget }: { baseTarget: string }) {
  const query = {
    type: "call",
    items: [
      {
        field: "function",
        text: "alias",
      },
      {
        field: "arguments",
        items: [
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
          {
            type: "keyword_argument",
            items: [
              {
                field: "name",
                text: "target",
              },
              {
                field: "value",
                capture: "dep",
              },
            ],
          },
        ],
      },
    ],
  } as const;
  const results: ParsedBazel[] = [];
  const traverseQuery = buildTraverseQuery(query, (captures) => {
    const target = captures.target?.text.slice(1, -1) ?? basename(baseTarget);
    const deps = [captures.dep.text.slice(1, -1)];
    results.push({
      sources: undefined,
      target,
      deps,
    });
    return { skip: true };
  });
  return { results, traverseQuery };
}

export type ParsedBazel = {
  target: string;
  sources: string[] | void;
  deps: string[];
};
