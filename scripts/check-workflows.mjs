import { readFileSync } from "node:fs";
import { report, trackedFiles } from "./tracked.mjs";

const USES = /^(\s*)(?:-\s+)?uses:\s*(\S+)(.*)$/;
const PINNED = /^[^@]+@[0-9a-f]{40}\s+# v?\d[\w.-]*$/;

function blocks(lines, headerRe, indent) {
  const found = [];
  for (let i = 0; i < lines.length; i++) {
    const match = headerRe.exec(lines[i]);
    if (!match || match[1].length !== indent) continue;
    let end = i + 1;
    while (end < lines.length && (!lines[end].trim() || lines[end].search(/\S/) > indent)) end++;
    found.push({ name: match[2], start: i, lines: lines.slice(i + 1, end) });
  }
  return found;
}

export function checkWorkflow(file, text) {
  const findings = [];
  const lines = text.split("\n");
  const jobsAt = lines.findIndex((line) => /^jobs:\s*$/.test(line));
  if (jobsAt === -1) return [`${file}: no jobs section`];
  const jobLines = lines.slice(jobsAt + 1);
  const jobs = blocks(jobLines, /^(\s+)([\w-]+):\s*$/, 2);
  if (!jobs.length) findings.push(`${file}: no jobs found`);
  for (const job of jobs) {
    const where = `${file}:${jobsAt + job.start + 2}`;
    const body = job.lines.join("\n");
    if (!/^\s{4}permissions:/m.test(body)) findings.push(`${where}: job ${job.name} does not set permissions`);
    if (!/^\s{4}timeout-minutes:\s*\d+/m.test(body)) findings.push(`${where}: job ${job.name} has no timeout-minutes`);
    const steps = blocks(job.lines, /^(\s+)- (uses|name|run|id|env|with|if|shell|working-directory):.*$/, 6);
    for (let i = 0; i < steps.length; i++) {
      const stepLines = [job.lines[steps[i].start], ...steps[i].lines];
      const usesLine = stepLines.find((line) => USES.test(line));
      if (!usesLine) continue;
      const action = USES.exec(usesLine)[2] + USES.exec(usesLine)[3];
      const line = jobsAt + job.start + steps[i].start + 3;
      if (!PINNED.test(action.trim())) findings.push(`${file}:${line}: uses ${action.trim()} is not pinned to a 40-char SHA with a version comment`);
      if (/^actions\/checkout@/.test(action) && !/persist-credentials:\s*false/.test(stepLines.join("\n"))) {
        findings.push(`${file}:${line}: checkout without persist-credentials: false`);
      }
    }
  }
  return findings;
}

export function checkFiles(files) {
  return files.flatMap((file) => checkWorkflow(file, readFileSync(file, "utf8")));
}

if (import.meta.main) {
  report("check-workflows", checkFiles(trackedFiles().filter((file) => /^\.github\/workflows\/[^/]+\.ya?ml$/.test(file))));
}
