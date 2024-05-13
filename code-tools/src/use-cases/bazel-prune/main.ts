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
const item = bazelGraph["easypromote/server"];
const parsed = item.getParsed();
console.log("parsed", parsed["server"].deps);
for (const dep of parsed["server"].deps) {
  const [baseTarget, targetMaybe] = splitTarget(dep);
  const target = targetMaybe ?? basename(baseTarget);
  const item = bazelGraph[baseTarget];
  if (!item) {
    console.log("missing!", item);
    continue;
  }
  const details = item.getParsed()[target];
  const { sources, deps } = details;
  const allImports = new Set<string>();
  if (sources) {
    for (const source of sources) {
      const files = await glob(source, { cwd: resolve(baseTarget) });
      for (const file of files) {
        const contents = readFileSync(join(baseTarget, file), "utf-8");
        const { imports } = parseScalaImportsExports(contents);
        for (const imp of imports) {
          allImports.add(imp);
        }
      }
      console.log("files", files);
    }
  }
  const unaccountedImports = new Set([...allImports]);
  const seen = new Set<string>();
  for (const dep of deps) {
    // console.log("dep", dep);
    const result = await getExports(dep, { seen });
    if (!result) continue;
    const { allExports } = result;
    if (!allExports.some((exp) => allImports.has(exp))) {
      console.log("unused", dep);
    } else {
      // console.log("used", dep);
      for (const exp of allExports) {
        unaccountedImports.delete(exp);
      }
    }
  }
  console.log("unaccounted imports", [...unaccountedImports]);
}

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
  const isFound = dep.includes("example/path");
  if (isFound) {
    console.log(" ".repeat(depth * 2), "found!", dep);
  }
  const [baseTarget, targetMaybe] = splitTarget(dep);
  const target = targetMaybe ?? basename(baseTarget);
  const item = bazelGraph[baseTarget];
  if (!item) {
    console.log(" ".repeat(depth * 2), "not found!", dep);
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
      if (file.endsWith(".scala")) {
        const contents = readFileSync(join(baseTarget, file), "utf-8");
        const { exports } = parseScalaImportsExports(contents);
        directExports.push(...exports);
      } else if (file.endsWith(".thrift")) {
        const contents = readFileSync(join(baseTarget, file), "utf-8");
        const { exports } = parseThriftImportsExports(contents);
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
