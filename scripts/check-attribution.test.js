import { expect, test } from "bun:test";
import { checkBranch, checkCommits, findAttribution } from "./check-attribution.mjs";

const vendor = ["cla", "ude"].join("");
const lab = ["anthro", "pic"].join("");
const assistant = ["co", "dex"].join("");
const pilot = ["co", "pilot"].join("");
const chat = ["chat", "gpt"].join("");
const openLab = ["open", "ai"].join("");

test("trailers, footers and vendor names are reported case-insensitively", () => {
  const text = [
    "Add feature",
    "",
    `Co-Authored-By: ${vendor} <noreply@${lab}.com>`,
    `🤖 Generated with [${vendor} Code](https://example.com)`,
    `Reviewed with ${assistant.toUpperCase()} and ${pilot}`,
    `${chat} said so, ${openLab} too`,
  ].join("\n");
  const names = findAttribution(text, "x").map((finding) => finding.split(": ")[1]);
  expect(names).toEqual([
    "co-authored trailer",
    "claude",
    "anthropic",
    "generated-with footer",
    "claude",
    "codex",
    "copilot",
    "chatgpt",
    "openai",
  ]);
});

test("word boundaries keep ordinary words and the app name clean", () => {
  const text = [
    "botch is a notch browser",
    "claudication is a medical term",
    "the copilots landed the plane",
    "a codexes shelf",
    "encoded with openaip formats",
  ].join("\n");
  expect(findAttribution(text, "x")).toEqual([]);
});

test("commit messages are reported with their short sha", () => {
  const commits = [
    { sha: "abcdef123456", message: `Fix\n\nCo-Authored-By: ${vendor} <x@y>` },
    { sha: "fedcba654321", message: "Tidy the Makefile" },
  ];
  expect(checkCommits(commits)).toEqual([
    "commit abcdef123456:3: co-authored trailer",
    "commit abcdef123456:3: claude",
  ]);
});

test("branch names with ai prefixes are rejected, others accepted", () => {
  for (const name of [`${vendor}/fix`, `${vendor}-fix`, "ai/thing", "ai-thing", `${pilot}/x`, "llm/x", `${lab}/x`]) {
    expect(checkBranch(name)).toHaveLength(1);
  }
  expect(checkBranch("strict-ci")).toEqual([]);
  expect(checkBranch("main")).toEqual([]);
  expect(checkBranch("aim/better")).toEqual([]);
  expect(checkBranch("")).toEqual([]);
});
