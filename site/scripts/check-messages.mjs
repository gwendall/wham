// Holds every messages/<code>.json to English's: the same keys, the same list
// lengths, and in each string the same tags (<code>, <github>...) and
// placeholders ({command}), so no language loses a link or a command. Also
// refuses empty strings, the em and en dashes, and a wordmark the pixel font
// cannot draw, and keeps each release's version and date as English has them.
// Runs before `lint` and `build`.
import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const dir = join(dirname(fileURLToPath(import.meta.url)), "..", "messages");
const read = (file) => JSON.parse(readFileSync(join(dir, file), "utf8"));
const english = read("en.json");
const problems = [];

const marks = (text) =>
  [...text.matchAll(/<\/?\w+>|\{\w+\}/g)]
    .map(([mark]) => mark)
    .sort()
    .join(" ");

function compare(code, path, base, other) {
  const where = `${code}: ${path || "(root)"}`;
  if (typeof base === "string") {
    if (typeof other !== "string") return problems.push(`${where} should be a string`);
    if (base !== "" && other.trim() === "") problems.push(`${where} is empty`);
    if (/[\u2013\u2014]/.test(other)) problems.push(`${where} has an em or en dash`);
    if (path.endsWith(".wordmark") && !/^[A-Za-z0-9 ]+$/.test(other)) problems.push(`${where} is drawn in Silkscreen: Latin letters only`);
    if (/\.(version|date)$/.test(path) && other !== base) problems.push(`${where} is "${other}", English has "${base}"`);
    if (marks(base) !== marks(other)) problems.push(`${where} has "${marks(other)}", English has "${marks(base)}"`);
    return;
  }
  if (Array.isArray(base)) {
    if (!Array.isArray(other) || other.length !== base.length) return problems.push(`${where} should list ${base.length}`);
    return base.forEach((item, i) => compare(code, `${path}[${i}]`, item, other[i]));
  }
  if (typeof other !== "object" || other === null || Array.isArray(other)) return problems.push(`${where} should be an object`);
  for (const key of Object.keys(base)) {
    if (!(key in other)) problems.push(`${where}.${key} is missing`);
    else compare(code, path ? `${path}.${key}` : key, base[key], other[key]);
  }
  for (const key of Object.keys(other)) if (!(key in base)) problems.push(`${where}.${key} is not in English`);
}

const files = readdirSync(dir).filter((file) => file.endsWith(".json"));
for (const file of files) compare(file.replace(".json", ""), "", english, read(file));

if (problems.length) {
  console.error(problems.join("\n"));
  console.error(`check-messages: ${problems.length} problem(s)`);
  process.exit(1);
}
console.log(`check-messages: ${files.length} languages match English`);
