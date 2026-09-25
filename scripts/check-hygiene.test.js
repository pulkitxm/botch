import { expect, test } from "bun:test";
import { execSync } from "node:child_process";
import { chmodSync, mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { checkFiles, duplicateJSONKeys, plistFindings, textFindings } from "./check-hygiene.mjs";

test("text findings cover whitespace, newlines, CRLF and BOM", () => {
  expect(textFindings("a.txt", "clean\nfile\n")).toEqual([]);
  expect(textFindings("a.txt", "")).toEqual([]);
  expect(textFindings("a.txt", "x \ny\t\nz")).toEqual([
    "a.txt: missing final newline",
    "a.txt:1: trailing whitespace",
    "a.txt:2: trailing whitespace",
  ]);
  expect(textFindings("a.txt", "x\r\n")).toEqual(["a.txt: CRLF line endings"]);
  expect(textFindings("a.txt", "x\n\n")).toEqual(["a.txt: trailing blank lines"]);
  expect(textFindings("a.txt", "﻿x\n")).toEqual(["a.txt: byte order mark"]);
});

test("duplicate json keys are reported per object scope only", () => {
  expect(duplicateJSONKeys('{"a": 1, "b": {"a": 2}, "c": [{"a": 1}, {"a": 2}]}')).toEqual([]);
  expect(duplicateJSONKeys('{\n"a": 1,\n"b": "a",\n"a": 3\n}')).toEqual([{ key: "a", line: 4 }]);
  expect(duplicateJSONKeys('{"k\\"ey": 1, "k\\"ey": 2}')).toEqual([{ key: 'k\\"ey', line: 1 }]);
});

test("plist assertions require the notch app flags", () => {
  const good = [
    "<key>LSUIElement</key>",
    "<true/>",
    "<key>NSAppTransportSecurity</key>",
    "<dict><key>NSAllowsArbitraryLoadsInWebContent</key><true/></dict>",
  ].join("\n");
  expect(plistFindings(good)).toEqual([]);
  expect(plistFindings("<key>LSUIElement</key><false/>")).toEqual([
    "Info.plist: LSUIElement must be true",
    "Info.plist: NSAppTransportSecurity.NSAllowsArbitraryLoadsInWebContent must be true",
    "Info.plist: NSAppTransportSecurity missing",
  ]);
});

test("tracked files are checked for size, mode, binaries and duplicates", () => {
  const dir = mkdtempSync(join(tmpdir(), "hygiene-"));
  execSync("git init -q && git config user.email t@t && git config user.name t", { cwd: dir });
  mkdirSync(join(dir, "scripts"));
  mkdirSync(join(dir, "docs"));
  writeFileSync(join(dir, "scripts/ok.sh"), "#!/bin/sh\necho ok\n");
  chmodSync(join(dir, "scripts/ok.sh"), 0o755);
  writeFileSync(join(dir, "scripts/quiet.sh"), "#!/bin/sh\n");
  writeFileSync(join(dir, "notes.txt"), "text\n");
  chmodSync(join(dir, "notes.txt"), 0o755);
  writeFileSync(join(dir, "big.bin"), Buffer.alloc(1024 * 1024 + 1));
  writeFileSync(join(dir, "docs/shot.png"), Buffer.alloc(1024 * 1024 + 1, 1));
  writeFileSync(join(dir, "dup.json"), '{"a": 1, "a": 2}\n');
  writeFileSync(join(dir, "blob.dat"), Buffer.from([0, 1, 2]));
  execSync("git add -A", { cwd: dir });
  const files = ["scripts/ok.sh", "scripts/quiet.sh", "notes.txt", "big.bin", "docs/shot.png", "dup.json", "blob.dat"];
  const previous = process.cwd();
  process.chdir(dir);
  try {
    expect(checkFiles(files, dir).sort()).toEqual(
      [
        "scripts/quiet.sh: script is not executable",
        "notes.txt: executable bit on a non-script",
        "big.bin: 1048577 bytes exceeds 1 MB",
        "big.bin: binary content without a known binary extension",
        'dup.json:1: duplicate key "a"',
        "blob.dat: binary content without a known binary extension",
      ].sort(),
    );
  } finally {
    process.chdir(previous);
  }
});
