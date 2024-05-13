import Parser from "tree-sitter";
import type { TraverseQuery } from "./traverse";

export function buildTraverseQuery<QueryItem extends TreeSitterQueryItem>(
  queryItem: QueryItem,
  callback: (params: QueryCaptures<QueryItem>) => void | { skip: boolean },
): TraverseQuery {
  function onNode(node: Parser.SyntaxNode): void | { skip: boolean } {
    if (toArr(queryItem.type).some((t) => t === node.type)) {
      queryItem.onFound?.(node);
      const captures: Record<string, Parser.SyntaxNode> = {};
      if (queryItem.capture) {
        captures[queryItem.capture] = node;
      }
      if (!queryItem.items) {
        return callback(captures as any);
      }
      const isMatch = queryItem.items.every((item) =>
        node.namedChildren.some((child) => {
          const matchAll = queryItem.captureAll
            ? {
                remainingCounter: queryItem.items?.length ?? 1,
                callback,
              }
            : undefined;
          return matchSubRecursive(child, item, captures, matchAll);
        }),
      );
      if (isMatch) {
        return callback(captures as any);
      }
    }
  }

  const result: TraverseQuery = {};
  for (const t of toArr(queryItem.type)) {
    result[t] = onNode;
  }
  return result;
}

function checkSubQueryItem(
  node: Parser.SyntaxNode,
  subQueryItem: TreeSitterQuerySubItem,
) {
  if ("type" in subQueryItem) {
    if (!toArr(subQueryItem.type).some((t) => t === node.type)) {
      return false;
    }
  } else if ("field" in subQueryItem) {
    if (
      !toArr(subQueryItem.field).some(
        (f) => node.parent && getField(node.parent, f) === node,
      )
    ) {
      return false;
    }
  } else if ("wildcard" in subQueryItem) {
  } else {
    const exhaustiveCheck: never = subQueryItem;
    throw new Error(`Unhandled case: ${exhaustiveCheck}`);
  }
  if (
    subQueryItem.text &&
    (typeof subQueryItem.text === "string"
      ? node.text !== subQueryItem.text
      : !subQueryItem.text.test(node.text))
  ) {
    return false;
  }
}
type MatchAll<QueryItem extends TreeSitterQueryItem> = {
  remainingCounter: number;
  callback: (params: QueryCaptures<QueryItem>) => void | { skip: boolean };
};
function matchSubRecursive<QueryItem extends TreeSitterQueryItem>(
  node: Parser.SyntaxNode,
  subQueryItem: TreeSitterQuerySubItem,
  captures: Record<string, Parser.SyntaxNode>,
  matchAll: MatchAll<QueryItem> | undefined,
): boolean {
  const shouldReturn = checkSubQueryItem(node, subQueryItem);
  if (typeof shouldReturn === "boolean") {
    return shouldReturn;
  }
  subQueryItem.onFound?.(node);

  if (subQueryItem.capture) {
    if (!matchAll && captures[subQueryItem.capture as any]) {
      throw new Error("duplicate capture name found: " + subQueryItem.capture);
    }
    captures[subQueryItem.capture as any] = node;
  }

  const items = "items" in subQueryItem ? subQueryItem.items : undefined;
  if (!items) {
    if (matchAll) {
      matchAll.remainingCounter -= 1;
      if (matchAll.remainingCounter === 0) {
        matchAll.callback({ ...captures } as any);
        return false;
      }
    }
    return true;
  } else {
    if (matchAll) {
      matchAll.remainingCounter += items.length - 1;
    }
    return items.every((item) => {
      let match = item.optional ?? false;
      for (const child of node.namedChildren) {
        if (matchSubRecursive(child, item, captures, matchAll)) {
          if (matchAll) {
            match = true;
          } else {
            return true;
          }
        }
      }
      return match;
    });
  }
}

export function getField(
  node: Parser.SyntaxNode,
  fieldName: string,
): Parser.SyntaxNode | void {
  // Also get all fields with node.fields
  const resolvedFieldName = fieldName.endsWith("Node")
    ? fieldName
    : fieldName + "Node";
  // @ts-expect-error - https://github.com/tree-sitter/node-tree-sitter/issues/54
  return node[resolvedFieldName];
}

function toArr<T>(arr: T | readonly T[]): readonly T[];
function toArr<T>(arr: T | T[]): T[] {
  return Array.isArray(arr) ? arr : [arr];
}

type TreeSitterQuerySubItem<Capture extends string = string> = (
  | {
      type: string | ReadonlyArray<string>;
      items?: ReadonlyArray<TreeSitterQuerySubItem<Capture>>;
    }
  | { wildcard: true }
  | {
      field: string | ReadonlyArray<string>;
      items?: ReadonlyArray<TreeSitterQuerySubItem<Capture>>;
    }
) & {
  capture?: Capture;
  text?: string | RegExp;
  optional?: boolean;
  onFound?: (node: Parser.SyntaxNode) => void;
};
export type TreeSitterQueryItem<Capture extends string = string> = {
  type: string | ReadonlyArray<string>;
  capture?: Capture;
  items?: ReadonlyArray<TreeSitterQuerySubItem<Capture>>;
  captureAll?: boolean;
  onFound?: (node: Parser.SyntaxNode) => void;
};
type QueryCapturesName<T extends TreeSitterQueryItem> =
  T extends TreeSitterQueryItem<infer Captures> ? Captures : never;
export type QueryCaptures<T extends TreeSitterQueryItem> = {
  [captures in QueryCapturesName<T>]: Parser.SyntaxNode;
};