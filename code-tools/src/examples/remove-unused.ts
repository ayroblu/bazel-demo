import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { isMainScript } from "../misc-utils.js";
import { shell } from "./utils/shell.js";
import Parser from "tree-sitter";
import ts from "tree-sitter-typescript";
import { buildTraverseQuery, getField } from "../query.js";
import { traverseWithCursor } from "../traverse.js";
import { runEdits, type CodeEdit } from "../codemod.js";
import { unnecessaryConditionals } from "../use-cases/codemods/unnecessary-conditionals.js";
import { unusedVariables } from "../use-cases/codemods/unused-vars.js";
import { resolveBinaryExpressions } from "../use-cases/codemods/resolve-binary-expressions.js";
import { unnecessaryReactHooksDeps } from "../use-cases/codemods/unnecessary-react-hooks-deps.js";
const { tsx } = ts;

const fsName = "example_enabled";
const fsValue = "true";

const parser = new Parser();
parser.setLanguage(tsx);

const names = [
  "featureSwitches.isTrue",
  "featureSwitches.getValueWithoutScribeImpression",
  "useFeatureSwitchIsTrue",
];
if (isMainScript(import.meta.url)) {
  const { stdout: gitFilesOutput } = await shell("git ls-files $DIRECTORY", {
    env: { DIRECTORY: "." },
  });
  const extensions = [".js", ".flow"];
  const filePaths = gitFilesOutput
    .split("\n")
    .filter(
      (filePath) =>
        filePath &&
        extensions.some((extension) => filePath.endsWith(extension)) &&
        existsSync(filePath),
    );

  for (const filePath of filePaths) {
    const source = readFileSync(filePath, { encoding: "utf8" });
    if (!source.includes(fsName)) continue;
    console.log(filePath);

    let result = source;
    const query = {
      type: "call_expression",
      capture: "call",
    } as const;

    const edits: CodeEdit[] = [];
    const traverseQuery = buildTraverseQuery(query, (captures) => {
      const name = getField(captures.call, "function");
      const args = getField(captures.call, "arguments");
      if (!name || !args) return;

      if (!names.some((n) => name.text.includes(n))) return;
      if (
        args.namedChildren.length !== 1 ||
        args.namedChildren[0].namedChildren.length !== 1
      )
        return;
      if (args.namedChildren[0].namedChildren[0].text !== fsName) return;

      edits.push({
        startIndex: captures.call.startIndex,
        endIndex: captures.call.endIndex,
        newText: fsValue,
      });
      return { skip: true };
    });
    const tree = parser.parse(result);
    traverseWithCursor(tree.walk(), traverseQuery);
    result = runEdits(result, edits);
    result = resolveBinaryExpressions(result);
    result = unnecessaryConditionals(result);
    result = unnecessaryReactHooksDeps(result);
    result = unusedVariables(result);
    if (source !== result) {
      writeFileSync(filePath, result);
    }
  }
}
