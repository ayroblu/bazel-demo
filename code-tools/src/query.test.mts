import Parser from "tree-sitter";
import ts from "tree-sitter-typescript";
import starlark from "tree-sitter-starlark";
import { buildTraverseQuery } from "./query.mjs";
import { traverseWithCursor } from "./traverse.mjs";
const { tsx } = ts;

describe("query", () => {
  const parser = new Parser();
  parser.setLanguage(tsx);

  it("should match valid expression", () => {
    const sourceCode = "let x = 1;\nconsole.log(x);";
    const tree = parser.parse(sourceCode);
    const query = {
      type: "expression_statement",
      capture: "expression",
      items: [
        {
          type: "call_expression",
          items: [
            { field: "function", capture: "callName", text: "console.log" },
          ],
        },
      ],
    } as const;

    let capture = undefined;
    const traverseQuery = buildTraverseQuery(query, (captures) => {
      capture = Object.keys(captures);
    });
    traverseWithCursor(tree.walk(), traverseQuery);
    expect(capture).to.deep.equal(["expression", "callName"]);
  });

  it("should match more generalised expression", () => {
    const sourceCode = `
const first = <Component foo="string" bar="string" />;
const second = <Component foo="string" bar="string">{first}</Component>;
const third = <NestedComponent foo="string" bar="string">{first}</NestedComponent>;
const fourth = <MyComp foo="Component" bar="string">{first}</MyComp>;
  `;
    const tree = parser.parse(sourceCode);
    const query = {
      type: ["jsx_opening_element", "jsx_self_closing_element"],
      items: [
        {
          field: "name",
          text: /Component/,
        },
        {
          type: "jsx_attribute",
          items: [
            {
              type: "property_identifier",
              capture: "identifier",
              text: "foo",
            },
          ],
        },
      ],
    } as const;

    const results: string[][] = [];
    const traverseQuery = buildTraverseQuery(query, (captures) => {
      results.push(Object.keys(captures));
    });
    traverseWithCursor(tree.walk(), traverseQuery);
    expect(results).to.deep.equal([
      ["identifier"],
      ["identifier"],
      ["identifier"],
    ]);
  });

  describe("captureAll", () => {
    const sourceCode = `
const a = {
  key1: 'first',
  key2: 'second',
  key3: 'third',
}
  `.trim();
    const tree = parser.parse(sourceCode);

    it("should match first item", () => {
      const query = {
        type: "object",
        items: [
          {
            type: "pair",
            items: [
              { field: "key", capture: "key" },
              { field: "value", capture: "value" },
            ],
          },
        ],
      } as const;

      const results: { key: string; value: string }[] = [];
      const traverseQuery = buildTraverseQuery(query, (captures) => {
        const key = captures.key.text;
        const value = captures.value.text;
        results.push({ key, value });
      });
      traverseWithCursor(tree.walk(), traverseQuery);
      expect(results).to.deep.equal([{ key: "key1", value: "'first'" }]);
    });

    it("should match each sub item", () => {
      const query = {
        type: "object",
        captureAll: true,
        items: [
          {
            type: "pair",
            items: [
              { field: "key", capture: "key" },
              { field: "value", capture: "value" },
            ],
          },
        ],
      } as const;

      const results: { key: string; value: string }[] = [];
      const traverseQuery = buildTraverseQuery(query, (captures) => {
        const key = captures.key.text;
        const value = captures.value.text;
        results.push({ key, value });
      });
      traverseWithCursor(tree.walk(), traverseQuery);
      expect(results).to.deep.equal([
        { key: "key1", value: "'first'" },
        { key: "key2", value: "'second'" },
        { key: "key3", value: "'third'" },
      ]);
    });
  });

  describe("optional", () => {
    const parser = new Parser();
    parser.setLanguage(starlark);
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

    it("capture when present", () => {
      const sourceCode = `
scala_library(
  name="custom_name",
  sources=["*.scala"],
  dependencies=[
    "path/to/dep",
  ],
)
  `.trim();
      const tree = parser.parse(sourceCode);

      const results: { target: string, sources: string[]; deps: string[] }[] = [];
      const traverseQuery = buildTraverseQuery(query, (captures) => {
        const target = captures.target?.text.slice(1, -1);
        const sources = captures.sources?.namedChildren.map((n) =>
          n.text.slice(1, -1),
        );
        const deps = captures.deps.namedChildren.map((n) =>
          n.text.slice(1, -1),
        );
        results.push({ target, sources, deps });
      });
      traverseWithCursor(tree.walk(), traverseQuery);
      expect(results).to.deep.equal([
        { sources: ["*.scala"], deps: ["path/to/dep"], target: 'custom_name' },
      ]);
    });

    it("omit when not present", () => {
      const sourceCode = `
scala_library(
  dependencies=[
    "path/to/dep",
  ],
)
  `.trim();
      const tree = parser.parse(sourceCode);

      const results: { target: string, sources: string[]; deps: string[] }[] = [];
      const traverseQuery = buildTraverseQuery(query, (captures) => {
        const target = captures.target?.text.slice(1, -1);
        const sources = captures.sources?.namedChildren.map((n) =>
          n.text.slice(1, -1),
        );
        const deps = captures.deps.namedChildren.map((n) =>
          n.text.slice(1, -1),
        );
        results.push({ target, sources, deps });
      });
      traverseWithCursor(tree.walk(), traverseQuery);
      expect(results).to.deep.equal([
        { deps: ["path/to/dep"], sources: undefined, target: undefined },
      ]);
    });
  });
});