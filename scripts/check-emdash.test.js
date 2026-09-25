import { expect, test } from "bun:test";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { EM_DASH, checkCommits, checkFiles, findEmDashes } from "./check-emdash.mjs";

test("every em-dash is reported with its line", () => {
  const text = `plain\nfirst ${EM_DASH} here\nsecond ${EM_DASH} and ${EM_DASH}\n`;
  expect(findEmDashes(text, "doc.md")).toEqual([
    "doc.md:2: em-dash",
    "doc.md:3: em-dash",
    "doc.md:3: em-dash",
  ]);
});

test("hyphens, en-dashes and other unicode are fine", () => {
  expect(findEmDashes("a - b – c − d …", "x")).toEqual([]);
});

test("commit messages in a range are checked by short sha", () => {
  const commits = [
    { sha: "abcdef123456", message: "Fix thing\n\nBody ${EM_DASH} nope".replace("${EM_DASH}", EM_DASH) },
    { sha: "fedcba654321", message: "Clean subject" },
  ];
  expect(checkCommits(commits)).toEqual(["commit abcdef123456:3: em-dash"]);
});

test("files are read from disk and binaries are skipped", () => {
  const dir = mkdtempSync(join(tmpdir(), "emdash-"));
  const bad = join(dir, "bad.md");
  const binary = join(dir, "blob.bin");
  writeFileSync(bad, `title ${EM_DASH} subtitle\n`);
  writeFileSync(binary, Buffer.from([0, 0xe2, 0x80, 0x94]));
  expect(checkFiles([bad, binary])).toEqual([`${bad}:1: em-dash`]);
});
