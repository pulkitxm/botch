import { commitMessages, lineOf, readText, report, trackedFiles } from "./tracked.mjs";

const SELF = ["scripts/check-attribution.mjs", "scripts/check-attribution.test.js"];

export const PATTERNS = [
  { name: "co-authored trailer", re: /co-authored-by:\s*(claude|codex|copilot|chatgpt|openai|anthropic)\b/gi },
  { name: "generated-with footer", re: /generated with \[claude code\]|🤖 generated with\b/gi },
  { name: "claude", re: /\bclaude(?:[ _-]?code)?\b/gi },
  { name: "anthropic", re: /\banthropic\b/gi },
  { name: "codex", re: /\bcodex\b/gi },
  { name: "copilot", re: /\bcopilot\b/gi },
  { name: "chatgpt", re: /\bchatgpt\b/gi },
  { name: "openai", re: /\bopenai\b/gi },
];

export const BRANCH_PREFIXES = /^(claude[/-]|ai[/-]|copilot\/|llm\/|anthropic\/)/i;

export function findAttribution(text, label) {
  const findings = [];
  for (const { name, re } of PATTERNS) {
    for (const match of text.matchAll(re))
      findings.push({ line: lineOf(text, match.index), text: `${label}:${lineOf(text, match.index)}: ${name}` });
  }
  return findings.sort((a, b) => a.line - b.line).map((finding) => finding.text);
}

export function checkFiles(files) {
  const findings = [];
  for (const file of files) {
    if (SELF.includes(file)) continue;
    const text = readText(file);
    if (text !== null) findings.push(...findAttribution(text, file));
  }
  return findings;
}

export function checkCommits(commits) {
  return commits.flatMap(({ sha, message }) => findAttribution(message, `commit ${sha}`));
}

export function checkBranch(name) {
  return name && BRANCH_PREFIXES.test(name) ? [`branch ${name}: ai-attributed branch name`] : [];
}

if (import.meta.main) {
  const args = process.argv.slice(2);
  const findings = [];
  if (args.includes("--commits")) findings.push(...checkCommits(commitMessages(args[args.indexOf("--commits") + 1])));
  if (args.includes("--branch")) findings.push(...checkBranch(args[args.indexOf("--branch") + 1]));
  if (!args.includes("--commits") && !args.includes("--branch")) findings.push(...checkFiles(trackedFiles()));
  report("check-attribution", findings);
}
