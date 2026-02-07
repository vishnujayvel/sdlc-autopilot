#!/usr/bin/env node

/**
 * sdlc-autopilot CLI entry point.
 *
 * Installs the SDLC Autopilot skill (SKILL.md) into the Claude Code
 * skills directory (global or project-level).
 *
 * Usage: npx sdlc-autopilot [options]
 */

import { existsSync, mkdirSync, copyFileSync, readFileSync } from "node:fs";
import { join, dirname, resolve } from "node:path";
import { homedir } from "node:os";
import { createInterface } from "node:readline";
import { fileURLToPath } from "node:url";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface CLIOptions {
  project: boolean;   // Install to .claude/skills/ instead of ~/.claude/skills/
  yes: boolean;       // Skip confirmation prompts
  dryRun: boolean;    // Show what would be installed
  version: boolean;   // Print version and exit
  help: boolean;      // Print help and exit
}

interface InstallResult {
  success: boolean;
  targetPath: string;
  warnings: string[]; // e.g., "cc-sdd not found"
}

// ---------------------------------------------------------------------------
// Version helper
// ---------------------------------------------------------------------------

function getVersion(): string {
  // Resolve package.json relative to the compiled JS file (dist/cli.js).
  // In the built output, package.json sits one level up from dist/.
  const thisFile = fileURLToPath(import.meta.url);
  const packageJsonPath = join(dirname(thisFile), "..", "package.json");
  try {
    const raw = readFileSync(packageJsonPath, "utf-8");
    const pkg = JSON.parse(raw) as { version?: string };
    return pkg.version ?? "0.0.0";
  } catch {
    return "0.0.0";
  }
}

// ---------------------------------------------------------------------------
// Argument parsing
// ---------------------------------------------------------------------------

function parseArgs(argv: string[]): CLIOptions {
  const opts: CLIOptions = {
    project: false,
    yes: false,
    dryRun: false,
    version: false,
    help: false,
  };

  // argv typically starts with [node, script, ...userArgs].
  // When invoked via `npx`, the first two entries are the runtime and the
  // script path. We only care about the rest.
  const args = argv.slice(2);

  for (const arg of args) {
    switch (arg) {
      case "--project":
        opts.project = true;
        break;
      case "--yes":
      case "-y":
        opts.yes = true;
        break;
      case "--dry-run":
        opts.dryRun = true;
        break;
      case "--version":
      case "-v":
        opts.version = true;
        break;
      case "--help":
      case "-h":
        opts.help = true;
        break;
      default:
        console.error(`Unknown flag: ${arg}`);
        console.error('Run "npx sdlc-autopilot --help" for usage information.');
        process.exit(1);
    }
  }

  return opts;
}

// ---------------------------------------------------------------------------
// Help output
// ---------------------------------------------------------------------------

function printHelp(): void {
  const version = getVersion();
  const text = `
sdlc-autopilot v${version}
Install the SDLC Autopilot skill for Claude Code.

USAGE
  npx sdlc-autopilot [options]

OPTIONS
  --project      Install into the current project (.claude/skills/sdlc-autopilot/)
                 instead of the global location (~/.claude/skills/sdlc-autopilot/)
  --yes, -y      Skip confirmation prompts (overwrite without asking)
  --dry-run      Show what would be installed without writing any files
  --version, -v  Print version and exit
  --help, -h     Show this help message and exit

EXAMPLES
  npx sdlc-autopilot              Install globally (recommended)
  npx sdlc-autopilot --project    Install into current project only
  npx sdlc-autopilot --dry-run    Preview installation without writing
  npx sdlc-autopilot -y           Install globally, overwrite if exists
`.trimStart();

  console.log(text);
}

// ---------------------------------------------------------------------------
// Target directory resolution
// ---------------------------------------------------------------------------

function resolveTargetDir(options: CLIOptions): string {
  if (options.project) {
    return resolve(process.cwd(), ".claude", "skills", "sdlc-autopilot");
  }
  return join(homedir(), ".claude", "skills", "sdlc-autopilot");
}

// ---------------------------------------------------------------------------
// Template path resolution
// ---------------------------------------------------------------------------

function resolveTemplatePath(): string {
  // In the built output (dist/cli.js), templates/ is at ../templates/ relative
  // to the dist directory.
  const thisFile = fileURLToPath(import.meta.url);
  return join(dirname(thisFile), "..", "templates", "skills", "sdlc-autopilot", "SKILL.md");
}

// ---------------------------------------------------------------------------
// Existing install detection
// ---------------------------------------------------------------------------

function checkExistingInstall(targetDir: string): boolean {
  const skillPath = join(targetDir, "SKILL.md");
  return existsSync(skillPath);
}

// ---------------------------------------------------------------------------
// Confirmation prompt (stdin)
// ---------------------------------------------------------------------------

