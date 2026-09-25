import { execSync } from "node:child_process";
import { readFileSync } from "node:fs";

export const EXCLUDED =
  /(^|\/)(\.build|dist|\.worktrees|node_modules|target)\/|^LICENSE$|^docs\/[^/]+\.png$|(^|\/)(bun\.lock|package-lock\.json|Cargo\.lock|Package\.resolved)$/;

export const BINARY_EXTENSIONS = /\.(png|jpe?g|gif|icns|ico|webp|pdf|zip|dmg|gz|tgz|woff2?|ttf|otf|mp4|mov|wasm|a|dylib|so)$/i;

export function trackedFiles(cwd = process.cwd()) {
  return execSync("git ls-files -z", { cwd, encoding: "utf8" })
    .split("\0")
    .filter(Boolean)
    .filter((file) => !EXCLUDED.test(file));
}

export function readText(file) {
  if (BINARY_EXTENSIONS.test(file)) return null;
  const bytes = readFileSync(file);
  if (bytes.includes(0)) return null;
  return bytes.toString("utf8");
}

export function commitMessages(range, cwd = process.cwd()) {
  const log = execSync(`git log --format=%H%x1f%B%x1e ${range}`, { cwd, encoding: "utf8" });
  return log
    .split("\x1e")
    .map((entry) => entry.trim())
    .filter(Boolean)
    .map((entry) => {
      const [sha, ...body] = entry.split("\x1f");
      return { sha: sha.slice(0, 12), message: body.join("\x1f") };
    });
}

export function lineOf(text, pos) {
  let line = 1;
  for (let i = 0; i < pos && i < text.length; i++) if (text[i] === "\n") line++;
  return line;
}

export function report(name, findings) {
  for (const finding of findings) console.log(finding);
  if (findings.length > 0) {
    console.error(`${name}: ${findings.length} finding(s)`);
    process.exit(1);
  }
  console.log(`${name}: clean`);
}
