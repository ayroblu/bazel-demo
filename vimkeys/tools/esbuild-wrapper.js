#!/usr/bin/env node
const esbuild = require("esbuild");

const args = process.argv.slice(2);
const entry = args[0];
const outfile = args[1];

if (!entry || !outfile) {
  console.error("usage: esbuild-wrapper.js <entry> <outfile>");
  process.exit(2);
}

esbuild.build({
  entryPoints: [entry],
  bundle: true,
  outfile,
  platform: "browser",
  target: "es2020",
}).catch(() => process.exit(1));
