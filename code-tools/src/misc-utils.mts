import * as url from "node:url";

export function isMainScript(importMetaUrl: string) {
  if (importMetaUrl.startsWith("file:")) {
    const modulePath = url.fileURLToPath(importMetaUrl);
    return process.argv[1] === modulePath;
  }
}
