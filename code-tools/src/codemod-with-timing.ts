import Parser from "tree-sitter";
import ts from "tree-sitter-typescript";
import {
  buildTraverseQuery,
  type QueryCaptures,
  type TreeSitterQueryItem,
} from "./query.js";
import { traverseWithCursor } from "./traverse.js";
const { tsx } = ts;

export function runCodemod<QueryItem extends TreeSitterQueryItem>({
  source,
  query,
  onCapture,
}: {
  source: string;
  lang?: "tsx";
  query: QueryItem;
  onCapture: (captures: QueryCaptures<QueryItem>) => CodeEdit;
}): {
  result: string;
  timings: {
    setup: number;
    parsing: number;
    traversal: number;
    edit: number;
  };
} {
  const time1 = performance.now();
  const parser = new Parser();
  parser.setLanguage(tsx);
  const time2 = performance.now();

  const tree = parser.parse(source);
  const time3 = performance.now();

  const edits: CodeEdit[] = [];
  const traverseQuery = buildTraverseQuery(query, (captures) => {
    const edit = onCapture(captures);
    edits.push(edit);
    return { skip: true };
  });
  traverseWithCursor(tree.walk(), traverseQuery);
  const time4 = performance.now();

  const result = runEdits(source, edits);
  const time5 = performance.now();
  return {
    result,
    timings: {
      setup: time2 - time1,
      parsing: time3 - time2,
      traversal: time4 - time3,
      edit: time5 - time4,
    },
  };
}

/* Assumes edits are in ascending order */
function runEdits(source: string, edits: CodeEdit[]): string {
  let adjustment = 0;
  for (const { startIndex, endIndex, newText } of edits) {
    source =
      source.slice(0, startIndex + adjustment) +
      newText +
      source.slice(endIndex + adjustment);
    adjustment += newText.length - (endIndex - startIndex);
  }
  return source;
}

type CodeEdit = {
  startIndex: number;
  endIndex: number;
  newText: string;
};