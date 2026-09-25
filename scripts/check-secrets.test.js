import { expect, test } from "bun:test";
import { RULES, entropy, scanText } from "./check-secrets.mjs";

const pemHeader = ["-----BEGIN", "PRIVATE", "KEY-----"].join(" ");
const githubToken = "ghp_".concat("aB3dE6gH9jK2mN5pQ8sT1vW4yZ7bC0eF3hJ6kL9n");
const awsKey = "AKIA".concat("IOSFODNN7Q2R5T8W");
const seedLine = 'let seed = "'.concat("A".repeat(43), "=", '"');

test("rules cover keys, tokens and entropy assignments", () => {
  expect(RULES.length).toBeGreaterThanOrEqual(10);
  expect(entropy("aaaa")).toBe(0);
  expect(entropy("abcdefghijklmnop")).toBe(4);
});

test("private key block and vendor tokens fire with file and line", () => {
  expect(scanText(`x\n${pemHeader}\n`, "k.pem")).toEqual(["k.pem:2: private key block"]);
  expect(scanText(`token: ${githubToken}`, "ci.yml")).toEqual(["ci.yml:1: github token"]);
  expect(scanText(`key=${awsKey}`, ".env")).toEqual([".env:1: aws access key"]);
  expect(scanText(`import Foundation\n${seedLine}`, "A.swift")).toEqual([
    "A.swift:2: sparkle or ssh private seed",
  ]);
});

test("high-entropy assignments fire, low-entropy and placeholders do not", () => {
  const random = "q7Zp2Lm9Xc4Vb8Nk3Jh6Gf1Ds5Aw0Ry7Tu2Io9Pe";
  expect(scanText(`api_key = "${random}"`, "config.toml")).toEqual([
    "config.toml:1: high-entropy assignment",
  ]);
  expect(scanText(`password = "${"a".repeat(40)}"`, "x.toml")).toEqual([]);
  expect(scanText(`secret: "${"X".repeat(40)}"`, "x.yml")).toEqual([]);
  expect(scanText(`token = "${random}EXAMPLE"`, "x.toml")).toEqual([]);
});

test("ordinary source, urls and version placeholders are clean", () => {
  const text = [
    'let url = "https://example.com/keys?token=abc"',
    "<string>__VERSION__</string>",
    'let name = "botch"',
    "let sum = seed + offset",
    "sha256=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb",
  ].join("\n");
  expect(scanText(text, "A.swift")).toEqual([]);
});
