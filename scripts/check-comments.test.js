import { expect, test } from "bun:test";
import {
  cssComments,
  hashComments,
  htmlComments,
  jsComments,
  jsonComments,
  rustComments,
  scan,
  scannerFor,
  swiftComments,
  yamlComments,
} from "./check-comments.mjs";

const count = (result) => [result.findings.length, result.kept];

test("swift: line and block comments are findings, directives are kept", () => {
  expect(count(swiftComments('let u = "https://x.com" // c'))).toEqual([1, 0]);
  expect(count(swiftComments("/* a /* nested */ b */ let x = 1"))).toEqual([1, 0]);
  expect(count(swiftComments("/// doc\nfunc f() {}"))).toEqual([1, 0]);
  expect(count(swiftComments("// swift-tools-version:6.0\nimport X"))).toEqual([0, 1]);
  expect(count(swiftComments("// swiftlint:disable foo\nlet x = 1"))).toEqual([0, 1]);
  expect(count(swiftComments("// swift-format-ignore\nlet x = 1"))).toEqual([0, 1]);
});

test("swift: strings, raw strings and interpolation never look like comments", () => {
  expect(count(swiftComments('let r = #"a // b /* c */"#'))).toEqual([0, 0]);
  expect(count(swiftComments('let s = "\\(a)//x"'))).toEqual([0, 0]);
  expect(count(swiftComments('let m = """\n// nope\n"""'))).toEqual([0, 0]);
  expect(count(swiftComments('let m = #"""\n// nope\n"""#\nlet y = 1 // yes'))).toEqual([1, 0]);
  expect(count(swiftComments('let s = "\\(a /* n */)"'))).toEqual([1, 0]);
  expect(count(swiftComments("let a = 1 / 2"))).toEqual([0, 0]);
});

test("js: strings, templates and regex literals are skipped, comments are found", () => {
  const source = [
    'const url = "https://example.com";',
    "const re = /\\/\\/ literal/;",
    "const t = `a ${x + `//${y}`} // still string`;",
    "const q = a / b / c;",
    "// remove",
    "/* and this */",
  ].join("\n");
  expect(count(jsComments(source))).toEqual([2, 0]);
  expect(count(jsComments("// @ts-expect-error\nconst v = 1;"))).toEqual([0, 1]);
  expect(count(jsComments("// biome-ignore lint: x\nconst v = 1;"))).toEqual([0, 1]);
  expect(count(jsComments("// eslint-disable-next-line\nconst v = 1;"))).toEqual([0, 1]);
  expect(count(jsComments("/*! license */\nconst v = 1;"))).toEqual([0, 1]);
});

test("rust: attributes, lifetimes, chars and raw strings are code, comments are findings", () => {
  const source = [
    "#![allow(dead_code)]",
    "#[derive(Debug)]",
    "struct A<'a> { s: &'a str, c: char }",
    "fn f() { let c = '/'; let q = '\\''; let r = r#\"// not\"#; let u = \"http://x\"; }",
    "/// doc comment",
    "//! inner doc",
    "/* block /* nested */ */",
  ].join("\n");
  expect(count(rustComments(source))).toEqual([3, 0]);
});

test("css: block comments are findings unless they are license blocks", () => {
  expect(count(cssComments("a{color:#fff}/* x */"))).toEqual([1, 0]);
  expect(count(cssComments("/*! keep */a{}"))).toEqual([0, 1]);
  expect(count(cssComments('a{content:"/* not */"; background:url(//cdn/x.png)}'))).toEqual([0, 0]);
});

test("json: any slash comment outside a string is a finding", () => {
  expect(count(jsonComments('{\n// c\n"a": 1\n}'))).toEqual([1, 0]);
  expect(count(jsonComments('{"a": 1 /* c */}'))).toEqual([1, 0]);
  expect(count(jsonComments('{"url": "http://x", "path": "a//b"}'))).toEqual([0, 0]);
});

test("html: markup comments plus embedded script and style comments are findings", () => {
  const page = [
    "<!DOCTYPE html>",
    "<html><!-- markup --><head>",
    "<style>a{}/* css */</style>",
    '<script>const u = "http://x"; // js</script>',
    "</head><body><a href=\"/#top\">x</a></body></html>",
  ].join("\n");
  const result = htmlComments(page);
  expect(count(result)).toEqual([3, 0]);
  expect(result.findings.map((r) => page.slice(r.pos, r.end))).toEqual([
    "<!-- markup -->",
    "/* css */",
    "// js",
  ]);
});

test("yaml: hash comments are findings, strings and pin markers are not", () => {
  expect(count(yamlComments("a: 1 # c\n# top\nb: 2"))).toEqual([2, 0]);
  expect(count(yamlComments('color: "#fff"\nurl: https://x/#frag\nkey: it\'s#fine'))).toEqual([0, 0]);
  expect(count(yamlComments("run: |\n  echo hi # in block\nnext: 1"))).toEqual([0, 0]);
  const pinned = "      - uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0";
  expect(count(yamlComments(pinned))).toEqual([0, 1]);
  expect(count(yamlComments("      - uses: actions/checkout@v5 # v5.0.0"))).toEqual([1, 0]);
  expect(count(yamlComments("# yamllint disable rule:line-length\na: 1"))).toEqual([0, 1]);
});

test("shell and toml: shebang, shellcheck directives, strings and heredocs are not comments", () => {
  const script = [
    "#!/usr/bin/env bash",
    "# shellcheck disable=SC2034",
    'url="https://x/#frag" # trailing',
    "echo '#not' $# ${#arr}",
    "cat <<'EOF'",
    "# inside heredoc",
    "EOF",
    "# real",
  ].join("\n");
  expect(count(hashComments(script))).toEqual([2, 2]);
  const toml = ['name = "x" # c', 'color = "#fff"', "desc = '''\n# not\n'''", "[deps]"].join("\n");
  expect(count(hashComments(toml))).toEqual([1, 0]);
});

test("scannerFor picks a scanner by extension, basename or shebang", () => {
  expect(scannerFor("Sources/A.swift")).toBe(swiftComments);
  expect(scannerFor("desktop/src/main.rs")).toBe(rustComments);
  expect(scannerFor("Makefile")).toBe(hashComments);
  expect(scannerFor(".swift-format")).toBe(jsonComments);
  expect(scannerFor("Resources/Info.plist")).toBe(htmlComments);
  expect(scannerFor("bin/tool", "#!/bin/sh\necho")).toBe(hashComments);
  expect(scannerFor("README.md")).toBeNull();
  expect(scan("README.md", "<!-- prose -->").findings).toEqual([]);
});
