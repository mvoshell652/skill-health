# Review of the plugin-driven build, 2026-10-04

Four reviewers (write safety, plugin contract, app, words and access) read the `plugin-driven` branch. A skeptic then tried to disprove each finding, by running it where it could. This is every finding, the skeptic's verdict, and what was done. Refuted findings were left as they were.

| Lens | # | Verdict | Severity | Finding | Outcome |
|---|---|---|---|---|---|
| words-access | 0 | confirmed | medium | Session note says Claude gets the corrections even when the person turned that option off | Fixed: session-start.sh drops the sentence (StatusSnapshot.correctionsTail); HookScriptTests.correctionsOffDropsTheSentenceSayingClaudeGetsThem |
| words-access | 1 | confirmed | medium | /skill-health:update tells people a skill they edited has a newer copy when it has none | Fixed: update list gives a `reason` code and no longer lists a copy changed only here; update/SKILL.md matches on it |
| words-access | 2 | confirmed | medium | skill-health findings and status give an all-clear when the saved results can't be read | Fixed: findings, plan and undo list fail with the reason; status skips the all-clear; ToolTests.unreadableResultsStop… |
| words-access | 3 | confirmed | medium | Count lines in the tool and /skill-health:fix break zero and one: 'None of the 1 skills', '1 haven't', 'Nothing to fix' with nothing checked | Fixed: checkedLine and the empty-findings lines handle none and one, update preview and compare too; ToolTests.countsReadRightForNoneAndOne |
| words-access | 4 | confirmed | medium | Banned words 'audit' and 'patch' in error text a person reads | Fixed: SkillHealthError wording; save-findings no longer doubles its prefix |
| words-access | 5 | confirmed | medium | GitHub rate-limit message says 'checks'; the stale note says 'compare checks again' | Fixed: "60 requests an hour", "Run skill-health compare to compare again" |
| words-access | 6 | refuted | medium | When Claude Code can't be opened, the menu titles still promise it, and only a subtitle (not exposed to accessibility) says it will copy instead | Left: the skeptic refuted it. |
| words-access | 7 | plausible | low | Unreadable findings.json shows two menu headers for one fault, in different words, with a file name and a system error | Fixed: no second menu header for an unreadable results file; one wording for decisions in app and tool |
| words-access | 8 | refuted | low | Issue draft labels the evidence link 'Source:' | Left: the skeptic refuted it. |
| words-access | 9 | refuted | low | Agent names shown in the Claude Code transcript are 'auditor' and 'second-check' | Left: the skeptic refuted it. |
| words-access | 10 | confirmed | low | Evidence window offers 'Fix in Claude Code…' under 'Nothing to review' | Fixed: the evidence window shows no footer under "Nothing to review" |
| words-access | 11 | refuted | low | Plugin step flips to 'Connected' with no VoiceOver announcement | Left: the skeptic refuted it. |
| words-access | 12 | refuted | low | 'No skills used in the last 90 days' is stated as fact when the kept sessions don't reach back 90 days | Left: the skeptic refuted it. |
| words-access | 13 | refuted | low | The same thing is worded three ways across app, tool and skills | Left: the skeptic refuted it. |
| words-access | 14 | plausible | low | save-findings success line and the legacy script use retired words and promise a menu entry that may not exist | Fixed in the tool ("Saved 1 finding for 1 checked skill."); the legacy script's words are left, as the verifier judged |
| words-access | 15 | refuted | low | Plugin description says it reads what the Mac app found, but every command now works without the app | Left: the skeptic refuted it. |
| write-safety | 0 | refuted | high | Write gate only recognises the literal text "skill-health <fix\|update\|undo> apply"; other spellings of the same command reach the tool with no prompt summary, and none of it fires in bypass mode | Refuted. The gate was later redesigned anyway (second round): every run must name a live plan, so other spellings are denied with the form to use |
| write-safety | 1 | confirmed | medium | A plan's `summary` (what the approval prompt shows) is not tied to the `fix.after` / staged files that get written | Fixed: apply rebuilds the summary from what it writes and refuses a mismatch (fix, update, undo); updates are checked against Engine.sourceDelta; ToolTests.aPlanWhoseChangeNoLongerMatchesItsSummaryIsRefused |
| write-safety | 2 | refuted | medium | Approval prompt cuts the summary at 3,000 characters, but the write is not limited, so the tail of a long fix is written without being in the prompt | Left: the skeptic refuted it. |
| write-safety | 3 | confirmed | medium | Plan is marked used before the lock is taken, so a busy lock burns the plan and the messages are wrong ("Try again in a moment", then "already been written") | Fixed: a plan is marked used only after a write; gate.sh denies used, expired and wrong-kind plans; ToolTests.aBusyLockLeavesThePlanToRunAgain, PluginGateTests.aPlanThatIsUsedExpiredOrForAnotherCommandIsDenied |
| write-safety | 4 | confirmed | medium | Fix writes the skill, then records the decision; if the record fails the tool never says the skill changed, and there is no undo record | Fixed: Engine.patch and undoPatch put the file back when the record can't be saved; ToolTests.aFixThatCantBeRecordedPutsTheFileBack |
| write-safety | 5 | confirmed | medium | HiddenText misses common invisible characters, so they pass save-findings and `--with -` and show nothing in the preview or the approval prompt | Fixed: HiddenText and save-findings.sh cover controls, default-ignorables, format characters, Hangul fillers, the blank braille pattern and selector runs; SaveFindingsTests.theScriptAndTheAppAgreeOnHiddenCharacters (27 cases) |
| write-safety | 6 | confirmed | medium | undoUpdate does not check that the manifest's folder is inside the skills folder, so an undo can write anywhere | Fixed: undoUpdate requires the backup under backups/ and the folder under skills/; UndoUpdateTests.anUndoRefusesAManifestNamingAFolderOutsideTheSkillsFolder |
| write-safety | 7 | confirmed | low | A BOM'd skill file gets a preview that can never be applied, and the refusal blames "changed after the preview" | Fixed: SkillText.exact keeps a byte-order mark; ToolTests.aFileWithAByteOrderMarkIsFixedAndKeepsIt |
| write-safety | 8 | plausible | low | checkSources reads compare.json and updates.json before the network phase, outside the lock, then writes them from that stale copy | Fixed: checkSources keeps a copy listing that an update or undo wrote while it compared |
| write-safety | 9 | refuted | low | `skill-health issue` (no --open), pre-approved in the fix skill, overwrites the clipboard | Left: the skeptic refuted it. |
| write-safety | 10 | confirmed | low | `update apply` ends with "Nothing was updated." even when it printed that a skill was partly updated and couldn't be restored | Fixed: a partly updated skill ends with a failure naming it and the backups, not "Nothing was updated" |
| plugin-contract | 0 | confirmed | medium | Undoing a fix fails (after the person approves) once the skill has been checked again | Fixed: undo apply works from the decision record (Engine.undoPatch(finding:)); the skill comes from the folder holding the file; ToolTests.aFixCanBeUndoneAfterItsSkillIsCheckedAgain |
| plugin-contract | 1 | confirmed | medium | /skill-health:fix skips findings the tool reports as open, so expired set-asides and resurfaced fixes never get offered | Fixed: fix/SKILL.md no longer skips a finding with a lapsed decision, and says what lapsed |
| plugin-contract | 2 | confirmed | medium | An unreadable findings.json or decisions.json reads as "Nothing to fix" or "Nothing to undo", and a check can spend ~1M tokens before failing to save | Fixed with words-access #2; save-findings names an unreadable results file |
| plugin-contract | 3 | confirmed | medium | /skill-health:update tells people a locally edited skill "has a newer copy" when its source hasn't changed | Fixed with words-access #1 |
| plugin-contract | 4 | confirmed | low | Session note still says "Claude gets the corrections at the start of every session" when the person turned corrections_for_claude off | Fixed with words-access #0 |
| plugin-contract | 5 | plausible | low | /skill-health:check step 6 says the auditor already gives skillName, but the auditor never outputs it, and the tool's error doesn't name the missing key | Fixed: check/SKILL.md adds skillName; save-findings names a missing field; ToolTests.aMissingFieldInCheckResultsIsNamed |
| plugin-contract | 6 | confirmed | low | gate.sh denies any Bash command that merely mentions "skill-health fix\|update\|undo apply" | Fixed in the second round: a command with no live plan id gets no opinion; PluginGateTests.wordsThatNameNoPlanGetNoOpinion |
| plugin-contract | 7 | refuted | low | update/SKILL.md says the approval prompt "shows the change", but for updates it shows only skill and file names | Left: the skeptic refuted it. |
| plugin-contract | 8 | confirmed | low | /skill-health:undo option labels collide when a skill has two entries of the same kind | Fixed: undo entries name the line ("Line 10 of SKILL.md"); undo/SKILL.md makes every label differ |
| plugin-contract | 9 | confirmed | low | `skill-health version` omits the git commit the spec says it prints | Fixed: `skill-health version` prints the commit from bin/BUILT_FROM |
| app | 0 | confirmed | medium | Session note still says "Claude gets the corrections at the start of every session" after the person turns Corrections for Claude off | Fixed with words-access #0 |
| app | 1 | refuted | low | An undecodable settings.json turns the whole app into state C, "couldn't read your Claude folder", whose remedy cannot work | Left: the skeptic refuted it. |
| app | 2 | confirmed | low | In sample mode, the review notes' "Compare Now … python-env has a newer copy" cannot be seen anywhere in the app | Fixed: sample mode says "1 sample skill has a newer copy" in the menu and in Settings; review notes say where |

