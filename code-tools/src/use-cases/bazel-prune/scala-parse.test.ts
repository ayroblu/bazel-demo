import { parseScalaImportsExports } from "./scala-parse.js";

describe("parseScalaImportExports", () => {
  it("should correctly extract scala imports and exports", () => {
    const source = `
package com.example.executable

import com.example.server.Server
import com.example.server.Server.Item
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
        "com.example.executable._",
      ],
    });
  });

  it("should correctly extract scala package objects", () => {
    const source = `
package com.example

package object service {
  type RequestFilter[A] = request.RequestFilter[A]
  val RequestFilter = request.RequestFilter
}
  `.trim();
    expect(parseScalaImportsExports(source)).to.deep.equal({
      imports: [],
      exports: [
        "com.example._",
        "com.example.service._",
        "com.example.service.RequestFilter",
        "com.example.service.RequestFilter",
      ],
    });
  });
});
