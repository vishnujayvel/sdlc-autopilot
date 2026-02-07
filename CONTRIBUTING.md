# Contributing to SDLC Autopilot

## Pre-Publish Review Checklist

Before publishing a new version to npm, verify the following:

### Data Leakage Scan

- [ ] Grep all shipped files for personal project names, usernames, or private references
- [ ] Grep for email addresses, home directory paths, API keys
- [ ] Verify `templates/skills/sdlc-autopilot/SKILL.md` line count is under 2,000 lines
- [ ] Verify no hardcoded user-specific paths in any shipped file

### Build Verification

- [ ] `npm run build` completes without errors
- [ ] `dist/cli.js` has `#!/usr/bin/env node` shebang on first line
- [ ] `node dist/cli.js --version` prints correct version
- [ ] `node dist/cli.js --help` prints usage information
- [ ] `node dist/cli.js --dry-run` shows correct template and target paths
- [ ] `node dist/cli.js --project --dry-run` shows project-level install path

### Package Verification

- [ ] `npm pack --dry-run` includes only intended files
- [ ] No `.env`, credentials, or `.claude/specs/` files in tarball
- [ ] `package.json` version matches `CHANGELOG.md` version

### Post-Publish Verification

- [ ] `npx sdlc-autopilot@latest --version` prints new version
- [ ] `npx sdlc-autopilot@latest --dry-run` works from a clean directory

## Reporting Issues

Please report bugs and feature requests via [GitHub Issues](https://github.com/vishnujayvel/sdlc-autopilot/issues).

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
