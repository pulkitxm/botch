import { lineOf, readText, report, trackedFiles } from "./tracked.mjs";

const SLASH_DIRECTIVES = [
  /^swift-tools-version\b/,
  /^swiftlint:/,
  /^swift-format-/,
  /^@(ts-ignore|ts-expect-error|ts-nocheck|ts-check)\b/,
  /^eslint-(disable|enable)(-next-line|-line)?\b/,
  /^biome-ignore\b/,
  /^prettier-ignore\b/,
  /^#\s*source(MappingURL|URL)\b/,
  /^@vite-ignore\b/,
  /^@(jsx|jsxImportSource|jsxRuntime|jsxFrag)\b/,
  /^<(reference|amd-)/,
];

const HASH_DIRECTIVES = [/^shellcheck\s/, /^yamllint\b/, /^yaml-language-server\b/];

const PIN_MARKER = /^\s*(-\s+)?uses:\s*\S+@[0-9a-f]{40}\s+# v?\d[\w.-]*\s*$/;

export function keepSlash(raw) {
  if (raw.startsWith("/*!")) return true;
  const inner = raw.startsWith("//") ? raw.replace(/^\/\/+/, "") : raw.slice(2, -2);
  const text = inner.trim().replace(/^\*+\s*/, "");
  return SLASH_DIRECTIVES.some((directive) => directive.test(text));
}

function keepHash(text, pos, line) {
  if (pos === 0 && text.startsWith("#!")) return true;
  if (PIN_MARKER.test(line)) return true;
  const inner = line.slice(line.indexOf("#") + 1).trim();
  return HASH_DIRECTIVES.some((directive) => directive.test(inner));
}

function lineComment(text, start) {
  let i = start + 2;
  while (i < text.length && text[i] !== "\n") i++;
  return i;
}

function blockComment(text, start, nested) {
  let i = start + 2;
  let depth = 1;
  while (i < text.length && depth > 0) {
    if (nested && text[i] === "/" && text[i + 1] === "*") {
      depth++;
      i += 2;
    } else if (text[i] === "*" && text[i + 1] === "/") {
      depth--;
      i += 2;
    } else i++;
  }
  return i;
}

function finish(text, found, keep) {
  const findings = [];
  let kept = 0;
  for (const range of found) {
    if (keep(text.slice(range.pos, range.end), range.pos)) kept++;
    else findings.push(range);
  }
  return { findings, kept };
}

export function swiftComments(text) {
  const n = text.length;
  const stack = [{ kind: "code", interp: false, paren: 0 }];
  const found = [];
  const has = (i, s) => text.startsWith(s, i);
  let i = 0;
  while (i < n) {
    const ctx = stack[stack.length - 1];
    const c = text[i];
    if (ctx.kind === "string") {
      if (c === "\\") {
        let j = i + 1;
        let hashes = 0;
        while (text[j] === "#") {
          hashes++;
          j++;
        }
        if (hashes === ctx.hashes && text[j] === "(") {
          stack.push({ kind: "code", interp: true, paren: 0 });
          i = j + 1;
        } else i += ctx.hashes === 0 ? 2 : 1;
        continue;
      }
      if (c === '"') {
        const closer = (ctx.multiline ? '"""' : '"') + "#".repeat(ctx.hashes);
        if (has(i, closer)) {
          stack.pop();
          i += closer.length;
          continue;
        }
      }
      i++;
      continue;
    }
    if (c === "#") {
      let j = i;
      while (text[j] === "#") j++;
      if (text[j] === '"') {
        const multiline = has(j, '"""');
        stack.push({ kind: "string", hashes: j - i, multiline });
        i = j + (multiline ? 3 : 1);
      } else i = j;
      continue;
    }
    if (c === '"') {
      const multiline = has(i, '"""');
      stack.push({ kind: "string", hashes: 0, multiline });
      i += multiline ? 3 : 1;
      continue;
    }
    if (c === "/" && text[i + 1] === "/") {
      const end = lineComment(text, i);
      found.push({ pos: i, end });
      i = end;
      continue;
    }
    if (c === "/" && text[i + 1] === "*") {
      const end = blockComment(text, i, true);
      found.push({ pos: i, end });
      i = end;
      continue;
    }
    if (ctx.interp) {
      if (c === "(") ctx.paren++;
      else if (c === ")") {
        if (ctx.paren === 0) stack.pop();
        else ctx.paren--;
      }
    }
    i++;
  }
  return finish(text, found, keepSlash);
}

