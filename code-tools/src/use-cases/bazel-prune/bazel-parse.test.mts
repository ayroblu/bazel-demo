import { parseBazelScalaLib } from "./bazel-parse.mjs";

describe("parseBazelScalaLib", () => {
  it("should correctly parse scala_library", () => {
    const source = `
scala_library(
  sources=["*.scala"],
  dependencies=[
    "path/to/dep",
    "path/to/dep2",
  ],
)
  `.trim();
    expect(parseBazelScalaLib(source)).to.deep.equal([
      {
        sources: ["*.scala"],
        deps: ["path/to/dep", "path/to/dep2"],
        target: undefined,
      },
    ]);
  });
});
