import { parseScalaImportsExports } from "./scala-parse.mjs";

describe("parseScalaImportExports", () => {
  it("should correctly extract scala imports and exports", () => {
    const source = `
package com.example.executable

import com.example.server.Server
import com.example.server.types._
import com.example.server.{Cache => RedisCache,Kafka}

case class DataType(id: String, name: String)
class Runner {}
sealed trait Variant
case object Yes extends Variant
case object No extends Variant
object Helper {}
  `.trim();
    expect(parseScalaImportsExports(source)).to.deep.equal({
      imports: [
        "com.example.server.Server",
        "com.example.server.types._",
        "com.example.server.Cache",
        "com.example.server.Kafka",
      ],
      exports: [
        "com.example.executable.DataType",
        "com.example.executable.Runner",
        "com.example.executable.Variant",
        "com.example.executable.Yes",
        "com.example.executable.No",
        "com.example.executable.Helper",
      ],
    });
  });
});
