// - For every scala file, get its exports and imports
// - For every bazel file get its imports
// identify if a bazel import is unused

import { readFileSync } from "node:fs";
import { shell } from "../../examples/utils/shell.js";
import { parseBazelScalaLib, type ParsedBazel } from "./bazel-parse.js";
import { basename, dirname, join, resolve } from "node:path";
import { glob } from "glob";
import { parseScalaImportsExports } from "./scala-parse.js";
import { parseThriftImportsExports } from "./thrift-parse.js";
import { parseJavaImportsExports } from "./java-parse.js";
import { createCacheManager } from "./cache.js";

// Only trim scala_libs
const { stdout } = await shell("git ls-files");
console.log("grabbed all files");
const allFiles = stdout.split("\n").filter((a) => a);
const bazelFiles = allFiles.filter(
  (a) => a.endsWith("BUILD") || a.endsWith("BUILD.bazel"),
);
console.log("found", bazelFiles.length, "bazel files");

const bazelContents = bazelFiles.map((filename) => {
  const baseTarget = dirname(filename);
  let parsed: Record<string, ParsedBazel>;
  function getParsed() {
    if (!parsed) {
      const source = readFileSync(filename, "utf8");
      parsed = parseBazelScalaLib(source, { baseTarget });
    }
    return parsed;
  }
  return {
    filename,
    getParsed,
    baseTarget,
  };
});
type Contents = (typeof bazelContents)[number];
const bazelGraph = bazelContents.reduce<Record<string, Contents>>(
  (map, next) => {
    map[next.baseTarget] = next;
    return map;
  },
  {},
);

function splitTarget(target: string): [string, string] {
  return target.split(":") as [string, string];
}
const cache = createCacheManager<ImportExports | undefined>();
// Read a file, for all scala libs in the file do:
// read all imports and deps
const relevantFiles = bazelContents.filter(({ baseTarget }) =>
  baseTarget.startsWith("finatra"),
);
for (const { baseTarget } of relevantFiles) {
  const item = bazelGraph[baseTarget];
  if (!item) {
    console.log("missing!", baseTarget);
    continue;
  }
  const entries = Object.entries(item.getParsed());
  for (const [target, details] of entries) {
    const { sources, deps, type, strictDeps } = details;
    if (type !== "scala-lib") continue;

    const allImports = new Set<string>();
    if (sources) {
      for (const source of sources) {
        const files = await glob(source, { cwd: resolve(baseTarget) });
        for (const file of files) {
          const filename = join(baseTarget, file);
          const result = cache.get(filename, () => {
            const contents = readFileSync(filename, "utf-8");
            return parseScalaImportsExports(contents);
          });
          if (!result) continue;
          const { imports } = result;
          for (const imp of imports) {
            allImports.add(imp);
          }
        }
      }
    }
    const unaccountedImports = new Set([...allImports]);
    const seen = new Set<string>();
    const unused: string[] = [];
    const transitives: (() => void)[] = [];
    const allExportsAllDeps: string[][] = [];
    for (const dep of deps) {
      // console.log("dep", dep);
      const result = await getExports(dep, { seen });
      if (!result) continue;
      const { allExports, directExports } = result;
      allExportsAllDeps.push(allExports);
      if (!directExports.some((exp) => allImports.has(exp))) {
        // strictDeps doesnt work yet
        if (strictDeps && false) {
          unused.push(dep);
        } else {
          transitives.push(() => {
            if (!allExports.some((exp) => allImports.has(exp))) {
              unused.push(dep);
            }
          });
        }
      }
    }
    for (const transitive of transitives) {
      transitive();
    }
    const allExports = allExportsAllDeps.flat();
    for (const exp of allExports) {
      unaccountedImports.delete(exp);
    }
    if (unused.length) {
      console.log("unused", baseTarget, target, unused);
      console.log("  unaccounted:", [...unaccountedImports]);
    }
  }
}

type ImportExports = {
  exports: string[];
  imports: string[];
};
type ExportResult = {
  directExports: string[];
  transitiveExports: string[];
  allExports: string[];
};
async function getExports(
  dep: string,
  { depth = 0, seen = new Set() }: { depth?: number; seen?: Set<string> } = {},
): Promise<ExportResult | undefined> {
  if (seen.has(dep)) {
    return;
  }
  seen.add(dep);
  const isFound = dep.includes("example/main");
  if (isFound) {
    console.log(" ".repeat(depth * 2), "found!", dep);
  }
  const [baseTarget, targetMaybe] = splitTarget(dep);
  const target = targetMaybe ?? basename(baseTarget);
  const item = bazelGraph[baseTarget];
  if (!item) {
    // console.log(" ".repeat(depth * 2), "not found!", dep);
    return;
  }
  const details = item.getParsed()[target];
  if (isFound) {
    console.log(" ".repeat(depth * 2), "details", details);
  }
  if (!details) {
    // console.log(" ".repeat(depth * 2), "not a scala target", dep, target);
    if (isFound) {
      console.log(" ".repeat(depth * 2), "not a scala target", dep, target);
    }
    return;
  }
  const { sources, deps } = details;
  if (!sources) {
    if (deps.length === 1) {
      const dep = deps[0];
      return getExports(dep, { depth: depth + 1, seen });
    } else {
      return Promise.all(
        deps.map((dep) => {
          return getExports(dep, { depth: depth + 1, seen });
        }),
      ).then((a) => {
        return a.reduce<ExportResult>(
          (map, next) => {
            if (next) {
              map.directExports.push(...next.directExports);
              map.transitiveExports.push(...next.transitiveExports);
              map.allExports.push(...next.allExports);
            }
            return map;
          },
          { transitiveExports: [], directExports: [], allExports: [] },
        );
      });
    }
  }
  const directExports: string[] = [];
  for (const source of sources) {
    const files = await glob(source, { cwd: resolve(baseTarget) });
    for (const file of files) {
      const filename = join(baseTarget, file);
      const result = cache.get(filename, () => {
        if (file.endsWith(".scala")) {
          const contents = readFileSync(filename, "utf-8");
          return parseScalaImportsExports(contents);
        } else if (file.endsWith(".thrift")) {
          const contents = readFileSync(filename, "utf-8");
          return parseThriftImportsExports(contents);
        } else if (file.endsWith(".java")) {
          const contents = readFileSync(filename, "utf-8");
          return parseJavaImportsExports(contents);
        }
      });
      if (result) {
        const { exports } = result;
        directExports.push(...exports);
      }
    }
  }
  if (isFound) {
    console.log(directExports);
  }
  const transitiveExports: string[] = [];
  if (deps && deps.length) {
    for (const dep of deps) {
      const result = await getExports(dep, {
        depth: depth + 1,
        seen,
      });
      if (result) {
        const { allExports } = result;
        transitiveExports.push(...allExports);
      }
    }
  }
  const allExports = [...directExports, ...transitiveExports];
  return { directExports, transitiveExports, allExports };
}
