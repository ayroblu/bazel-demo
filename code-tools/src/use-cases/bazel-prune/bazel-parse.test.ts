import { parseBazelScalaLib } from "./bazel-parse.js";

describe("parseBazelScalaLib", () => {
  it("should correctly parse scala_library", () => {
    const source = `
scala_library(
  sources=["*.scala", "other/thing.scala"],
  dependencies=[
    # TODO remove
    "path/to/dep",
    "path/to/dep2",
    ":special",
  ],
)

scala_library(
  name="special",
  sources=["other/thing.scala"],
  dependencies=[
    "path/to/dep",
  ],
)
  `.trim();
    expect(
      parseBazelScalaLib(source, { baseTarget: "path/to/example" }),
    ).to.deep.equal({
      example: {
        sources: ["*.scala", "other/thing.scala"],
        deps: ["path/to/dep", "path/to/dep2", "path/to/example:special"],
        target: "example",
      },
      special: {
        sources: ["other/thing.scala"],
        deps: ["path/to/dep"],
        target: "special",
      },
    });
  });

  it("should correctly parse scala_library with variables", () => {
    const source = `
scala_library(
  sources = ["**/*.scala"] + exclude_globs(THRIFT_VALIDATION),
  dependencies=[
    "path/to/dep",
  ],
)
  `.trim();
    expect(
      parseBazelScalaLib(source, { baseTarget: "path/to/example" }),
    ).to.deep.equal({
      example: {
        sources: ["**/*.scala"],
        deps: ["path/to/dep"],
        target: "example",
      },
    });
  });

  it("should correctly parse thrift library", () => {
    const source = `
create_thrift_libraries(
    base_name = "external",
    sources = ["com/example/external/*.thrift"],
    dependency_roots = [
        "example/thrift/src/main/thrift",
    ],
    generate_languages = [
        "java",
        "scala",
    ],
)

  `.trim();
    expect(
      parseBazelScalaLib(source, { baseTarget: "path/to/example" }),
    ).to.deep.equal({
      "external-java": {
        sources: ["com/example/external/*.thrift"],
        deps: ["example/thrift/src/main/thrift"],
        target: "external-java",
      },
      "external-scala": {
        sources: ["com/example/external/*.thrift"],
        deps: ["example/thrift/src/main/thrift"],
        target: "external-scala",
      },
    });
  });

  it("should correctly parse alias", () => {
    const source = `
alias(
    name = "example-core",
    target = "example/example-core/src/main/scala/com/example",
)
  `.trim();
    expect(
      parseBazelScalaLib(source, { baseTarget: "example/example-core" }),
    ).to.deep.equal({
      "example-core": {
        sources: undefined,
        deps: ["example/example-core/src/main/scala/com/example"],
        target: "example-core",
      },
    });
  });
});
