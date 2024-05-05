// await shell('git ls-files .');
// filter to just js / ts files
// get all imports from file

import { existsSync } from "node:fs";
import { shell } from "../../examples/utils/shell.mjs";

// get all exports from file
async function run() {
  const { stdout } = await shell("git ls-files .");
  const files = stdout
    .split("\n")
    .filter((f) => f)
    .filter((f) => existsSync(f));
  const graph: Map<string, ImportsExports> = new Map();
}

type ImportsExports = {
  filepath: string;
  imports: Import[];
  exports: Export[];
};
type Import = {
  filepath: string;
  symbol: string;
};
type Export = {
  symbol: string;
};