const REGEX_PRECEDERS = /[(,=:[!&|?{};+\-*%<>~^]$/;
const REGEX_KEYWORDS = /(^|[^\w$])(return|typeof|case|do|else|in|of|instanceof|new|delete|void|throw|yield|await)$/;

function regexAllowed(text, i) {
  let j = i - 1;
  while (j >= 0 && /\s/.test(text[j])) j--;
  if (j < 0) return true;
  const before = text.slice(Math.max(0, j - 12), j + 1);
  return REGEX_PRECEDERS.test(before) || REGEX_KEYWORDS.test(before);
}

function skipQuoted(text, i, quote) {
  i++;
  while (i < text.length && text[i] !== quote && text[i] !== "\n") {
    if (text[i] === "\\") i++;
    i++;
  }
  return i + 1;
}

export function jsComments(text) {
  const n = text.length;
  const found = [];
  const templateDepth = [];
  let braces = 0;
  let i = 0;
  while (i < n) {
    const c = text[i];
    if (c === "`") {
      i = skipTemplate(text, i, templateDepth);
      continue;
    }
    if (templateDepth.length && c === "}" && braces === templateDepth[templateDepth.length - 1]) {
      templateDepth.pop();
      i = skipTemplate(text, i, templateDepth, true);
      continue;
    }
    if (c === "{") braces++;
    else if (c === "}") braces--;
    if (c === '"' || c === "'") {
      i = skipQuoted(text, i, c);
      continue;
    }
    if (c === "/" && text[i + 1] === "/") {
      const end = lineComment(text, i);
      found.push({ pos: i, end });
      i = end;
      continue;
    }
    if (c === "/" && text[i + 1] === "*") {
      const end = blockComment(text, i, false);
      found.push({ pos: i, end });
      i = end;
      continue;
    }
    if (c === "/" && regexAllowed(text, i)) {
      i = skipRegex(text, i);
      continue;
    }
    i++;
  }
  return finish(text, found, keepSlash);

  function skipTemplate(source, start, depth, resumed = false) {
    let j = start + 1;
    while (j < n) {
      if (source[j] === "\\") {
        j += 2;
        continue;
      }
      if (source[j] === "`") return j + 1;
      if (source[j] === "$" && source[j + 1] === "{") {
        depth.push(braces);
        return j + 2;
      }
      j++;
    }
    return resumed ? j : n;
  }

  function skipRegex(source, start) {
    let j = start + 1;
    let inClass = false;
    while (j < n && source[j] !== "\n") {
      if (source[j] === "\\") j += 2;
      else if (inClass) {
        if (source[j] === "]") inClass = false;
        j++;
      } else if (source[j] === "[") {
        inClass = true;
        j++;
      } else if (source[j] === "/") return j + 1;
      else j++;
    }
    return j;
  }
}

export function rustComments(text) {
  const n = text.length;
  const found = [];
  let i = 0;
  while (i < n) {
    const c = text[i];
    if (c === "r" && /^r#*"/.test(text.slice(i, i + 8)) && !/\w/.test(text[i - 1] || "")) {
      let j = i + 1;
      let hashes = 0;
      while (text[j] === "#") {
        hashes++;
        j++;
      }
      const closer = '"' + "#".repeat(hashes);
      const end = text.indexOf(closer, j + 1);
      i = end === -1 ? n : end + closer.length;
      continue;
    }
    if (c === '"') {
      i++;
      while (i < n && text[i] !== '"') {
        if (text[i] === "\\") i++;
        i++;
      }
      i++;
      continue;
    }
    if (c === "'") {
      if (text[i + 1] === "\\") {
        const end = text.indexOf("'", i + 2);
        i = end === -1 ? n : end + 1;
      } else if (text[i + 2] === "'") i += 3;
      else i++;
      continue;
    }
    if (c === "/" && text[i + 1] === "/") {
      const end = lineComment(text, i);
      found.push({ pos: i, end });
      i = end;
      continue;
    }
    if (c === "/" && text[i + 1] === "*") {
      const end = blockComment(text, i, true);
      found.push({ pos: i, end });
      i = end;
      continue;
    }
    i++;
  }
  return finish(text, found, keepSlash);
}

export function cssComments(text) {
  const n = text.length;
  const found = [];
  let i = 0;
  while (i < n) {
    const c = text[i];
    if (c === '"' || c === "'") {
      i = skipQuoted(text, i, c);
      continue;
    }
    if (c === "/" && text[i + 1] === "*") {
      const end = blockComment(text, i, false);
      found.push({ pos: i, end });
      i = end;
      continue;
    }
    i++;
  }
  return finish(text, found, keepSlash);
}

export function jsonComments(text) {
  const n = text.length;
  const found = [];
  let i = 0;
  while (i < n) {
    const c = text[i];
    if (c === '"') {
      i = skipQuoted(text, i, c);
      continue;
    }
    if (c === "/" && (text[i + 1] === "/" || text[i + 1] === "*")) {
      const end = text[i + 1] === "/" ? lineComment(text, i) : blockComment(text, i, false);
      found.push({ pos: i, end });
      i = end;
      continue;
    }
    i++;
  }
  return finish(text, found, () => false);
}

export function htmlComments(text) {
  const n = text.length;
  const found = [];
  let kept = 0;
  const embedded = /<(script|style)\b[^>]*>/gi;
  const regions = [];
  for (const match of text.matchAll(embedded)) {
    const bodyStart = match.index + match[0].length;
    const close = text.toLowerCase().indexOf(`</${match[1].toLowerCase()}`, bodyStart);
    const bodyEnd = close === -1 ? n : close;
    const scanner = match[1].toLowerCase() === "script" ? jsComments : cssComments;
    const result = scanner(text.slice(bodyStart, bodyEnd));
    kept += result.kept;
    for (const range of result.findings)
      found.push({ pos: range.pos + bodyStart, end: range.end + bodyStart });
    regions.push([bodyStart, bodyEnd]);
  }
  let i = 0;
  while (i < n) {
    const region = regions.find(([start, end]) => i >= start && i < end);
    if (region) {
      i = region[1];
      continue;
    }
    if (text.startsWith("<!--", i)) {
      const close = text.indexOf("-->", i + 4);
      const end = close === -1 ? n : close + 3;
      found.push({ pos: i, end });
      i = end;
      continue;
    }
    i++;
  }
  found.sort((a, b) => a.pos - b.pos);
  return { findings: found, kept };
}

export function yamlComments(text) {
  const found = [];
  let kept = 0;
  let pos = 0;
  let blockIndent = null;
  let quote = null;
  for (const line of text.split("\n")) {
    const lineStart = pos;
    pos += line.length + 1;
    const firstNonSpace = line.search(/\S/);
    const blank = firstNonSpace === -1;
    const indent = blank ? 0 : firstNonSpace;
    if (quote === null && blockIndent !== null) {
      if (blank || indent > blockIndent) continue;
      blockIndent = null;
    }
    if (quote === null && blank) continue;
    let commentAt = -1;
    let previousSpace = true;
    for (let k = 0; k < line.length; k++) {
      const c = line[k];
      if (quote === '"') {
        if (c === "\\") k++;
        else if (c === '"') quote = null;
        previousSpace = false;
        continue;
      }
      if (quote === "'") {
        if (c === "'" && line[k + 1] === "'") k++;
        else if (c === "'") quote = null;
        previousSpace = false;
        continue;
      }
      if ((c === '"' || c === "'") && (previousSpace || /[:\-[{,]/.test(line[k - 1] || ""))) {
        quote = c;
        previousSpace = false;
        continue;
      }
      if (c === "#" && previousSpace) {
        commentAt = k;
        break;
      }
      previousSpace = c === " " || c === "\t";
    }
    if (quote === null) {
      const code = (commentAt === -1 ? line : line.slice(0, commentAt)).trimEnd();
      if (/(?:^|\s)[|>](?:[1-9][+-]?|[+-][1-9]?)?$/.test(code)) blockIndent = indent;
    }
    if (commentAt === -1) continue;
    if (keepHash(text, lineStart + commentAt, line)) kept++;
    else found.push({ pos: lineStart + commentAt, end: lineStart + line.length });
  }
  return { findings: found, kept };
}

const HEREDOC = /<<-?\s*(["']?)([A-Za-z_][\w]*)\1/;

export function hashComments(text) {
  const n = text.length;
  const found = [];
  let kept = 0;
  let i = 0;
  let lineStart = 0;
  let heredoc = null;
  while (i < n) {
    const c = text[i];
    if (c === "\n") {
      lineStart = i + 1;
      i++;
      if (heredoc) {
        let lineEnd = text.indexOf("\n", i);
        if (lineEnd === -1) lineEnd = n;
        if (text.slice(i, lineEnd).trim() === heredoc) heredoc = null;
        i = lineEnd;
      }
      continue;
    }
    if (text.startsWith('"""', i) || text.startsWith("'''", i)) {
      const closer = text.slice(i, i + 3);
      const end = text.indexOf(closer, i + 3);
      i = end === -1 ? n : end + 3;
      continue;
    }
    if (c === '"') {
      i++;
      while (i < n && text[i] !== '"') {
        if (text[i] === "\\") i++;
        i++;
      }
      i++;
      continue;
    }
    if (c === "'") {
      const end = text.indexOf("'", i + 1);
      i = end === -1 ? n : end + 1;
      continue;
    }
    if (c === "<" && text[i + 1] === "<") {
      const match = HEREDOC.exec(text.slice(i, i + 40));
      if (match && match.index === 0) {
        heredoc = match[2];
        i += match[0].length;
        continue;
      }
    }
    if (c === "#" && (i === lineStart || /\s/.test(text[i - 1]))) {
      let end = text.indexOf("\n", i);
      if (end === -1) end = n;
      const line = text.slice(lineStart, end);
      if (keepHash(text, i, line)) kept++;
      else found.push({ pos: i, end });
      i = end;
      continue;
    }
    i++;
  }
  return { findings: found, kept };
}

const BY_EXTENSION = {
  swift: swiftComments,
  js: jsComments,
  mjs: jsComments,
  cjs: jsComments,
  ts: jsComments,
  mts: jsComments,
  cts: jsComments,
  tsx: jsComments,
  jsx: jsComments,
  rs: rustComments,
  css: cssComments,
  scss: cssComments,
  json: jsonComments,
  jsonc: jsonComments,
  yml: yamlComments,
  yaml: yamlComments,
  html: htmlComments,
  htm: htmlComments,
  xhtml: htmlComments,
  xml: htmlComments,
  svg: htmlComments,
  plist: htmlComments,
  sh: hashComments,
  bash: hashComments,
  zsh: hashComments,
  toml: hashComments,
  ini: hashComments,
  cfg: hashComments,
  mk: hashComments,
};

const BY_BASENAME = {
  Makefile: hashComments,
  ".editorconfig": hashComments,
  ".gitignore": hashComments,
  ".gitattributes": hashComments,
  ".gitleaksignore": hashComments,
  ".npmrc": hashComments,
  ".swift-format": jsonComments,
};

export function scannerFor(file, text = "") {
  const base = file.slice(file.lastIndexOf("/") + 1);
  if (BY_BASENAME[base]) return BY_BASENAME[base];
  const extension = base.includes(".") ? base.slice(base.lastIndexOf(".") + 1).toLowerCase() : "";
  if (BY_EXTENSION[extension]) return BY_EXTENSION[extension];
  if (/^#!.*\b(ba|z)?sh\b/.test(text.split("\n")[0] || "")) return hashComments;
  return null;
}

export function scan(file, text) {
  const scanner = scannerFor(file, text);
  if (!scanner) return { findings: [], kept: 0 };
  return scanner(text);
}

function snippet(text, range) {
  const first = text.slice(range.pos, range.end).split("\n")[0].trim();
  return first.length > 80 ? `${first.slice(0, 77)}...` : first;
}

export function checkFiles(files) {
  const findings = [];
  for (const file of files) {
    const text = readText(file);
    if (text === null) continue;
    for (const range of scan(file, text).findings)
      findings.push(`${file}:${lineOf(text, range.pos)}: ${snippet(text, range)}`);
  }
  return findings;
}

if (import.meta.main) report("check-comments", checkFiles(trackedFiles()));
