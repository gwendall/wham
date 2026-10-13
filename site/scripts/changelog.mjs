// Writes the repo's CHANGELOG.md from the changelog in messages/en.json, the
// one wham.sh/changelog shows in English:
//
//   node scripts/changelog.mjs           rewrites ../CHANGELOG.md
//   node scripts/changelog.mjs --check   fails when it is not up to date
//
// The changelog is written for the people who use Wham, by hand, in
// messages/en.json and then in every other language. The release workflow takes
// a version's notes from CHANGELOG.md, and scripts/release.sh refuses a version
// it does not have. `--check` runs in `lint`.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const site = join(dirname(fileURLToPath(import.meta.url)), "..");
const target = join(site, "..", "CHANGELOG.md");
const { releases } = JSON.parse(readFileSync(join(site, "messages", "en.json"), "utf8")).changelog;

// The page's markup in Markdown: <code>wham on</code> is `wham on`.
function markdown(text) {
  const done = text.replace(/<code>(.*?)<\/code>/g, "`$1`");
  const left = done.match(/<(\w+)>.*?<\/\1>/);
  if (left) throw new Error(`changelog: no Markdown for <${left[1]}> in "${text}"`);
  return done;
}

const lines = [
  "# Changelog",
  "",
  "What changed in each version of Wham, newest first. Also on",
  "[wham.sh/changelog](https://wham.sh/changelog), in nine languages.",
  "",
  "<!-- Made by site/scripts/changelog.mjs from site/messages/en.json: edit the changelog there. -->",
];
for (const { version, date, items } of releases) {
  lines.push("", `## ${version} - ${date}`, "", ...items.map((item) => `- ${markdown(item)}`));
}
const text = `${lines.join("\n")}\n`;

if (process.argv.includes("--check")) {
  let current = "";
  try {
    current = readFileSync(target, "utf8");
  } catch {}
  if (current !== text) {
    console.error("changelog: CHANGELOG.md is not the changelog in messages/en.json. Run: node scripts/changelog.mjs");
    process.exit(1);
  }
  console.log("changelog: CHANGELOG.md is up to date");
} else {
  writeFileSync(target, text);
  console.log(`changelog: wrote CHANGELOG.md, ${releases.length} versions`);
}
