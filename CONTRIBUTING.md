# Contributing

Thanks for helping. For anything bigger than a small fix, open an issue first, so the design can be talked through before the code.

## What's where

- `Sources/SkillHealthCore`: the engine. Skills and their install records, usage, comparing with repositories, updates and their undo, findings and choices, the lock that stops the app and the plugin from writing at the same time, and the files the plugin's hook prints.
- `Sources/skill-health`: the plugin's command-line tool, built into the committed `plugin/bin/skill-health`.
- `Sources/SkillHealthApp`: the SwiftUI menu bar app: the menu, the Settings window, and a read-only page for each skill.
- `plugin/`: the Claude Code plugin: skills, agents, hooks (session start, and the write gate), the tool, and the known corrections in `plugin/data/corrections.json`. `.claude-plugin/marketplace.json` makes this repository its own marketplace.

## Build and test

You need macOS 27 and Swift 6.2 or later (Xcode 27). There are no third-party dependencies.

```bash
swift build
swift test
```

`Scripts/package_app.sh` builds the app into `build/SkillHealth.app`.

## The plugin's binary is committed

Claude Code installs a plugin by copying its folder; nothing is built on install. So the plugin's tool, `plugin/bin/skill-health`, is a committed universal binary, and `plugin/bin/BUILT_FROM` names the commit it was built from.

**Don't commit a rebuilt binary in a pull request.** A binary can't be reviewed in a diff, so only the maintainer builds it (see `.github/CODEOWNERS`). If your change touches `Sources/SkillHealthCore`, `Sources/skill-health` or `Package.swift`, the test `theCommittedBinaryIsBuiltFromTheCurrentSource` fails when you run `swift test`; that is expected, and there is no CI yet. Leave "Allow edits from maintainers" on, and the maintainer rebuilds the binary on your branch, in its own commit, before merging with a merge commit (never a squash or a rebase, so the commit `plugin/bin/BUILT_FROM` names stays in history).

**To check the committed binary yourself,** run:

```bash
Scripts/verify_plugin_bin.sh
```

It first checks that the commit `plugin/bin/BUILT_FROM` names is in your history and has the same `Sources/SkillHealthCore`, `Sources/skill-health`, `Package.swift` and build scripts as your working tree. Then it builds that commit in a scratch worktree, with its own build script, and compares the code. A plain `cmp` or `shasum` of the two files differs whenever the build path's length does, because each binary carries a UUID and an ad hoc signature that covers it; the script removes both from copies before comparing.

What a pass proves, and what it doesn't:

- The committed binary is the same code as a build of the source in your checkout. It doesn't show that source is safe: read it.
- It builds with your toolchain, and a different Xcode can change the code itself. `plugin/bin/BUILT_WITH` records the Xcode, Swift and SDK the maintainer used, and the script prints it beside yours; if they differ, a failure is not evidence either way.
- It runs the commit's build script and `Package.swift` with your privileges, as `swift build` does, and the script is part of the checkout it checks. Use a clone you would build anyway.
- Claude Code runs the copy it installed, not the one in your clone. Compare `~/.claude/plugins/cache/skill-health/skill-health/<version>/bin/skill-health` with the clone's by `shasum -a 256` (`claude plugin list --json` shows the install path).

It needs a full clone (the test and the script read git history, so a shallow clone or a downloaded ZIP fails), takes a minute or two, and changes nothing in your working tree.

`plugin/data/corrections.json`, the known corrections that ship with the plugin, is the maintainer's: entries are added with `skill-health export-shared` from checks of unedited public skills, and reworded by hand when a check's wording needs it. Please don't edit it in a pull request; open an issue with the skill and the instruction instead.

## Words are part of the design

Every sentence a person reads is decided in `Sources/SkillHealthCore` (`MenuLayout`, `SettingsText`, `SkillPageText`, `ProblemText`, the tool's messages) and checked word for word by a test. The views only lay them out. If you change what Skill Health says, change the test with it, and keep Skill Health's voice: plain, specific, sentence case, no exclamation marks, and never a claim the data can't back.

## Keep the safety promises

[SECURITY.md](SECURITY.md) lists them. In short: only the plugin's tool writes a skill, always as preview then apply; the app never does; nothing new is sent off the Mac. A change that touches any of these needs a test that tries to break it.

## The design record

[docs/2026-10-04_plugin_driven_redesign.md](docs/2026-10-04_plugin_driven_redesign.md) is the spec: what each piece does and why. When you change behavior, update the spec in the same change. `plugin/evals/` holds evals for the check's agents; run them with `claude plugin eval` when you change an agent.

## Commits

One change per commit, with a message that says what changed and why. The maintainer's rebuilt binary goes in its own commit, "plugin/bin/skill-health rebuilt". The app and the plugin share one version: `MARKETING_VERSION` in `version.env` and `version` in `plugin/.claude-plugin/plugin.json` (and the tool's own) change together, and a test fails if they differ.

By contributing, you agree that your contribution is licensed under the Apache License 2.0, as the rest of the project is (section 5 of [LICENSE](LICENSE)).
