import { parseThriftImportsExports } from "./thrift-parse.js";

describe("parseThriftImportExports", () => {
  it("should correctly extract thrift imports and exports", () => {
    const source = `
namespace java com.example.thriftjava
#@namespace scala com.example.thriftscala

include "com/example/metric_types.thrift"

enum Platform {
  WEB = 1,
  ANDROID = 2,
  IOS = 3,
}

struct ExampleResponse {
  1: required bool isEligible;
} (hasPersonalData='true')

exception AccessDenied {
  1: required string message
}
typedef i16 FieldId
const i64 EXECUTE_AT_NEVER = -1
  `.trim();
    const packageExports = [
      "com.example.thriftjava",
      "com.example.thriftscala",
    ];
    const exportNames = [
      "Platform",
      "ExampleResponse",
      "AccessDenied",
      "FieldId",
      "EXECUTE_AT_NEVER",
    ];
    expect(parseThriftImportsExports(source)).to.deep.equal({
      imports: ["com/example/metric_types.thrift"],
      exports: packageExports.flatMap((namespace) =>
        exportNames.flatMap((name) => `${namespace}.${name}`),
      ),
      packageExports,
    });
  });
});
