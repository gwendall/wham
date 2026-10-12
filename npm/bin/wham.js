#!/usr/bin/env node
// `npx wham.sh` installs or updates Wham, the menu bar app, with the same
// script as `curl -fsSL wham.sh | sh`. Anything after it goes to the `wham`
// command of the installed app: `npx wham.sh status`, `npx wham.sh on`.
"use strict";

const { spawnSync } = require("node:child_process");
const { existsSync } = require("node:fs");
const { homedir } = require("node:os");
const path = require("node:path");

const args = process.argv.slice(2);
const here = path.join(__dirname, "..");

function run(command, commandArgs) {
  const result = spawnSync(command, commandArgs, { stdio: "inherit" });
  if (result.error) {
    console.error(`wham.sh: ${result.error.message}`);
    process.exit(1);
  }
  process.exit(result.status === null ? 1 : result.status);
}

if (process.platform !== "darwin") {
  console.error("wham.sh: Wham is a macOS app.");
  process.exit(1);
}

if (args.length === 0 || args[0] === "install" || args[0] === "update") {
  run("/bin/sh", [path.join(here, "install.sh")]);
} else if (args[0] === "uninstall") {
  run("/bin/sh", [path.join(here, "uninstall.sh")]);
} else {
  const binary = ["/Applications", path.join(homedir(), "Applications")]
    .map((dir) => path.join(dir, "Wham.app", "Contents", "MacOS", "Wham"))
    .find((candidate) => existsSync(candidate));
  if (!binary) {
    console.error("wham.sh: Wham is not installed yet. Install it with: npx wham.sh");
    process.exit(1);
  }
  run(binary, args);
}
