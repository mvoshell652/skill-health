# Skill Health, plugin-driven: the build spec (2026-10-04)

## Why

The owner, 2026-10-04, in four messages:

- "this should be a claude plugin WITH a mac os menu bar app to monitor status, but everything is driven through the claude plugin"
- "I dont want to have to require people to add an API key or anything ... the menu bar needs to be the conduit to WHEN to use the plugin"
- "why 3 different surfaces?", then "i found ANOTHER surface, we need to consolidate this into the menu bar / leverage a claude plugin"
- "need to make a pass with /writing-for-interfaces" (on the menu)

The owner then chose:

- **Keep the Mac App Store possible.** The app keeps one read-only evidence view, so it is useful on its own.
- **Build it all.**

The design was reviewed by six agents: three researchers, covering plugin docs, the app inventory and Apple's rules, and three critics, covering feasibility, completeness, and the menu and copy. This spec folds in their corrections.

**One deviation from the reviewed design.** The reviewers assumed the plugin would write with shell scripts, and flagged several guards as risky to port to sh: exactly-once quote matching, all-or-nothing updates with rollback, file modes, and blob verification. Instead the plugin ships Skill Health's own Swift engine as a command-line tool, `plugin/bin/skill-health`, built from `Sources/skill-health`. This gives:

- One tested engine for app and plugin.
- No port of any guard.
- A plugin that works when the app isn't running.

Files in a plugin's `bin/` are on the Bash tool's PATH while the plugin is enabled (plugins/components docs).

## What each piece does

**The plugin** (Claude Code) does all the work, on the person's own Claude plan. There is no API key.

| Command | What it does |
|---|---|
| `/skill-health:check [skill]` | Checks skills for instructions that no longer work. Renamed from `/skill-health:audit`, which stays one release as a one-line alias. |
| `/skill-health:fix [skill]` | Goes through failing and deprecated instructions one at a time: fix the line, set it aside, draft an issue, or use another skill. |
| `/skill-health:update` | Updates skills you use that are behind their source and unchanged on this Mac. |
| `/skill-health:undo [skill]` | Puts back a fix or an update, or reopens a decision. |
| `/skill-health:status` | Shows the menu's three lists in a session: skills that need fixing, due for a check, with a newer copy. Runs no check and changes no skill; the model reads two short lists, a few thousand tokens, and the tool rewrites only its usage cache (0.6.0). It reads `status --json` (which now carries the first eight skills due for a check, so the whole `plan` isn't needed) and `update list --json`. |
| SessionStart hook | Shows the once-a-day note and passes the corrections to Claude. It also writes `plugin.json`, the handshake, and, when what Claude gets is a day old or was never made, starts `skill-health refresh` in the background (below). |
| PreToolUse hook | The write gate (below). |

**Which model a check runs on** (owner decision 2026-10-09, plugin 0.4.2): the two agents that do nearly all of a check's reading, `skill-health:auditor` and `skill-health:second-check`, say `model: sonnet` in their frontmatter, so a check never runs on the session's model when that is Opus. `sonnet` is Claude Code's alias for the newest Sonnet (Sonnet 5.5 on the Anthropic API since Claude Code 2.1.284; an older Sonnet on Bedrock, Google Cloud and Foundry), so a new Sonnet needs no plugin release. What can still change it, per Anthropic's sub-agents and model-config docs: a `model` passed per call (the check skill says not to), `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`, and an organization's `availableModels`, which substitutes the newest Sonnet it allows (or the session's model) with a warning. The skills name no model on purpose: a skill's `model:` switches the whole turn, and the switch re-reads the conversation without the prompt cache, which in a long session can cost more than the small orchestration it saves. There is no option to choose another model: a plugin option can't set an agent's frontmatter, an unset option reaches a skill's text as the literal `${user_config.KEY}`, and a choice list (`options`) stops the plugin loading on Claude Code before 2.1.271. The cost question says "The agents that read each skill run on Sonnet, unless your organization's settings choose another model." The coordinating turn (the plan, the two questions, the save) stays on the session's model.

**What a check spends, and how it spends less** (owner decision 2026-10-09, plugin 0.4.2). Measured on a 79-skill check on Sonnet 5.5: auditors were 81% of the tokens processed and second looks 19%; an auditor's cost tracked the skill's size (r = 0.78; two Swift skills with 164 and 276 KB of references cost about 4.2 million each, the median skill 260,000); and nearly all of it was cached re-reading, since every turn re-reads everything opened before it. 90 of the 245 findings were old-version or cosmetic, which nothing shows. So:
- The auditor reports only `breaks` and `deprecated`. It reads SKILL.md and short files whole, and in files over about 8 KB greps for the lines that carry checkable claims and reads around them. It opens several sources per turn, lets one page settle every claim it covers, and stops when every claim is checked. `maxTurns` 50 (the 79-skill run's longest auditor took 39).
- The second look is one agent per skill with findings, not one per finding: it gets the skill's findings numbered and answers with one verdict per finding, in order, judging each on its own. A skill whose second look returns fewer verdicts than findings isn't saved as checked. `maxTurns` 60. The eval `second-check-judges-each-finding-on-its-own` gives it one true and one false finding in the same skill.
- `oldVersion` and `cosmetic` stay valid in the file format, for results saved before 0.4.2; a check no longer writes them.
- **Unchanged skills are left out** (owner decision 2026-10-09). A save records each checked skill's fingerprint in findings.json (`trees`: skill to `SharedCorrections.tree` of its files, the same key the shared list uses). A skill is up to date while its files are exactly the ones a check covered in the last 90 days: a check saved here whose fingerprint matches, or the shared list's `checked` entry for these files. The check skill offers only skills that are due; a person can still name an up-to-date one. With nothing due it says when the next one is and spends nothing. 90 days because sources move on even when a skill doesn't. Checks saved before 0.4.2 have no fingerprint and count as changed.
- **Checked once for everyone.** `skill-health export-shared <file>` adds this Mac's checks to a known-corrections file: a "checked" entry and the kept failing and deprecated corrections for each skill whose files are exactly its public source's (the last comparison read the source, and nothing differs) and unchanged since its check, dated to the day. Nothing edited on this Mac, nothing without a GitHub source, nothing uncompared is shared, so no private text leaves the Mac; refused skills are listed with the reason. The owner runs it on `plugin/data/corrections.json` after a check and commits it; the plugin and the app ship it, and every identical copy then counts as up to date and gets the corrections with no tokens spent. No skill's allowed tools include it.
- **The estimate grows with size.** Each plan entry carries `tokens`: 75,000 plus 750 a KB of the skill's files, to the nearest thousand (`AuditPlan.tokens`), fitted on the 79-skill check in the units Claude Code reports for an agent (its context when it finished; the workflow's reported total and this measure agreed within 2%). The flat 180,000 stays only for audit-plan.json. Fitted before 0.4.2's lean reading, so it should overstate large skills; re-fit after the next real check.

