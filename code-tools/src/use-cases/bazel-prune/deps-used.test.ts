import { depsUsed } from "./deps-used.js";

describe("depsUsed", () => {
  it("should identify dependencies used for a bazel file", () => {
    const bazelTargetGraph = {
      main: {
        deps: ["a", "b", "c"],
        imports: ["com.example.A", "com.example.D"],
        exports: [],
      },
      a: {
        deps: [],
        imports: [],
        exports: ["com.example.A"],
      },
      b: {
        deps: ["d"],
        imports: [],
        exports: ["com.example.B"],
      },
      c: {
        deps: [],
        imports: [],
        exports: ["com.example.C"],
      },
      d: {
        deps: [],
        imports: [],
        exports: ["com.example.D"],
      },
    };
    const deps = depsUsed(bazelTargetGraph, "main");
    expect(deps).to.deep.equal({
      toRemove: ["c"],
      unknownImports: [],
      transitives: ["b"],
    });
  });
});
