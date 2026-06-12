#!/usr/bin/env node
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const defaultRepoRoot = path.resolve(__dirname, "..", "..");
const defaultFixture = path.join("governed-implementation-entry", "tests", "fixtures", "valid-entry-record.md");

const entryTypes = [
  {
    heading: "Implementation Entry Record",
    requiredFields: [
      "Current layer",
      "Target",
      "Scope",
      "Contract evidence",
      "Readiness gate",
      "Packetization",
      "Verification command",
      "Review / Next state file",
      "Stop conditions",
    ],
    validate: validateImplementationEntry,
  },
  {
    heading: "Trivial Safe Change Entry",
    requiredFields: [
      "Target",
      "Scope",
      "Why trivial",
      "Existing contract or reason not needed",
      "Verification",
      "Stop conditions",
    ],
    validate: () => [],
  },
];

const { targets, repoRoot } = parseArgs(process.argv.slice(2));
const files = targets.length ? targets.map((target) => resolveTarget(target, repoRoot)) : discoverEntryRecords(repoRoot);
const errors = [];
let checked = 0;

for (const file of files) {
  const result = checkFile(file, repoRoot);
  checked += result.checked ? 1 : 0;
  errors.push(...result.errors);
}

if (errors.length) {
  console.error("Entry record check failed:");
  for (const error of errors) {
    console.error(`- ${error}`);
  }
  process.exit(1);
}

if (checked === 0) {
  console.log("Entry record check passed: no entry records found.");
} else {
  console.log(`Entry record check passed: ${checked} file(s).`);
}

function checkFile(file, repoRootValue) {
  const label = normalize(path.relative(repoRootValue, file) || file);
  const localErrors = [];

  if (!existsSync(file)) {
    return { checked: false, errors: [`${label} does not exist.`] };
  }

  if (!statSync(file).isFile()) {
    return { checked: false, errors: [`${label} is not a file.`] };
  }

  const text = readFileSync(file, "utf8");
  const matchingType = entryTypes.find((entryType) => hasHeading(text, entryType.heading));

  if (!matchingType) {
    localErrors.push(`${label}: Missing 'Implementation Entry Record:' or 'Trivial Safe Change Entry:' heading.`);
  } else {
    for (const field of matchingType.requiredFields) {
      const value = fieldValue(text, field);

      if (value === null) {
        localErrors.push(`${label}: Missing field: ${field}`);
        continue;
      }

      if (isInvalidValue(value)) {
        localErrors.push(`${label}: Empty or placeholder value: ${field}`);
      }
    }

    localErrors.push(...matchingType.validate(text).map((error) => `${label}: ${error}`));
  }

  return { checked: true, errors: localErrors };
}

function discoverEntryRecords(repoRootValue) {
  const records = [path.join(repoRootValue, defaultFixture)];
  const remediationRoot = path.join(repoRootValue, "docs", "remediation");

  if (existsSync(remediationRoot)) {
    for (const entry of readdirSync(remediationRoot, { withFileTypes: true })) {
      if (entry.isFile() && /整改记录\.md$/u.test(entry.name)) {
        records.push(path.join(remediationRoot, entry.name));
      }
    }
  }

  return [...new Set(records)].sort();
}

function resolveTarget(target, repoRootValue) {
  const direct = path.resolve(target);
  if (existsSync(direct)) {
    return direct;
  }

  const repoRelative = path.resolve(repoRootValue, target);
  if (existsSync(repoRelative)) {
    return repoRelative;
  }

  return repoRelative;
}

function parseArgs(args) {
  const parsedTargets = [];
  let parsedRepoRoot = defaultRepoRoot;

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === "--repo") {
      parsedRepoRoot = path.resolve(args[index + 1] ?? "");
      index += 1;
    } else if (arg === "--help" || arg === "-h") {
      usage();
      process.exit(0);
    } else {
      parsedTargets.push(arg);
    }
  }

  return {
    targets: parsedTargets,
    repoRoot: parsedRepoRoot,
  };
}

function hasHeading(text, heading) {
  return new RegExp(`${escapeRegExp(heading)}:`, "i").test(text);
}

function fieldValue(text, field) {
  const pattern = new RegExp(`^-\\s*${escapeRegExp(field)}\\s*:\\s*(.*)$`, "im");
  const match = text.match(pattern);
  return match ? match[1] : null;
}

function isInvalidValue(value) {
  return /^(?:\s*|tbd|todo|missing|n\/a|\?)$/i.test(value);
}

function validateImplementationEntry(text) {
  const validationErrors = [];
  const readiness = fieldValue(text, "Readiness gate") ?? "";
  if (readiness && !/\b(?:pass|fail)\b/i.test(readiness)) {
    validationErrors.push("Readiness gate must include pass or fail.");
  }

  const packetization = fieldValue(text, "Packetization") ?? "";
  if (packetization && !/\b(?:ready|not-needed|missing)\b/i.test(packetization)) {
    validationErrors.push("Packetization must include ready, not-needed, or missing.");
  }

  return validationErrors;
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function normalize(value) {
  return value.replaceAll(path.sep, "/");
}

function usage() {
  console.error("Usage: node governed-implementation-entry/scripts/check-entry-record.mjs [markdown-file ...] [--repo <path>]");
}
