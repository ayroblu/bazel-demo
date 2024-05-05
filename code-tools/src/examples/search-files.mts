/**
 * 1. git ls-files
 * 2. filter by known string query (source code includes xyz)
 * 3. parse and search file for code
 */

import { existsSync, readFileSync } from "node:fs";
import { isMainScript } from "../misc-utils.mjs";
import { shell } from "./utils/shell.mjs";
import Parser from "tree-sitter";
import ts from "tree-sitter-typescript";
import { buildTraverseQuery } from "../query.mjs";
import { traverseWithCursor } from "../traverse.mjs";
const { tsx } = ts;

const parser = new Parser();
parser.setLanguage(tsx);

if (isMainScript(import.meta.url)) {
  const time1 = performance.now();
  const { stdout: gitFilesOutput } = await shell("git ls-files $DIRECTORY", {
    env: { DIRECTORY: "." },
  });
  const time2 = performance.now();
  const extensions = [".js"];
  const filePaths = gitFilesOutput
    .split("\n")
    .filter(
      (filePath) =>
        filePath &&
        extensions.some((extension) => filePath.endsWith(extension)) &&
        existsSync(filePath),
    );

  const timings: Record<string, number>[] = [];
  const results: Result[] = [];
  for (const filePath of filePaths) {
    const time1 = performance.now();
    const source = readFileSync(filePath, { encoding: "utf8" });
    const time2 = performance.now();
    if (!source.includes("accessibilityLabel")) {
      timings.push({
        read: time2 - time1,
      });
      continue;
    }
    const query = {
      type: ["jsx_self_closing_element", "jsx_opening_element"],
      items: [
        {
          field: "name",
          text: /^(View|Image|Button|Icon\w+)$/,
        },
        {
          type: "jsx_attribute",
          items: [
            {
              type: "property_identifier",
              capture: "identifier",
              text: "accessibilityLabel",
            },
          ],
        },
      ],
    } as const;

    const time3 = performance.now();
    const tree = parser.parse(source);
    const traverseQuery = buildTraverseQuery(query, (captures) => {
      const pos = captures.identifier.startPosition;
      results.push({ filename: filePath, line: pos.row, column: pos.column });
      return { skip: true };
    });
    const time4 = performance.now();
    traverseWithCursor(tree.walk(), traverseQuery);
    const time5 = performance.now();
    const timing = {
      read: time2 - time1,
      parse: time4 - time3,
      traverse: time5 - time4,
    };
    timings.push(timing);
  }
  for (const { filename, line, column } of results) {
    console.log(`${filename}:${line}:${column}`);
  }
  console.error("git ls-files", (time2 - time1).toLocaleString(), "ms");
  Object.entries(aggregateTiming(timings)).forEach(([key, value]) => {
    console.error(key, value.toLocaleString(), "ms");
  });
}

function aggregateTiming(
  timings: Record<string, number>[],
): Record<string, number> {
  const result: Record<string, number> = {};
  for (const timing of timings) {
    Object.entries(timing).forEach(([key, value]) => {
      result[key] = (result[key] ?? 0) + value;
    });
  }
  return result;
}

type Result = {
  filename: string;
  line: number;
  column: number;
};