## Second round: verifying the fixes (2026-10-04, evening)

Seven agents tried to reopen each fix, using scratch copies only. Six reported; the hidden-characters verifier was cut off by a usage limit and is re-run with the final check. Their findings, and what was done:

| Area | Finding | Outcome |
|---|---|---|
| plan binding | [high] A plan file with a repeated "summary" key: jq shows the last, Swift decodes the first | Fixed: apply refuses a plan file that isn't byte for byte what the tool writes, or whose id isn't the one asked for |
| plan binding | The 3,000 limit counted in Characters by the tool, code points by the gate | Fixed: counted and cut in unicode scalars; the gate denies anything longer |
| plan binding | update apply trusted compare.json, so a forged plan plus forged compare.json wrote anything | Fixed: update apply checks every file against GitHub's own listing for the commit, and each change's kind and executable mode |
| plan binding | undo of an update trusted the manifest | Fixed: the manifest must name its own installed skill folder, kinds must agree with blobs, a folder path is refused, the summary's words come from blobs |
| plan binding | The diff compared lines by canonical equivalence (Kelvin sign for K) | Fixed: lines compared by unicode scalars |
| plan binding | fix apply didn't tie the plan to the finding or check it was open | Fixed: the finding must be open and the plan must be the file with exactly its quote replaced |
| plan binding | File names and repo names went into prompts raw | Fixed: revealed; a path part with a hidden character is refused |
| plan binding | A copied plan file could be applied under a second id | Fixed with the id check |
| plan binding | The gate didn't pin the program | Fixed: under CLAUDE_PLUGIN_ROOT the path must be the plugin's own tool |
| plan lifecycle | undo of an update reverted files, then failed on updates.json with no rollback | Fixed: the update's files go back and Skill Health says nothing changed |
| plan lifecycle | A swallowed failure to mark a plan used | Fixed: the plan is deleted instead, and stderr names it if that fails too |
| plan lifecycle | update apply said "/skill-health:undo puts a skill back" for a skill whose undo record wasn't saved | Fixed: attention line first, no undo line, non-zero exit |
| plan lifecycle | Rollback reported "partly updated" for a skill nothing was written to | Fixed: only files written or removed are restored |
| plan lifecycle | An unwritable folder read as "another Skill Health is saving" | Fixed: the real error is reported |
| plan lifecycle | A fix applied over a decision made after the preview | Fixed: the finding must still be open |
| gate | Mentions at a line start or after a quote were still denied | Fixed: a command with no live plan id gets no opinion |
| gate | Runs through a variable, a wrapper with flags, escaped spaces or a quoted apostrophe got no output | Fixed: any command naming a live plan with "apply" that isn't the canonical form is denied with the form to use; canonical paths with escapes and either quote are recognised |
| gate | A long run of braces made the regex quadratic | Fixed: the command-position regexes are gone; tested at 100 KB |
| gate | The no-jq fallback denied every mention | Fixed: it denies only a command naming a live plan |
| gate | Misleading reasons (trailing new line, $HOME paths) | Fixed: a trailing new line is trimmed; other spellings get the canonical form |
| tool words | An unreadable entry still printed an all-clear | Fixed |
| tool words | "Nothing to fix" while instructions were set aside | Fixed: set-aside counts in status and findings, and in /skill-health:fix's empty case |
| tool words | undo list said "Nothing to undo" with unreadable results | Fixed: it fails with the reason |
| tool words | save-findings silently dropped unreadable entries of other skills | Fixed: it refuses while any entry can't be read |
| tool words | keptAsItIs could never happen | Removed |
| tool words | upstream "removed" meant the file, not the skill | Fixed: fileRemoved and skillRemoved |
| tool words | A set-aside that came back because the source changed was called expired | Fixed: decision.lapsed says which |
| tool words | Undo labels still collided; decisions named no instruction | Fixed: each detail names the line or the instruction; lapsed set-asides aren't listed |
| tool words | Counts, zero-used text, refusal wording, the update preview quote, check's first message | Fixed |
| regressions | Any fix on a line longer than about 1,450 characters was refused | Fixed: long lines are shown cut around the change |
| regressions | A byte-order mark triggered the hidden-characters warning | Fixed: the warning is only for characters the change adds |
| regressions | Update preview dropped a leading byte-order mark | Fixed |
| app | A check opened from the menu hid an unreadable results file | Fixed: the unreadable header wins |
| app | Unreadable results were said nowhere with usage unreadable or in sample mode | Fixed: a group of its own there |
| app | Settings said "No skill you use has a newer copy" after an offline comparison | Fixed with the setup window rebuild: the line says what the comparison established |
| app | The review notes' "first line" was untrue in sample mode | Fixed |
| app | Decisions worded differently in app and tool | Fixed: one wording (ProblemText) |
| words | The rate-limit sentence promised "Skill Health will finish comparing then" with Compare daily off | Fixed: the sentence says what GitHub allows; the app and the tool each say what happens next |
| words | The privacy policy and README said only skill names, line ids and times are kept | Fixed: they now name the session file paths, sizes and dates the usage cache keeps |

