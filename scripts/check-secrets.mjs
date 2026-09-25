import { lineOf, readText, report, trackedFiles } from "./tracked.mjs";

const SELF = ["scripts/check-secrets.mjs", "scripts/check-secrets.test.js"];

export const RULES = [
  { name: "private key block", re: /-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----/g },
  { name: "github token", re: /\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\b/g },
  { name: "github fine-grained token", re: /\bgithub_pat_[A-Za-z0-9_]{70,}\b/g },
  { name: "aws access key", re: /\b(AKIA|ASIA)[A-Z0-9]{16}\b/g },
  { name: "slack token", re: /\bxox[abpr]-[A-Za-z0-9-]{10,}\b/g },
  { name: "openai style key", re: /\bsk-(proj-|ant-)?[A-Za-z0-9_-]{32,}\b/g },
  { name: "google api key", re: /\bAIza[0-9A-Za-z_-]{35}\b/g },
  { name: "stripe key", re: /\b(sk|rk)_(live|test)_[A-Za-z0-9]{24,}\b/g },
  { name: "npm token", re: /\bnpm_[A-Za-z0-9]{36}\b/g },
  { name: "sparkle or ssh private seed", re: /(?:seed|private[_-]?key)["']?\s*[:=]\s*["'][A-Za-z0-9+/]{40,}={0,2}["']/gi },
  {
    name: "high-entropy assignment",
    re: /(?:secret|token|password|passwd|api[_-]?key|auth)["']?\s*[:=]\s*["']([A-Za-z0-9+/=_-]{32,})["']/gi,
    entropy: 4.2,
  },
];

export function entropy(value) {
  const counts = new Map();
  for (const char of value) counts.set(char, (counts.get(char) || 0) + 1);
  let bits = 0;
  for (const count of counts.values()) {
    const p = count / value.length;
    bits -= p * Math.log2(p);
  }
  return bits;
}

export function scanText(text, file) {
  const findings = [];
  for (const rule of RULES) {
    for (const match of text.matchAll(rule.re)) {
      if (rule.entropy && entropy(match[1]) < rule.entropy) continue;
      if (/X{4,}|EXAMPLE|placeholder|__VERSION__/i.test(match[0])) continue;
      findings.push(`${file}:${lineOf(text, match.index)}: ${rule.name}`);
    }
  }
  return findings;
}

export function checkFiles(files) {
  const findings = [];
  for (const file of files) {
    if (SELF.includes(file)) continue;
    const text = readText(file);
    if (text !== null) findings.push(...scanText(text, file));
  }
  return findings;
}

if (import.meta.main) report("check-secrets", checkFiles(trackedFiles()));