**The Mac app** watches and says when. It never writes a skill.

- **Background work:**
  - reads which skills you use
  - matches the known corrections
  - compares with GitHub daily, but only after the person chose the first comparison
  - renders the hook's data files
  - shows the dot on the icon
- **Surfaces:**
  - the menu, used daily
  - one small setup window, "Skill Health Settings"
  - one read-only evidence window per skill, for the App Store path, used only when the plugin isn't connected and in sample mode
- **Removed:**
  - the Update Skills window
  - the four decision sheets and every decision button
  - the Settings sections Accuracy, Newer copies details, In Claude Code sessions, Needs your review and Decided

## Files in ~/.claude/skill-health: who writes what

| File | Writer | Readers |
|---|---|---|
| findings.json | plugin (`skill-health save-findings`; save-findings.sh kept one release) | app, plugin |
| decisions.json | plugin (`skill-health fix/decide/undo`) | app, plugin |
| updates.json | plugin (`skill-health update apply`). The app's daily compare prunes stale records, under the lock. | app, plugin |
| compare.json | app (daily compare), plugin (`skill-health compare`, `update apply`), each under the lock | app, plugin |
| backups/ | plugin | app (Finder only) |
| pending/&lt;id&gt;.json, pending/&lt;id&gt;/ | plugin | the gate hook |
| workspace/ | app, when it opens Claude Code; holds only a README.md saying what it is for | none: it is the working folder of the sessions the app opens, so Skill Health's own files are outside it |
| plugin.json | the plugin's SessionStart hook: `{"version": "...", "readAt": "ISO 8601"}` | app |
| hook-read | the plugin's SessionStart hook (touch; kept for older apps) | app |
| status.json, hook-note.json, hook-quiet.json | the plugin's tool (`skill-health refresh`, and after `save-findings`, `decide` and an applied fix, update or undo) and the app, with the same engine code; an atomic write of the same content, so either may write | hook, app, plugin |
| .refreshed, .refresh-lock | the tool's stamp after a refresh, and the hook's claim when it starts one (an empty file and an empty folder; their age is all that matters, and only one hook can make the folder) | hook |
| audit-plan.json, settings.json | app | plugin (audit-plan.json, for the old alias), app |
| usage-cache.json | app, and the plugin's tool whenever it reads which skills you use (a cache, rebuilt from the session files) | app, plugin |

**Lock.** `FileLock` in SkillHealthCore:

- **How it locks:** `mkdir ~/.claude/skill-health/.lock` (atomic), with an `owner` file inside holding `{pid, process, since}`.
- **When it counts as stale:** older than 10 minutes.
- **Waiting:** up to 5 s, then it fails with `SkillHealthError.busy`, whose message reads "Another Skill Health is saving its files. Try again in a moment."
- **A lock that can't be made at all** (a folder Skill Health can't write to) is reported as that, "Skill Health can't write to <folder>: <reason>", never as busy.
- **What takes it:** every read-modify-write of findings.json, decisions.json, updates.json and compare.json, in the Engine. The app and the command-line tool share that code, so both take it.

## The command-line tool: plugin/bin/skill-health

- **Where it's built from:** `Sources/skill-health`, with `Scripts/build_plugin_bin.sh` (a universal release build, `strip`, then copied to `plugin/bin/skill-health`). The binary is committed. `skill-health version` prints the plugin version and the git commit it was built from, and a test fails when the committed binary is older than the source.
- **Environment:** `SKILL_HEALTH_CLAUDE_HOME` overrides `~/.claude`, for tests.
- **Known corrections:** read from `plugin/data/corrections.json`, found relative to the binary as `../data/corrections.json`. `SKILL_HEALTH_CORRECTIONS` overrides it. `Scripts/package_app.sh` copies the same file into the app, so there is one file.
- **Output:** text that a person can read in the transcript and Claude can parse. `--json` is offered where a skill needs fields.
- **Errors:** on stderr, as `skill-health: <one sentence that says what to do>`. Exit codes: 1 for a refusal, 2 for a usage error.
- **Every refusal names the reason.** Silence never means "nothing to do".

