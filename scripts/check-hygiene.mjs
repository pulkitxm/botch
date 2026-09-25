import { execSync } from "node:child_process";
import { readFileSync, statSync } from "node:fs";
import { BINARY_EXTENSIONS, readText, report, trackedFiles } from "./tracked.mjs";

export const SIZE_LIMIT = 1024 * 1024;
export const LARGE_FILE_ALLOWED = /^(Resources\/AppIcon\.icns|docs\/[^/]+\.png|desktop\/src-tauri\/icons\/.+)$/;
export const EXECUTABLE_ALLOWED = /^(install\.sh|scripts\/[^/]+\.sh)$/;

export function textFindings(file, text) {
  const findings = [];
  if (text.includes("\r")) findings.push(`${file}: CRLF line endings`);
  if (text.length > 0 && !text.endsWith("\n")) findings.push(`${file}: missing final newline`);
  if (text.endsWith("\n\n")) findings.push(`${file}: trailing blank lines`);
  if (text.charCodeAt(0) === 0xfeff) findings.push(`${file}: byte order mark`);
  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    if (/[ \t]+$/.test(lines[i])) findings.push(`${file}:${i + 1}: trailing whitespace`);
  }
  return findings;
}

export function duplicateJSONKeys(text) {
  const duplicates = [];
  const stack = [];
  let i = 0;
  let pendingKey = null;
  while (i < text.length) {
    const c = text[i];
    if (c === '"') {
      let j = i + 1;
      while (j < text.length && text[j] !== '"') {
        if (text[j] === "\\") j++;
        j++;
      }
      const value = text.slice(i + 1, j);
      i = j + 1;
      const top = stack[stack.length - 1];
      if (top && top.expectKey) {
        pendingKey = value;
        top.expectKey = false;
      }
      continue;
    }
    if (c === "{") stack.push({ keys: new Set(), expectKey: true });
    else if (c === "[") stack.push({ keys: null, expectKey: false });
    else if (c === "}" || c === "]") stack.pop();
    else if (c === ":" && pendingKey !== null) {
      const top = stack[stack.length - 1];
      if (top?.keys) {
        if (top.keys.has(pendingKey)) duplicates.push({ key: pendingKey, line: text.slice(0, i).split("\n").length });
        top.keys.add(pendingKey);
      }
      pendingKey = null;
    } else if (c === ",") {
      const top = stack[stack.length - 1];
      if (top?.keys) top.expectKey = true;
    }
    i++;
  }
  return duplicates;
}

export function checkFiles(files, cwd = process.cwd()) {
  const findings = [];
  const modes = new Map(
    execSync("git ls-files -s", { cwd, encoding: "utf8" })
      .split("\n")
      .filter(Boolean)
      .map((row) => {
        const [mode, , , ...path] = row.split(/\s+/);
        return [path.join(" "), mode];
      }),
  );
  for (const file of files) {
    const size = statSync(file).size;
    if (size > SIZE_LIMIT && !LARGE_FILE_ALLOWED.test(file)) findings.push(`${file}: ${size} bytes exceeds 1 MB`);
    const executable = modes.get(file) === "100755";
    if (executable && !EXECUTABLE_ALLOWED.test(file)) findings.push(`${file}: executable bit on a non-script`);
    if (!executable && EXECUTABLE_ALLOWED.test(file)) findings.push(`${file}: script is not executable`);
    if (BINARY_EXTENSIONS.test(file)) continue;
    const text = readText(file);
    if (text === null) {
      findings.push(`${file}: binary content without a known binary extension`);
      continue;
    }
    findings.push(...textFindings(file, text));
    if (/\.(json|jsonc)$|(^|\/)\.swift-format$/.test(file)) {
      for (const { key, line } of duplicateJSONKeys(text)) findings.push(`${file}:${line}: duplicate key "${key}"`);
    }
  }
  return findings;
}

export function plistFindings(text) {
  const findings = [];
  const flag = (key) => {
    const re = new RegExp(`<key>${key}</key>\\s*<(true|false)/>`);
    return re.exec(text)?.[1] ?? null;
  };
  if (flag("LSUIElement") !== "true") findings.push("Info.plist: LSUIElement must be true");
  if (flag("NSAllowsArbitraryLoadsInWebContent") !== "true") {
    findings.push("Info.plist: NSAppTransportSecurity.NSAllowsArbitraryLoadsInWebContent must be true");
  }
  if (!text.includes("<key>NSAppTransportSecurity</key>")) findings.push("Info.plist: NSAppTransportSecurity missing");
  return findings;
}

if (import.meta.main) {
  const findings = checkFiles(trackedFiles());
  findings.push(...plistFindings(readFileSync("Resources/Info.plist", "utf8")));
  report("check-hygiene", findings);
}
