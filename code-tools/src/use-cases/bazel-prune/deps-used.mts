export function depsUsed(
  targetGraph: TargetGraph,
  target: string,
): DepsUsedResult {
  const targetInfo = targetGraph[target];
  if (!targetInfo) throw new Error(`info for '${target}' not found`);
  const usedSet = new Set<string>();
  const importsSet = new Set(targetInfo.imports);
  for (const dep of targetInfo.deps) {
    const depInfo = targetGraph[dep];
    if (!depInfo) throw new Error(`info for '${dep}' not found`);
    for (const item of depInfo.exports) {
      if (importsSet.has(item)) {
        usedSet.add(dep);
        importsSet.delete(item);
      }
    }
  }
  const unusedStrict = targetInfo.deps.filter((d) => !usedSet.has(d));
  if (importsSet.size > 0) {
    // bfs all deps and check if imports uses it
    for (const dep of targetInfo.deps) {
      bfsImport(targetGraph, dep, importsSet, usedSet);
      if (importsSet.size === 0) break;
    }
  }
  const toRemove = targetInfo.deps.filter((d) => !usedSet.has(d));
  const transitives = unusedStrict.filter((d) => usedSet.has(d));
  return {
    toRemove,
    unknownImports: [...importsSet],
    transitives,
  };
}
function bfsImport(
  targetGraph: TargetGraph,
  originalDep: string,
  importsSet: Set<string>,
  usedSet: Set<string>,
) {
  let deps = targetGraph[originalDep].deps;
  while (deps.length) {
    const nextDeps: string[] = [];
    for (const dep of deps) {
      const info = targetGraph[dep];
      for (const item of info.exports) {
        if (importsSet.has(item)) {
          usedSet.add(originalDep);
          importsSet.delete(item);
          if (importsSet.size === 0) return;
        }
      }
      nextDeps.push(...info.deps);
    }
    deps = nextDeps;
  }
}

type TargetGraph = {
  [key: string]: {
    deps: string[];
    imports: string[];
    exports: string[];
  };
};
type DepsUsedResult = {
  toRemove: string[];
  unknownImports: string[];
  transitives: string[];
};
