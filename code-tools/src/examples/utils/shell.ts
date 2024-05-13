import { spawn } from "node:child_process";
import type { SpawnOptions } from "node:child_process";

export async function shell(
  cmd: string,
  options?: SpawnOptions,
): Promise<ShellReturn> {
  const child = spawn(cmd, {
    shell: "/bin/zsh",
    ...options,
  });
  let stdall = "";
  let stdout = "";
  child.stdout?.on("data", (data) => {
    stdout += data;
    stdall += data;
  });
  let stderr = "";
  child.stderr?.on("data", (data) => {
    stderr += data;
    stdall += data;
  });

  const exitCode: number = await new Promise((resolve) => {
    child.on("close", resolve);
  });

  if (exitCode) {
    throw new ShellError(`Non zero exit code for command "${cmd}"`, {
      code: exitCode,
      stdout,
      stderr,
      stdall,
    });
  }
  return { stdout, stderr, stdall };
}

export type ShellReturn = {
  stdout: string;
  stderr: string;
  stdall: string;
};
type ShellErrorData = {
  code: number;
  stdout: string;
  stderr: string;
  stdall: string;
};
class ShellError extends Error {
  code: number;
  stdout: string;
  stderr: string;
  stdall: string;
  constructor(message: string, data: ShellErrorData) {
    super(message);
    this.message = message;
    this.code = data.code;
    this.stdout = data.stdout;
    this.stderr = data.stderr;
    this.stdall = data.stdall;
  }
}
