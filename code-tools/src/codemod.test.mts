import { runCodemod } from "./codemod.mjs";

describe("codemod", () => {
  it("should correctly modify expression and not comment", function () {
    expect(runTest()).to.equal(result);
  });
});

const source =
  "let x = 1;\n// comment console.log(x) not changed\nconsole.log(x);\nconsole.log(x);";
const result =
  "let x = 1;\n// comment console.log(x) not changed\nlogger.info(x);\nlogger.info(x);";
function runTest() {
  const query = {
    type: "expression_statement",
    capture: "expression",
    items: [
      {
        type: "call_expression",
        items: [
          { field: "function", capture: "callName", text: "console.log" },
        ],
      },
    ],
  } as const;
  const result = runCodemod({
    source,
    query,
    onCapture: (captures) => {
      return {
        startIndex: captures.callName.startIndex,
        endIndex: captures.callName.endIndex,
        newText: "logger.info",
      };
    },
  });
  return result;
}