| Command | Does |
|---|---|
| `skill-health version` | `Skill Health 0.6.1 (abc1234)` |
| `skill-health refresh` | Brings status.json, hook-note.json and hook-quiet.json up to date from the saved checks, the known corrections, the decisions and the usage, then stamps `.refreshed`. Prints how many corrections Claude will get. Exits 1 and leaves those files as they were while any of its inputs can't be read, including the skills folder. No network, no skill changed. It ends itself after ten minutes. Also run, quietly, after `save-findings`, `decide`, `compare` and an applied fix, update or undo. |
| `skill-health status [--json]` | Skills count, used count (with "at least" when usage doesn't cover 90 days), checked of used, failing and deprecated counts per skill, failing and deprecated counts set aside, newer-copy count, compare age, how many sources of skills you use couldn't be read at the last comparison. Never prints an all-clear when results can't be read. |
| `skill-health findings [skill] [--json]` | Open failing and deprecated findings in skills you use (with a skill named: all of that skill's open findings, and when it was checked). Each has: id, skill, severity, file, says, trueNow, evidence, wrongSince text, provenance, loads, choices (`fix` if suggested text exists and the file is writable; `write` (Claude proposes text) otherwise; `set-aside`; `issue` if the source is a GitHub repo; `another`), upstream (`same`, `differs`, `fileRemoved`, `skillRemoved`, `unknown`) and an earlier decision that lapsed. Failing first, then deprecated; then by loads. "Nothing to fix" only when nothing is open, nothing is set aside and every result was read; otherwise it says what is set aside or unreadable. A named skill never checked reads "<skill> hasn't been checked yet. Run /skill-health:check <skill>." |
| `skill-health fix preview <finding-id> [--with -]` | Builds the change (Engine.proposePatch, or the replacement read from stdin with `--with -`: non-empty, at most 2,000 characters, no hidden characters, not the quote itself; the audit's suggested text is held to the same rules). Writes `pending/<plan>.json` and prints the file path and the diff: hidden characters as ⟨U+XXXX⟩ (a warning line only when the change adds one the removed lines didn't have), and a long changed line cut around the change, about 60 characters each side, the unchanged rest as ⟨… N unchanged characters …⟩ (the same on both lines). Ends `Plan: <plan-id>`. |
| `skill-health fix apply <plan-id>` | Gated. Refuses an unknown, used or expired plan (15 minutes), a plan file that isn't exactly what the tool wrote or whose id isn't the one asked for, a finding that is no longer open, a file whose bytes changed since the preview, and a plan whose text isn't the file with exactly the finding's quote replaced by a replacement that passes the `--with` rules. Rebuilds the summary from what it will write and refuses unless it equals the plan's. Writes through Engine.patch (backup first, decision recorded; if the record can't be saved the file is put back), then marks the plan used (deleting it if that fails), and prints the result line. |
| `skill-health decide <finding-id> set-aside 30\|90\|until-update` | Engine.record with the 180-day cap. `until-update` stores the source fingerprint and needs a compare entry. |
| `skill-health decide <finding-id> another <skill>` | The skill must be installed and different. |
| `skill-health decide <finding-id> reopen` | Removes the decision (a patched finding must be undone instead). Refuses with the reason when the decisions can't be read. |
| `skill-health issue <finding-id> [--open]` | Prints the title, the body, and GitHub's new-issue URL. With `--open`, opens the URL and records reportedAt. If the URL would pass 7,000 characters, the body is cut short and the full text is put on the clipboard with `pbcopy`. |
| `skill-health undo list [--json]` | Most recent first: fixes (patch records), updates (manifests), set-asides and other-skill decisions that still hold (a lapsed set-aside is already open, so it isn't listed). Ids are `fix:<finding-id>`, `update:<skill>:<stamp>` and `decision:<finding-id>`. Each detail names the line or the instruction. Fails with the reason when results or decisions can't be read. |
| `skill-health undo preview <entry>` | For a fix: the diff from the current file to the original, with a plan; refused if the file changed since the fix. For an update: the files put back and removed (words from each file's blobs) and the skill's folder, with a plan. For a decision: says to run `skill-health decide <id> reopen` (no plan, no skill write). |
| `skill-health undo apply <plan-id>` | Gated. A fix is put back from its decision record (the finding itself may be gone after a re-check). An update's manifest must be in Skill Health's backups, name its own skill folder (the installed skill's), and have each entry's kind agree with its blobs; a path that is now a folder is refused; if the update record can't be saved, the update's files are put back and nothing has changed. |
| `skill-health update list [--json]` | Eligible skills (used, behind, unchanged here), the left-out ones with a reason (`changedBoth`, `removedAtSource`), the compare age (stale after a day), and what the last comparison couldn't establish (sources it couldn't read, a stop at GitHub's limit), never "nothing to update" as if it were known. |
| `skill-health update preview <skill>... \| --all` | Each skill prepared on its own (one bad file skips that skill, not all), downloads verified against blob ids and staged under `pending/<plan>/`. Prints each skill's files with kind (added, changed, removed) and diffs, up to 20,000 characters, then "N more changed lines aren't shown here; each file's full new copy is in <folder>." Ends `Plan: <plan-id>`. |
| `skill-health update apply <plan-id>` | Gated. Checks every change against the last comparison and this Mac's files, then against GitHub itself: for each repository and commit, one listing, and every written file's blob and executable mode must be GitHub's, every removed path absent, and each change's kind must follow from its blobs. A skill GitHub can't confirm is left as it was ("Skill Health couldn't reach GitHub to confirm this update"). Calls Engine.applyUpdates (all or nothing per skill; a rollback touches only files it wrote or removed) and writes `backups/<skill>/<stamp>-update/.manifest.json` so the update can be undone. A skill updated whose undo record couldn't be saved gets its attention line first, no undo line, and a non-zero exit. |
| `skill-health compare` | Compares now (Engine.checkSources) under the lock. Prints the summary, sources it couldn't read, and any stop at GitHub's limit with "Run skill-health compare again after that to finish." |
| `skill-health plan [--json]` | Check candidates: used skills, the due ones first (never checked, most loads first; then checked longest ago), then the up-to-date ones a check leaves out. Each has checked date, upToDate, recheckDue, its own token estimate, size, repo and installedAt. Refuses when the results can't be read, or when some entries can't and a save would lose them (not for unreadable decisions: a check can still be saved). Its text lists 12 skills, then "and N more". |
| `skill-health save-findings -` | Engine.save(AuditResults) from JSON on stdin, under the same rules as save-findings.sh (AuditResults.problem). Refuses while findings.json has entries Skill Health can't read, naming the count and the remedy. Every refusal begins "Nothing saved:" and names the rule and the JSON field. The success line counts the findings and skills actually saved, after duplicates are merged. |

**Plan file** `pending/<id>.json`, schema 1:

```
{"schema":1,"id":"<UUID>","kind":"fix|update|undo","createdAt":"…","expiresAt":"…","used":false,
 "summary":"<what the approval prompt shows, at most 3,000 unicode scalars, the unit the gate's jq counts>", "fix"|"update"|"undo": {…}}
```

Apply refuses a plan file unless it is byte for byte what the tool writes for the plan it decodes (sorted keys, pretty printed), so a repeated key can't make the gate and the tool read different summaries, and unless its id is the one asked for.

## The write gate

- **What approves a write:** the person's click in Claude Code's own permission prompt, which shows the plan's summary. The model choosing to ask is not enough.
- **Skills:** a skill's `allowed-tools` never names an `apply` command, and only names read-only or non-skill-writing commands (status, findings, fix preview, decide, issue, undo list/preview, update list/preview, compare, plan, save-findings, version).
- **The hook:** `plugin/hooks/hooks.json` has a PreToolUse hook, matcher `Bash`, that runs `sh "${CLAUDE_PLUGIN_ROOT}/scripts/gate.sh"`. gate.sh reads the hook JSON on stdin and does this:
  - One trailing new line is trimmed first.
  - **The canonical apply:** the whole command is exactly `<tool> <fix|update|undo> apply <UUID>`. The tool may be bare (`Skill Health`), a path, a quoted path (either quote may sit inside the other kind) or a path with backslash-escaped spaces. When CLAUDE_PLUGIN_ROOT is set, a path must resolve (cd -P, pwd -P) to `$CLAUDE_PLUGIN_ROOT/bin/skill-health`; any other program gets deny, "That isn't Skill Health's own tool. Run the apply command exactly as the preview printed it." Then the plan, from `$SKILL_HEALTH_DIR/pending/<id>.json` with jq: missing, used, expired, or of another kind is a deny saying which; a summary longer than 3,000 code points is a deny ("That change is too long to show in full here, so it can't be approved. Run the preview again."). Plan state and length are said before the permission mode. Then `permission_mode` `bypassPermissions` or `dontAsk` gets deny, "Skill Health doesn't write a skill while permission prompts are skipped. Switch to a mode that asks (Shift+Tab), then run the command again.", and any other mode gets `ask` with `permissionDecisionReason` = `Skill Health will write this change.\n\n<summary>`.
  - **Any other spelling of a run:** a command that contains the word `apply` and names a UUID whose `pending/<uuid>.json` exists gets deny with the form to use, including the plan's kind and, when CLAUDE_PLUGIN_ROOT is set, the full tool path. This catches a tool path in a variable, a wrapper with flags, an escape or a chain without parsing the shell, because every run must name a live plan.
  - **Everything else gets no opinion.** A mention of the words with no live plan id (a commit message, a PR title, a heredoc, `git log --grep`) is never denied.
  - **Without jq:** a command naming a live plan id is denied, saying jq is needed; everything else gets no opinion.
  - **What it doesn't guarantee:** a run that builds the plan id or the word apply at run time gets no opinion. The tool's own checks still apply.
- **The tool's own checks still apply behind the hook:** expiry, single use, unchanged bytes, the plan file's exact bytes and id, and the summary. Apply rebuilds the summary from what it is about to write and refuses unless it equals the plan's (`PendingPlan.fitted`), so a plan file changed after the preview can't write anything but what the prompt showed. A fix's or a fix undo's summary must fit the prompt whole (3,000 unicode scalars). An update's summary is not refused when longer: it is cut at 3,000 scalars with a note, so the prompt lists the files and says so when the list is cut, and the preview above it carries the diffs (up to 20,000 characters). An update is also checked against the last comparison and then against GitHub itself (see `update apply`). A plan is marked used only once something was written, so a busy lock or a refusal leaves it to run again; every apply re-checks the bytes it replaces, so it can't write twice.
- **Where Claude Code works:** sessions the app opens start in `~/.claude/skill-health/workspace`, an empty folder, so Skill Health's plans in `~/.claude/skill-health/pending` are outside the working folder that acceptEdits mode lets Claude edit without asking.

## SessionStart hook and plugin options

The manifest gains `userConfig`:

- `session_note` (boolean, default true; title "Session note"; description "One line at the start of a session, at most once a day, when a skill you use has a failing or deprecated instruction.")
- `corrections_for_claude` (boolean, default true; title "Corrections for Claude"; description "Claude gets the corrections at the start of every session.")

The person changes them with `/plugin configure Skill Health`. They replace the app's two switches.

`session-start.sh` reads `CLAUDE_PLUGIN_OPTION_SESSION_NOTE` and `CLAUDE_PLUGIN_OPTION_CORRECTIONS_FOR_CLAUDE`, which are unset or "true" by default (both off: it prints nothing and starts no refresh):

- **Session note off:** never print the note; corrections only (hook-quiet.json).
- **Corrections off:** print the note without `additionalContext` (jq `del(.hookSpecificOutput)`).
- **Every run:** writes `$SKILL_HEALTH_DIR/plugin.json` (`version` from `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`) and still touches hook-read.

**The plugin keeps them up to date on its own (0.6.0).** Until 0.6.0 only the app wrote status.json and the two hook files, so Claude got no corrections without the app, and none a week after the app last ran. Now:

- `skill-health refresh` joins the saved checks, the shipped known corrections and the person's decisions exactly as `status` does, makes the snapshot with `StatusSnapshot.make`, and writes it with `Engine.writeStatus`, then stamps `.refreshed`. It leaves status.json and the two hook files as they were (the usage cache is still rewritten), and exits 1, while the skills folder can't be listed or the results, the decisions, the known corrections or the usage can't be read: an empty list written over a good one would silence the corrections. No network, no skill changed.
- `save-findings`, `decide` and an applied `fix`, `update` or `undo` refresh afterwards, without failing the command that just succeeded.
- The hook starts `skill-health refresh` when neither status.json nor `.refreshed` was written in the last 20 hours (a file dated in the future doesn't count), claiming the start by making `.refresh-lock`, which only one of several sessions starting together can do and which is replaced after ten minutes, detached (`nohup`, every stream closed) so Claude Code never waits for it. It passes the folder it reads as `SKILL_HEALTH_CLAUDE_HOME`. It starts nothing when both options are off, when the plugin has no tool, when there is no skills folder to read, or when `CLAUDE_CONFIG_DIR` points anywhere but `~/.claude` (Skill Health works on `~/.claude`). A refresh that can't finish is tried again at a later session start, no sooner than ten minutes on. The first session after an install therefore prints nothing and starts the work; the next one prints the note and the corrections. Measured on the author's Mac against 8 GB of session history (10,630 files): 27 seconds the first time, 0.9 seconds once the usage cache exists.
- The hook's own 7-day rule stays as a safety net: files older than that print nothing.

**The app always renders both the note and the corrections.** The note text changes to:

- Failing: `skill-health: 2 skills you use have instructions that now fail (gcp-cloud-run, supabase). Run /skill-health:fix to go through them. Claude gets the corrections at the start of every session.`
- Deprecated only: `skill-health: 1 skill you use has deprecated instructions (tailwindcss). Run /skill-health:fix to go through them.`

Corrections given to Claude use "Evidence:" in place of "Source:".

## The menu (copy reviewed with writing-for-interfaces; the HIG checked)

**Redesigned 2026-10-09** (owner critique: "everything is calling to open Claude, which is repetitive; the menu bar app is supposed to be more informative across all aspects of skills"). Knowing is free, doing costs tokens: the menu says what is true about the skills you use, each skill a row that opens its page in Skill Health; every command that hands off to Claude Code sits in one submenu.

**Conventions:**

- **Header:** a section header that states a fact in sentence case, with no final period.
- **Skill row:** the skill's name, as the title. Its second line says the facts ("14 failing, 3 deprecated · used 183 times"). VoiceOver reads both: measured 2026-10-09 on macOS 27, AppKit's label is "gcp-cloud-run, 14 failing, 3 deprecated · used 185 times" (an earlier note here said AppKit doesn't expose the second line; it does now). It opens the skill's page (the evidence window).
- **Other items:** a verb first, title case, with no articles. Skill names keep their case.
- **Hand-offs:** one item, "Open in Claude Code", a submenu (no ellipsis, as submenus take none). Its items end with an ellipsis, because the command is typed in and waits for Return. "in Claude Code" is said once, by the submenu.
- **Second lines** only add to what the title says.

**Fix group** (failing = Breaks, deprecated = Deprecated; Old version and Cosmetic never appear in the menu):

- **Header:** "35 skills need fixing" / "1 skill needs fixing": the thing a person acts on is a skill. The icon's accessibility label keeps the instruction counts ("Skill Health, 105 failing instructions, 38 deprecated").
- **Rows:** skills you use with an open failing or deprecated instruction, those with a failing one first, then most used, at most 5. Not by the number failing: on the real menu that put a skill used twice in 90 days (21 failing) above one used 185 times. Second line "14 failing, 3 deprecated · used 183 times" ("used once" for one load).

**Check group** (N = skills you use, C = checked of those, D = due for a check (`Coverage`), Z = open failing or deprecated, A = failing set aside):

- **N = 0:** "No skills used in the last 90 days".
- **C = 0:** "None of the 79 skills you use checked yet" / "The skill you use isn't checked yet".
- **D > 0:** "2 skills you use are due for a check" / "1 skill you use is due for a check", with the due skills as rows (at most 5, most used first): "Never checked · used once", "Changed since its check on Oct 1 · used 21 times", "Last checked Jul 1 · used 4 times".
- **Nothing due, usage doesn't cover 90 days:** "5 of 79 skills you use checked" / "79 skills you use checked" (never "all": more may have been used; Settings says since when sessions are kept).
- **Nothing due, 0 < C < N:** "5 of 79 skills you use checked". When Z = 0, add ", none failing in those", or when A > 0, ", 2 failing instructions set aside".
- **Nothing due, C = N:** "All 79 skills you use checked since Sep 26" (the oldest check). When Z = 0, add ", none failing", or the set-aside clause.
- **Findings unreadable:** "Skill Health couldn't read the results of earlier checks".
- **After a check opened Claude Code:** "Check opened in Claude Code 12 minutes ago" until findings.json changes or 2 hours pass. Opened, never "running".
- **With no rows** (nothing due), the sentence heads the closing group, the one with "Open in Claude Code" (or "Set Up Claude Code Plugin…"); in state F, it goes last, where the view draws an item-less group above Settings….

**Update group** (U = used skills behind and unchanged here; absent when U = 0):

- **Header:** "23 skills you use have newer copies" / "1 skill you use has a newer copy".
- **Rows:** those skills, most used first, at most 5, second line "used 21 times".

**Open in Claude Code** (state G only): "Fix All 35 Skills…" (`/skill-health:fix`; "Fix gcp-cloud-run…" for one skill, nothing for none), "Check Skills…" (`/skill-health:check`; "Check 2 Skills…" while 2 are due), and "Update 23 Skills…" (`/skill-health:update`, only with newer copies). When nothing can open Claude Code, each has the second line "Copies the command to paste into Claude Code".

**A skill's page** (the evidence window, opened from any skill row): a section of what Skill Health knows (`SkillPageText`):
- **Used:** "195 times in the last 90 days" (or "since Aug 25", when sessions are kept only since then).
- **Source:** "TerminalSkills/skills, installed Jun 1", with how the copy stands at the last comparison ("A newer copy is at its source. Run /skill-health:update in Claude Code to take it.", "Changed on this Mac since it was installed.", …), or "No install record, so Skill Health can't compare it with a source".
- **Checked:** "Oct 9, unchanged since" with "Due for another check Jan 7."; "Oct 9, changed since"; "Never".

Then each open failing or deprecated instruction, or "No open failing or deprecated instructions." Its one action: "Fix in Claude Code…" when there is something to fix (`/skill-health:fix <skill>`), else "Check in Claude Code…" when the skill is due (`/skill-health:check <skill>`).

**States:**

- **A. No folder:**
  - Header "Skill Health can't see your skills yet".
  - Item "Choose Claude Folder…" opens the folder panel directly.
- **B. Reading:** header "Reading your skills…", and Settings… directly under it.
- **C. Folder unreadable:**
  - Header "Skill Health couldn't read your Claude folder".
  - Item "Choose Claude Folder Again…".
- **D. Usage unreadable:**
  - Header "Skill Health couldn't read which skills you use".
  - Item "Read Skills Again", which acts at once, so it has no ellipsis.
- **E. Plugin not installed and never connected:**
  - The groups above, with their rows (the App Store path: everything there is to know, no plugin needed).
  - Then one closing item, "Set Up Claude Code Plugin…", second line "Fixing, checking and updating happen in Claude Code". It opens the setup window.
- **F. Plugin older than this app needs:**
  - Header "The Claude Code plugin is older than Skill Health".
  - Item "Update Claude Code Plugin…" opens the setup window.
  - Then the groups above, with their rows, and no hand-off.
- **G. Normal:** the groups above, then "Open in Claude Code".
- **H. Sample skills:**
  - Header "These are sample skills".
  - Each fix row is the skill's name ("supabase-basics") and opens its page.
  - Then "Choose Claude Folder…".
  - No hand-off items.
- **Problems:** an unreadable decisions.json adds a header with the problem in words, and the item "Open Settings…". An unreadable findings.json is said once, as "Skill Health couldn't read the results of earlier checks": the check group's header (which wins over "Check opened in Claude Code …"), or, when there is no check group (usage unreadable, sample skills), a group of its own with "Open Settings…".
- **Arriving at the plugin:** "Set Up Claude Code Plugin…" and "Update Claude Code Plugin…" open the setup window scrolled to the plugin row, with focus on its control. "Open Settings…" opens it at the top.
- **Opening Skill Health again** (Finder, Spotlight, the Dock) while it runs with no window showing brings back the setup window.

**Every state ends with** "Settings… ⌘," and "Quit Skill Health ⌘Q".

**Menu bar icon:** the dot shows only when something is failing or deprecated. The accessibility label is "Skill Health, 3 failing instructions, 4 deprecated", or "Skill Health".

**Opening Claude Code:**

- **Where, in order** (owner decision 2026-10-09):
  1. **The Claude app**, when the app that handles `claude://` is one of the copies with bundle ID `com.anthropic.claudefordesktop`: `claude://code/new?q=<percent-encoded command>&folder=<claude folder>/skill-health/workspace`. It opens the Code tab's new-session page with the command typed in as a command (`/check [skill name]`, run on Return), not sent (measured 2026-10-09: opening the link made no session). It needs no permission from macOS. The app asks before it uses the `folder`, every time, even for a folder it trusts (Anthropic's help article "Open Claude Desktop with a link"); declined, the session keeps the folder last used, and Skill Health's gate still guards every write. Documented parameters: `q` (alias `prompt`), `folder` (only the first is used), `file` (accepted, not supported).
  2. **A terminal,** when Claude Code has registered its own link: `claude-cli://open?q=<percent-encoded command>&cwd=<claude folder>/skill-health/workspace`. It opens a new window in the terminal Claude Code last ran in, with the command typed in, not sent, under a "Prompt from an external link" banner (Anthropic's "Launch sessions from links" page).
  3. **Neither:** the alert below.
- **Never the browser.** Claude Code on the web runs in the cloud, on a copy of a GitHub repository; it can't read or change the skills on this Mac.
- **The person's choice:** Settings shows "Open commands in" (Claude App / Terminal) only when both are on this Mac and menu items can hand off. The line under it says what opens: "A new Code session in the Claude app, with the command typed in. The app asks each time before it uses Skill Health's folder." / "A new window in the terminal you last used Claude Code in, with the command typed in." Stored in the app's defaults (`openCommandsIn`), not settings.json: only the app opens anything. A choice that is no longer installed falls back to the other.
- **The terminal's permission prompt is Claude Code's, not Skill Health's.** Claude Code drives Terminal and iTerm with AppleScript. Its link handler (`~/Applications/Claude Code URL Handler.app`) runs the versioned binary through a symlink and declares no usage description, so macOS asks whether "2.1.289" (the binary's file name) wants to control Terminal. Skill Health can't change that text. Before the first command opens in a terminal, Skill Health says so in its own alert, once per Mac: title "Claude Code May Ask to Control Your Terminal"; body "Claude Code opens /skill-health:update in a new terminal window. macOS may ask whether Claude Code can control your terminal: the first time, and again after Claude Code updates. The request shows Claude Code's version number, like “2.1.289”, instead of its name. Choose Allow. If you choose Don't Allow, no window opens until you turn it on in System Settings > Privacy & Security > Automation. Nothing runs until you press Return."; buttons "Continue" and "Cancel". Cancel opens nothing, copies nothing, and the note comes back next time. The note counts as shown only once a terminal link actually opened. macOS keys the permission to the binary's path, which changes with each Claude Code update, so the prompt likely returns under the new number; Skill Health can't read that version from the sandbox, so the note says so instead of coming back. Skill Health can't see whether the window opened either: after Don't Allow, the menu still says the check was opened.
- **The folder:** either link starts in `<claude folder>/skill-health/workspace`, so trust is asked about one folder, once. The app makes the folder (with a README.md) before opening; it is not `<claude folder>/skill-health` itself, because Skill Health's pending plans sit there and acceptEdits mode lets a session edit its working folder without a prompt. If the folder can't be made, the app copies the command and shows the alert below.
- **Skill names:** checked against `^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$` before they go in a command.
- **When `NSWorkspace.shared.urlForApplication(toOpen:)` finds no handler for either link** (no Claude app, and Claude Code registers its own after the person's first prompt), or the open fails: copy the command and show an alert. Title "Couldn't Open Claude Code"; body "/skill-health:fix supabase is copied. Paste it into a Claude Code session and press Return."; button "OK".

## The setup window ("Skill Health Settings")

Designed from a critique of the first build (information architecture, writing, visual design, accessibility and interaction; 2026-10-04). The words live in `Sources/SkillHealthCore/Menu/SettingsText.swift`, tested in `SettingsTextTests`; the views are thin.

- **Top line,** plain text above the form (not in it: a grouped form gives every section a card or restyles it as a heading), aligned with the rows' text, by state: before a folder, the purpose ("Skill Health tells you when a skill you use has a failing or deprecated instruction. You fix it in Claude Code, with the Skill Health plugin.") and "Next: choose your Claude folder."; sample skills, "These are sample skills, so you can try Skill Health without Claude Code." and "Next: choose your Claude folder to see your own."; then "Next: install the Claude Code plugin." / "Next: start a Claude Code session to connect the plugin." / "Next: update the Claude Code plugin."; once everything is ready, "Skill Health is set up." and how it tells you (the dot, or with the icon hidden, the plugin's session note).
- **Needs attention** (only when something is wrong): one warning row per problem (folder access, a failed write, unreadable results, unreadable decisions).
- **Claude Code:** two rows, each with ONE trailing control and its state in the lines under the title. The only green check in the window is the plugin's "Connected".
  - *Claude folder* (the title in every state): not chosen ("To see which skills you use, Skill Health reads this hidden folder. In the next window, click Allow."; Try with Sample Skills, Choose Folder…); reading; failed (warning, the reason last, Choose Again…); sample ("Using sample skills", Choose Claude Folder…); ready (`~/.claude`, the counts line, "Claude Code has kept sessions only since Aug 25." while the count is a lower bound, Change…); usage unreadable (warning, Read Skills Again, and Change… under it).
  - *Claude Code plugin* (hidden for sample skills): before a folder, it waits for one; not installed (the reason, the command in a block, "Then start a Claude Code session to connect it.", Copy Command, which reads "Copied" for 3 seconds); installed (Waiting, "Installed. Start a Claude Code session to connect it."); connected (Connected, "Run these in Claude Code:" and the four commands on a line of their own, so a break never falls inside one); older (warning, the update command, Copy Command). The link note shows only when the plugin is installed and nothing can open Claude Code (no Claude app, and Claude Code's terminal link isn't registered).
  - *Open commands in* (only when both the Claude app and the terminal link are on this Mac): a pop-up menu, Claude App / Terminal, with what opens on the line under it (see "Opening Claude Code").
- **Launch at login offer (first run, once):** a card between Claude Code and Newer copies, shown only once a real folder is ready, while Launch at login is off and not yet answered, never for sample skills. "Open Skill Health when you log in?" / "It keeps the dot in the menu bar and the daily comparison working. You can change this later in Settings." / No Thanks, Open at Login. Either answer is remembered (`loginOfferAnswered`), and so is using the switch under On this Mac (or one macOS wants approval for), so it is asked once; the switch stays. Both buttons are ordinary, not filled: the window's one filled button is the step its top line names, and this side question must not take Return from it. The title is a heading. "No Thanks" and not "Not Now", which the bottom bar uses for closing the window. If macOS needs approval or refuses, the switch's row says so, and speaks it. `-debugShowLoginOffer YES` shows it for a layout check, and is inert.
- **Newer copies,** the row "Compare with GitHub" (once a folder is ready, or sample skills): Compare Now, then Compare Again, which stays in place, disabled, while comparing. The line under it says what the last comparison established, never a check: never compared (the consent sentence and the daily note); paused at GitHub's limit (and "Choose Compare Again after that." when Compare daily is off); every source failed; some failed; success ("Compared 5 minutes ago. None of the 41 skills you use that have a source has a newer copy." / newer copies with "Run /skill-health:update in Claude Code"; a newer copy left alone because it was changed on this Mac too is said as such, and then "none" becomes "none … has a newer copy that's safe to take"); usage unknown ("Compared 5 minutes ago." only). Times are live. Then the toggle "Compare daily": "Only while Skill Health is running. It sends GitHub the names of the repositories your skills came from, and when you installed them."
- **On this Mac:** "Show Skill Health in the menu bar" first (on: what the dot means; off: how to come back, and that the window opens at each start when Launch at login is on), then "Launch at login" ("Keeps the dot and the daily comparison working."; macOS approval as a warning line with Open Login Items). Footer: "To come back to this window, choose Settings… in Skill Health's menu, or open Skill Health from Finder or Spotlight."
- **Bottom bar:** "Not Now" (Esc) only before a real folder is ready (not chosen, reading, failed, sample). After that there is no Done: settings apply as they change, and Esc or ⌘W closes.
- **Announcements:** the folder's result (and a folder refused from the menu opens this window so the reason can be seen), a failed read of which skills you use when the person asked for it, the plugin moving to waiting or connected, a copied command, the comparison's start and its line, the menu bar switch turned off, launch at login approved, refused or waiting for approval.

## The evidence window (read-only)

- **One window per skill**, titled with the skill name.
- **Each open finding shows:**
  - severity in words ("Failing" or "Deprecated", never "Breaks")
  - "The skill says", "True now" and "Evidence" (a link)
  - when it became wrong
  - provenance: a known correction from <where>, or checked on <date> and kept after a second look tried to disprove it
- **No decisions.**
- **Bottom:**
  - Plugin connected: a button "Fix in Claude Code…".
  - Otherwise: "Fixes happen in Claude Code with the Skill Health plugin." and a button "Set Up Plugin…" that opens the setup window.
  - Sample mode: "These are sample skills. Choose your Claude folder to see your own."

## Word list

| Use | Meaning | Never |
|---|---|---|
| check | for accuracy against current documentation | audit; and the daily GitHub comparison is "compare" |
| second look | the pass that tries to disprove a finding | second check, second pass |
| failing | Breaks | "fail" for deprecated |
| deprecated | Deprecated | |
| fix | change a line of a skill | patch |
| update, newer copy | bring a skill up to its source | fix |
| evidence | a finding's link | source |
| source | the repository a skill came from | |
| skills you use | loaded in the last 90 days | |
| Claude | the model | |
| Claude Code | the app | |
| Claude folder | ~/.claude | .claude folder, your folder |
| connected | the plugin's hook has run in a Claude Code session; nothing else | for the folder |
| start a Claude Code session | what connects the plugin | Claude Code starts |
| paused | a comparison GitHub's hourly limit interrupted | stopped |
| dot, icon | the mark on Skill Health's menu bar icon, and the icon | |
| click | a mouse action on a button | select (for a button) |
| what you fixed or set aside | the person's decisions | decisions |
| draft an issue | | tell the author |

## Order of work

0. Remove the in-app check and the API key. Done.
1. Core: FileLock and its use in Engine; the plan files; the command-line tool; corrections moved to plugin/data; the build script; tests.
2. Plugin: skills check, fix, update and undo, plus the audit alias; the gate hook; session-start options and handshake; userConfig; evals; script tests.
3. App: the menu as above; the setup window; the evidence window; removals; a wider watcher (findings, decisions, updates, compare and plugin.json); the handshake; deep links with cwd and the handler check; StatusSnapshot copy.
4. Docs: README, privacy policy, review notes, listing and CHECKLIST.
5. Later, after a release of dogfooding: delete the Swift write paths that no longer have a caller in the app (they stay in the engine, because the tool uses them).

## To verify by hand (not documented, so a test can't prove it)

- [ ] **The gate:** in default, acceptEdits, auto and bypassPermissions modes, an `apply` shows the prompt with the summary, or is denied in bypass. A commit message or PR title starting with the apply words is not blocked. An apply run through a variable or a wrapper is denied with the form to use.
- [ ] **A deep link with cwd** opens Claude Code in `~/.claude/skill-health/workspace`, trust is asked once, and in acceptEdits mode an edit to `~/.claude/skill-health/pending/…` still asks.
- [ ] **userConfig:** `/plugin configure skill-health@skill-health` shows both options, and turning them off changes the session-start output.
- [ ] **Reopening:** with the icon hidden and the window closed, opening Skill Health from Finder or Spotlight shows the window.
- [ ] **The setup window on screen,** in light and dark, active and inactive: the top line's alignment, the plugin card with its command block, the scroll to the plugin row from "Set Up Claude Code Plugin…", focus on Copy Command, and VoiceOver's reading of each row.

## The tool's JSON (the contract the skills rely on)

Field names are fixed; text output may change. Dates are ISO 8601 (UTC). Severity values: `breaks`, `deprecated`, `oldVersion`, `cosmetic`.

`skill-health status --json`
```
{"skills": 1639, "used": 79, "usedIsLowerBound": true, "checkedUsed": 5, "failing": 3, "deprecated": 4,
 "setAsideFailing": 1, "setAsideDeprecated": 0,
 "bySkill": [{"skill": "gcp-cloud-run", "failing": 1, "deprecated": 2, "loads": 175}],
 "newerCopies": 23, "comparedAt": "…" | null, "compareStopped": "…" | null, "comparedProblems": 0,
 "findingsProblem": "…" | null, "correctionsProblem": "…" | null, "decisionsProblem": "…" | null,
 "usageProblem": "…" | null, "compareProblem": "…" | null}
```

`skill-health findings [skill] --json`
```
{"findings": [{"id": "UUID", "skill": "supabase", "severity": "breaks", "file": "SKILL.md",
   "says": "npm install -g supabase", "trueNow": "…", "evidence": "https://…", "wrongSince": "Wrong since it was written (Feb 18, 2026)",
   "provenance": "Known correction, first found in owner/repo · skill on Sep 26, 2026" | "Found by a check on Oct 3, 2026, kept after a second look",
   "loads": 188, "suggested": "…" | null, "alternative": "…" | null,
   "choices": ["fix" | "write", "set-aside", "issue", "another"],
   "upstream": "same" | "differs" | "fileRemoved" | "skillRemoved" | "unknown",
   "decision": null | {"status": "patched|setAside|usingAnotherSkill", "on": "…", "until": "…" | null, "skill": "…" | null,
                       "lapsed": "expired" | "sourceChanged" | "lineCameBack" | null}}],
 "failing": 1, "deprecated": 1, "other": 0, "skills": 1, "setAsideFailing": 0, "setAsideDeprecated": 0,
 "checkedOn": "…" | null (only with a skill named), "problem": "…" | null}
```
Every finding listed is open. A non-null `decision` is an earlier one that no longer holds, and `lapsed` says why: a set-aside that ran out, a set-aside until the next update whose source changed, or a fixed line that came back. `other` counts old-version and cosmetic findings. `problem` says when some findings couldn't be read. When the results file or the decisions can't be read at all, `findings`, `plan` and `undo list` fail with the reason instead of answering, since an empty answer would say there is nothing to do.
`choices` holds `fix` when there is suggested text and the file can be written, otherwise `write` (Claude proposes the line and passes it with `fix preview <id> --with -`). It holds `issue` only when the skill's source is a GitHub repository.

`skill-health plan --json`
```
{"skills": [{"name": "vite", "loads": 21, "checkedOn": "…" | null, "upToDate": false, "recheckDue": "…" | null,
  "tokens": 91000, "files": 4, "bytes": 21034,
  "folder": "/Users/…/.claude/skills/vite", "repo": "owner/repo" | null, "installedAt": "…" | null}]}
```
Order: the skills due first (never checked, most loads first; then checked longest ago, including ones changed since), then the up-to-date ones, soonest due first. `tokensPerSkill` is gone (0.4.2): each skill carries its own `tokens`.

`skill-health undo list --json`
```
{"unreadable": ["<backup folder whose undo record can't be read>"], "entries": [{"id": "fix:UUID" | "update:skill:STAMP" | "decision:UUID", "kind": "fix" | "update" | "decision",
  "skill": "supabase", "when": "…", "detail": "Line 10 of SKILL.md: npx supabase --help" | "1 line in SKILL.md: <text>" | "4 files" | "Set aside until Nov 3: npm install -g supabase" | "Using vercel-deploy instead: npm install -g supabase"}]}
```

`skill-health update list --json`
```
{"comparedAt": "…" | null, "stale": false, "comparedProblems": 0, "stopped": "…" | null,
 "eligible": [{"skill": "vite", "loads": 21, "repo": "owner/repo", "history": "https://…" | null}],
 "leftOut": [{"skill": "my-deploy", "reason": "changedBoth" | "removedAtSource", "why": "changed on this Mac, so updating would write over your changes"}]}
```

`leftOut` lists skills you use that have something newer at their source (or whose source is gone) and aren't offered; `reason` is stable for the plugin's commands to match. A copy changed on this Mac whose source hasn't moved has nothing newer and is in neither list.

Previews (`fix preview`, `update preview`, `undo preview`) print the change, then a last line `Plan: <UUID>`. The apply commands take that UUID.
