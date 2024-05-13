import { existsSync } from "node:fs";
import { shell } from "../../examples/utils/shell";

// get all exports from file
const { stdout } = await shell("git ls-files .");
const supportedExtensions = [".ts", ".mts", ".tsx"];
const files = stdout
  .split("\n")
  .filter((f) => f && supportedExtensions.some((ext) => f.endsWith(ext)))
  .filter((f) => existsSync(f));
const graph: Map<string, ImportsExports> = new Map();

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
