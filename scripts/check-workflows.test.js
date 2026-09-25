import { expect, test } from "bun:test";
import { checkWorkflow } from "./check-workflows.mjs";

const sha = "08c6903cd8c0fde910a37f88322edcfb5dd907a8";

const good = [
  "name: CI",
  "on: [push]",
  "permissions:",
  "  contents: read",
  "jobs:",
  "  policy:",
  "    runs-on: ubuntu-latest",
  "    timeout-minutes: 10",
  "    permissions:",
  "      contents: read",
  "    steps:",
  `      - uses: actions/checkout@${sha} # v5.0.0`,
  "        with:",
  "          persist-credentials: false",
  "      - name: Bun",
  `        uses: oven-sh/setup-bun@${sha} # v2.2.0`,
  "        with:",
  "          bun-version: 1.4.2",
  "      - run: make ci",
  "  swift:",
  "    runs-on: macos-26",
  "    timeout-minutes: 30",
  "    permissions: {}",
  "    steps:",
  `      - uses: actions/checkout@${sha} # v5.0.0`,
  "        with:",
  "          fetch-depth: 0",
  "          persist-credentials: false",
  "",
].join("\n");

test("a fully pinned, permissioned workflow with timeouts is clean", () => {
  expect(checkWorkflow("ci.yml", good)).toEqual([]);
});

test("unpinned actions, missing comments, credentials, permissions and timeouts are reported", () => {
  const bad = [
    "name: CI",
    "on: [push]",
    "jobs:",
    "  a:",
    "    runs-on: ubuntu-latest",
    "    steps:",
    "      - uses: actions/checkout@v5",
    `      - uses: actions/setup-node@${sha}`,
    "      - name: Cache",
    `        uses: actions/cache@${sha} # v4.2.0`,
    "  b:",
    "    runs-on: ubuntu-latest",
    "    timeout-minutes: 5",
    "    permissions:",
    "      contents: read",
    "    steps:",
    `      - uses: actions/checkout@${sha} # v5.0.0`,
    "        with:",
    "          fetch-depth: 0",
    "",
  ].join("\n");
  expect(checkWorkflow("ci.yml", bad)).toEqual([
    "ci.yml:4: job a does not set permissions",
    "ci.yml:4: job a has no timeout-minutes",
    "ci.yml:7: uses actions/checkout@v5 is not pinned to a 40-char SHA with a version comment",
    "ci.yml:7: checkout without persist-credentials: false",
    `ci.yml:8: uses actions/setup-node@${sha} is not pinned to a 40-char SHA with a version comment`,
    "ci.yml:17: checkout without persist-credentials: false",
  ]);
});

test("a file without jobs is reported", () => {
  expect(checkWorkflow("x.yml", "name: X\n")).toEqual(["x.yml: no jobs section"]);
});