## Third round: checking the merged work (2026-10-05)

Six agents were started on the merged branch (hidden characters, the gate, the write path, the tool's words, the window's logic, regressions). Five were stopped partway to save tokens, and one, the tool's words, finished. Its findings are below. In place of the others, the gate and the write path were attacked by hand. **The hidden-characters area, the window's logic and the regression read have not had a verification pass since the merge.**

By hand, against the merged tool and scripts, on scratch copies:

| Check | Result |
|---|---|
| Gate: canonical forms (bare, absolute, quoted, trailing new line, upper-case id) | ask; deny in bypass |
| Gate: variable, `env -u`, `sudo -E`, `nice -n`, `xargs`, `bash -c`, chains, quoted/split `apply`, quoted id, `$P`, `\apply`, `%33…`, another program path | all denied with a live plan |
| Gate: mentions with no live plan (commit message, echo, `git log --grep`) | no opinion |
| Gate: 100 KB of braces | 65 ms |
| Write path: a plan with a repeated `summary` key; `after` changed outside the quote; a plan copied under another id | all refused, nothing written |
| Write path: the honest preview then apply | writes once; a second apply is refused |

The tool-words verifier's findings:

| Finding | Outcome |
|---|---|
| medium: `update list` and `compare` said "None of the skills you use has a newer copy" when no skill has a recorded source | Fixed: says how many have a source, and "nothing to compare" when none |
| medium: a set-aside known correction in a never-checked skill read "hasn't been checked yet" with no mention of it | Fixed |
| low: `findings <skill>` sent an unused skill to `/skill-health:check`, which refuses it | Fixed |
| low: `undo list` order for equal times was random | Fixed: ties break by id |
| low: `undo list` didn't need the skills folder | Fixed |
| low: dates followed the Mac's locale, a future time read "in 5 hours", a shipped correction's date showed a day early | Fixed: English, "just now", date-only values shown as their UTC day |
| low: `plan --json` folder had a trailing slash | Fixed |
| low: spec said plan lists "then most loads" | Fixed |
| low: legacy "not for this project" decisions counted as set aside but not listed by undo | Fixed (fourth round): listed, to reopen |
| low: an unreadable update manifest or compare.json reads as "nothing to undo" / "never compared" | Fixed: both are said |
| low: `undo list` lists a fix whose backup was deleted | Fixed: not offered |
| low: `undo` labels can still tie for two same-day decisions | Fixed: undo/SKILL.md adds the detail's first words |
| low: skill names with hidden characters print raw in text output (previews reveal them) | Fixed |
| low: `compare` lists failing sources of skills you don't use; the rate-limit time is baked into the text | Fixed: only sources of skills you use; a stop an hour old says the limit has reset (tool and app) |
| low: `update/SKILL.md` points at Settings for Compare Now and says "once a day" unconditionally; `fix/SKILL.md` has set-aside-until-update wording the skill can't make | Fixed: /skill-health:update can compare after asking; the dead sentence is gone |
| low: `status --json` `findingsProblem` also carries decisions and usage problems | Fixed: one field per file |
| low: read-only commands write `usage-cache.json` | Fixed in the spec's writer table and check/SKILL.md (the cache is Skill Health's own file) |
| low: "No skills used in the last 90 days" said as fact when earlier use may be missing | Fixed: says since when; an unreadable sessions folder is a usage problem |
| low: the unreadable-decisions remedy ("move the file aside") discards undo records; one bad entry makes the whole file unreadable | Fixed in words: the remedy says what it costs, and the reason is in words. A bad entry still makes the file unreadable (nothing writes over it) |
| low: `save-findings` accepts skills that aren't installed and quotes that aren't in the file | Fixed: those are left out and named, the rest is saved |
| low: a missing or unreadable known-corrections file is dropped silently | Fixed: said, and no all-clear without them |

## Fourth round: the areas left unverified (2026-10-09)

| Area | Result |
|---|---|
| Hidden characters | Every Unicode code point that is a format character or default-ignorable is hidden (exhaustive check over 0–0x10FFFF, now a test). Script and app share the same ranges. |
| Setup window logic | Read against the critique. Kept as designed: launch at login reads the real status each time; the folder row shows Change… under Read Skills Again when usage can't be read. Comment on the disabled Compare button corrected (on macOS a disabled button leaves keyboard focus). |
| Accessibility tree (throwaway copy, sample mode) | Three headings (Claude Code, Newer copies, On this Mac), buttons labelled by their row, reading order as on screen. Switches were read twice (their texts and the switch); fixed. |
| Reopening | With the icon shown and hidden: closing the window and opening Skill Health again (Finder, Spotlight) brings the window back; Skill Health keeps running with no window. |
| Regression read of the merge | Not done as a separate pass. The tool's commands, the gate and the write path were each attacked or tested since the merge (third round and this one). |
