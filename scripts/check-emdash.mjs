import { commitMessages, lineOf, readText, report, trackedFiles } from "./tracked.mjs";

export const EM_DASH = "—";

export function findEmDashes(text, label) {
  const findings = [];
  let from = 0;
  while (true) {
    const at = text.indexOf(EM_DASH, from);
    if (at === -1) return findings;
    findings.push(`${label}:${lineOf(text, at)}: em-dash`);
    from = at + 1;
  }
}

export function checkFiles(files) {
  const findings = [];
  for (const file of files) {
    const text = readText(file);
    if (text !== null) findings.push(...findEmDashes(text, file));
  }
  return findings;
}

export function checkCommits(commits) {
  return commits.flatMap(({ sha, message }) => findEmDashes(message, `commit ${sha}`));
}

if (import.meta.main) {
  const args = process.argv.slice(2);
  const range = args[args.indexOf("--commits") + 1];
  const findings = args.includes("--commits")
    ? checkCommits(commitMessages(range))
    : checkFiles(trackedFiles());
  report("check-emdash", findings);
}
