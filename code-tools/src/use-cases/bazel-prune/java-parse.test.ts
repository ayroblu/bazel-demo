import { parseJavaImportsExports } from "./java-parse.js";

describe("parseJavaImportExports", () => {
  it("should correctly extract java imports and exports", () => {
    const source = `
package com.example.zookeeper;

import java.net.InetSocketAddress;

import static com.google.common.base.Preconditions.checkNotNull;

public class ServerSet {
  public static final Amount<Integer,Time> DEFAULT_SD_SESSION_TIMEOUT = Amount.of(10, Time.SECONDS);
}
  `.trim();
    expect(parseJavaImportsExports(source)).to.deep.equal({
      imports: [
        "java.net.InetSocketAddress",
        "com.google.common.base.Preconditions.checkNotNull",
      ],
      exports: ["com.example.zookeeper.ServerSet", "com.example.zookeeper._"],
    });
  });
});
