/**
 * 1. git ls-files
 * 2. filter by known string query (source code includes xyz)
 * 3. parse and search file for code
 */

import { existsSync, readFileSync } from "node:fs";
import { isMainScript } from "../misc-utils.js";
import { shell } from "./utils/shell.js";
import Parser from "tree-sitter";
import ts from "tree-sitter-typescript";
import { buildTraverseQuery } from "../query.js";
import { traverseWithCursor } from "../traverse.js";
const { tsx } = ts;

const parser = new Parser();
parser.setLanguage(tsx);

if (isMainScript(import.meta.url)) {
  const { stdout: gitFilesOutput } = await shell("git ls-files $DIRECTORY", {
    env: { DIRECTORY: "." },
  });
  const extensions = [".js"];
  const filePaths = gitFilesOutput
    .split("\n")
    .filter(
      (filePath) =>
        filePath &&
        extensions.some((extension) => filePath.endsWith(extension)) &&
        existsSync(filePath),
    );

  const results: Result[] = [];
  for (const filePath of filePaths) {
    const source = readFileSync(filePath, { encoding: "utf8" });
    if (!source.includes("accessibilityLabel")) {
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

    const tree = parser.parse(source);
    const traverseQuery = buildTraverseQuery(query, (captures) => {
      const pos = captures.identifier.startPosition;
      results.push({ filename: filePath, line: pos.row, column: pos.column });
      return { skip: true };
    });
    traverseWithCursor(tree.walk(), traverseQuery);
  }
}

type Result = {
  filename: string;
  line: number;
  column: number;
};
