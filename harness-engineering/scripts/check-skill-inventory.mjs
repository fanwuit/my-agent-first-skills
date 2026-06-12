#!/usr/bin/env node
import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const defaultRepoRoot = path.resolve(__dirname, "..", "..");
const ASSET_DIRS = new Set(["assets", "references", "scripts", "templates", "tests"]);
const TOP_LEVEL_ASSETS = new Set(["reference.md", "examples.md"]);

const { repoRoot } = parseArgs(process.argv.slice(2));
const readmePath = path.join(repoRoot, "README.md");
const errors = [];

if (!existsSync(readmePath)) {
  errors.push("README.md not found.");
} else {
  const readme = readFileSync(readmePath, "utf8");
  checkSkillTable(repoRoot, readme, errors);
  checkAssetInventory(repoRoot, readme, errors);
}

if (errors.length) {
  console.error("Skill inventory check failed:");
  for (const error of errors) {
    console.error(`- ${error}`);
  }
  process.exit(1);
}

console.log("Skill inventory check passed.");

function checkSkillTable(repoRootValue, readme, allErrors) {
  const enabledSkills = discoverEnabledSkills(repoRootValue);
  const tableSkills = extractReadmeSkillNames(readme);
  const tableSet = new Set(tableSkills);

  const countMatch = readme.match(/启用的非 system skills：\s*(\d+)\s*个/);
  if (!countMatch) {
    allErrors.push("README missing enabled non-system skill count.");
  } else if (Number(countMatch[1]) !== enabledSkills.length) {
    allErrors.push(`README enabled skill count is ${countMatch[1]}, expected ${enabledSkills.length}.`);
  }

  for (const skill of enabledSkills) {
    if (!tableSet.has(skill)) {
      allErrors.push(`README skill table missing enabled skill: ${skill}.`);
    }
  }

  for (const skill of tableSkills) {
    if (!enabledSkills.includes(skill)) {
      allErrors.push(`README skill table lists missing or disabled skill: ${skill}.`);
    }
  }
}

function checkAssetInventory(repoRootValue, readme, allErrors) {
  const assets = discoverAssets(repoRootValue);
  for (const asset of assets) {
    const normalized = normalize(asset);
    const basename = path.basename(asset);
    const wildcard = basename.replace(/\.(?:ps1|sh|mjs|py|md)$/i, ".*");
    if (!readme.includes(normalized) && !readme.includes(basename) && !readme.includes(wildcard)) {
      allErrors.push(`README important asset inventory missing: ${normalized}.`);
    }
  }
}

function discoverEnabledSkills(repoRootValue) {
  return readdirSync(repoRootValue, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .filter((name) => !name.startsWith("."))
    .filter((name) => existsSync(path.join(repoRootValue, name, "SKILL.md")))
    .filter((name) => !name.includes("disabled") && !name.includes("deleted"))
    .sort();
}

function extractReadmeSkillNames(readme) {
  const names = [];
  for (const line of readme.split(/\r?\n/)) {
    const columns = line.split("|").map((column) => column.trim());
    if (columns.length < 6 || columns[4] !== "是") {
      continue;
    }
    const skillCell = columns[2];
    const match = skillCell.match(/^`([^`]+)`$/);
    if (match) {
      names.push(match[1]);
    }
  }
  return names.sort();
}

function discoverAssets(repoRootValue) {
  const assets = [];
  for (const skill of discoverEnabledSkills(repoRootValue)) {
    const skillDir = path.join(repoRootValue, skill);
    for (const entry of readdirSync(skillDir, { withFileTypes: true })) {
      if (entry.isDirectory() && ASSET_DIRS.has(entry.name)) {
        collectFiles(path.join(skillDir, entry.name), repoRootValue, assets);
      } else if (entry.isFile() && TOP_LEVEL_ASSETS.has(entry.name)) {
        assets.push(path.relative(repoRootValue, path.join(skillDir, entry.name)));
      }
    }
  }
  return assets.sort();
}

function collectFiles(dir, repoRootValue, out) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (entry.name !== "fixtures") {
        collectFiles(fullPath, repoRootValue, out);
      }
    } else if (entry.isFile() && !entry.name.endsWith(".tmp")) {
      out.push(path.relative(repoRootValue, fullPath));
    }
  }
}

function parseArgs(args) {
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
      usage();
      process.exit(2);
    }
  }
  return { repoRoot: parsedRepoRoot };
}

function normalize(value) {
  return value.replaceAll(path.sep, "/");
}

function usage() {
  console.error("Usage: node harness-engineering/scripts/check-skill-inventory.mjs [--repo <path>]");
}