async function confirmOverwrite(targetPath: string): Promise<boolean> {
  const rl = createInterface({ input: process.stdin, output: process.stdout });

  return new Promise<boolean>((resolvePromise) => {
    rl.question(
      `\nSKILL.md already exists at ${targetPath}\nOverwrite? [y/N] `,
      (answer) => {
        rl.close();
        const normalised = answer.trim().toLowerCase();
        resolvePromise(normalised === "y" || normalised === "yes");
      },
    );
  });
}

// ---------------------------------------------------------------------------
// Skill installation
// ---------------------------------------------------------------------------

function installSkill(templatePath: string, targetDir: string): InstallResult {
  const targetPath = join(targetDir, "SKILL.md");
  const warnings: string[] = [];

  try {
    // Verify that the template source exists
    if (!existsSync(templatePath)) {
      console.error(`Error: Template not found at ${templatePath}`);
      console.error("This is likely a packaging issue. Please reinstall the package.");
      return { success: false, targetPath, warnings };
    }

    // Create target directory recursively
    mkdirSync(targetDir, { recursive: true });

    // Copy the file
    copyFileSync(templatePath, targetPath);

    return { success: true, targetPath, warnings };
  } catch (err: unknown) {
    const error = err as NodeJS.ErrnoException;

    if (error.code === "EACCES") {
      console.error(`\nPermission denied: ${targetDir}`);
      console.error("Try one of the following:");
      console.error(`  sudo npx sdlc-autopilot`);
      console.error(`  Check ownership: ls -la ${dirname(targetDir)}`);
      console.error(`  Or install to the project instead: npx sdlc-autopilot --project`);
    } else {
      console.error(`\nFailed to install SKILL.md: ${error.message ?? String(err)}`);
    }

    return { success: false, targetPath, warnings };
  }
}

// ---------------------------------------------------------------------------
// Prerequisite detection
// ---------------------------------------------------------------------------

function checkPrerequisites(cwd: string): string[] {
  const warnings: string[] = [];

  const ccSddPath = join(cwd, ".claude", "commands", "kiro", "spec-init.md");
  if (!existsSync(ccSddPath)) {
    warnings.push(
      [
        "cc-sdd not detected in this project.",
        "SDLC Autopilot works best with cc-sdd (Kiro-style specs for Claude Code).",
        "Install it with:  npx cc-sdd@latest --claude",
        "More info: https://github.com/gotalab/cc-sdd",
      ].join("\n"),
    );
  }

  return warnings;
}

// ---------------------------------------------------------------------------
// Result output
// ---------------------------------------------------------------------------

function printResult(result: InstallResult): void {
  if (result.success) {
    console.log(`\nInstalled SKILL.md to ${result.targetPath}`);
  }

  if (result.warnings.length > 0) {
    console.log("");
    for (const warning of result.warnings) {
      console.warn(`Warning: ${warning}`);
    }
  }

  if (result.success) {
    console.log('\nYou\'re all set! Say "SDLC" in Claude Code to start.');
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

async function main(argv: string[]): Promise<void> {
  const options = parseArgs(argv);

  // --help
  if (options.help) {
    printHelp();
    process.exit(0);
  }

  // --version
  if (options.version) {
    console.log(`sdlc-autopilot v${getVersion()}`);
    process.exit(0);
  }

  const targetDir = resolveTargetDir(options);
  const templatePath = resolveTemplatePath();
  const targetPath = join(targetDir, "SKILL.md");

  // --dry-run
  if (options.dryRun) {
    console.log("Dry run: no files will be written.\n");
    console.log(`Template source : ${templatePath}`);
    console.log(`Target directory: ${targetDir}`);
    console.log(`Target file     : ${targetPath}`);

    const alreadyExists = checkExistingInstall(targetDir);
    if (alreadyExists) {
      console.log("\nNote: SKILL.md already exists at the target path and would be overwritten.");
    } else {
      console.log("\nSKILL.md does not yet exist at the target path. It would be created.");
    }

    // Also show prerequisite status
    const prereqWarnings = checkPrerequisites(process.cwd());
    if (prereqWarnings.length > 0) {
      console.log("");
      for (const w of prereqWarnings) {
        console.warn(`Warning: ${w}`);
      }
    }

    process.exit(0);
  }

  // Check for existing install and prompt if needed
  const alreadyExists = checkExistingInstall(targetDir);
  if (alreadyExists && !options.yes) {
    const confirmed = await confirmOverwrite(targetPath);
    if (!confirmed) {
      console.log("Installation cancelled.");
      process.exit(0);
    }
  }

  // Install
  const result = installSkill(templatePath, targetDir);

  // Check prerequisites (best-effort, cwd only)
  const prereqWarnings = checkPrerequisites(process.cwd());
  result.warnings.push(...prereqWarnings);

  // Print result
  printResult(result);

  process.exit(result.success ? 0 : 1);
}

// Run
main(process.argv).catch((err) => {
  console.error("Unexpected error:", err);
  process.exit(1);
});
