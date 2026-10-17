# Copy for the plugin's commands (reviewed with writing-for-interfaces, 2026-10-04)

From the menu-and-copy critique of the plugin-driven redesign. The build spec is 2026-10-04_plugin_driven_redesign.md;
where they differ (the tool's command names, the word list's "second look"), the spec wins.

```
COMMAND: /skill-health:check
description: Check the skills you use for instructions that no longer work. Asks what to check and what it costs before anything runs. Changes no skill.
argument-hint: [skill name]
First message: "5 of 79 skills you use are checked; the oldest check was Sep 26. A check covers up to 6 skills, about 1.1 million tokens. Run it again for the next 6."
Question 1 (header "Check"): "Which skills should Skill Health check?"
  - "{name}" (first, only when the argument names a skill you use): "Loaded 212 times in 90 days. Never checked." / "Last checked Sep 26."
  - "6 you use most, not checked yet": "supabase, vite, tailwindcss and 3 more."  (when all are checked: "6 checked longest ago": "Oldest: Sep 26.")
  - "Skills for this project": "react, vite and 1 more, from package.json."  (left out when nothing matches)
  - "One skill": "You type its name next."
Question 2: preface "This uses your Claude plan. The estimate is from a measured check and could be 30% either way. It reads each skill and public documentation, and changes no skill." Then "Check 6 skills for about 1.1 million tokens?"  Options: "Check 6 Skills" / "Not Now". One skill: "Check 1 skill for about 180,000 tokens?" / "Check 1 Skill".
Not now or no answer: "Nothing ran. /skill-health:check asks again any time."
Progress: "Checking supabase, 2 of 6."
One skill failed: "vite couldn't be checked, so it stays as it was."
Result: "Checked 6 skills. 3 failing instructions and 4 deprecated were kept after a second look tried to disprove each one. The second look dropped 2. Run /skill-health:fix to go through them." Zero: "Checked 6 skills. No failing or deprecated instructions. The second look dropped 0." One: "Checked 1 skill. 1 failing instruction was kept after a second look tried to disprove it. The second look dropped 0."
Skill Health hasn't run: "Skill Health hasn't read your skills yet. Open Skill Health, choose your Claude folder, then run /skill-health:check again."

COMMAND: /skill-health:fix
description: Go through the failing and deprecated instructions in the skills you use, one at a time. Shows the exact change before anything is written.
argument-hint: [skill name]
Opening: "3 failing instructions and 4 deprecated in 4 skills you use. Starting with gcp-cloud-run." With an argument: "gcp-cloud-run has 1 failing instruction and 2 deprecated." Esc: "Esc stops here. Nothing you haven't approved is written."
Each instruction: "gcp-cloud-run · 1 of 3 · failing" / "The skill says: "…"" / "True now: …" / "Evidence: https://…"
Question (header "This line"): "What should happen to this instruction?"
  1. "Fix This Line": "Shows the exact change first. The current file is copied to backups before anything is written."  (no suggested text: "Write a Fix": "Claude proposes the new line and shows it first.")
  2. "Set Aside": "Come back to it later. You choose 30 or 90 days next."
  3. "Draft an Issue": "Writes an issue for the skill's author. You read it first, and nothing is posted unless you submit it on GitHub."
  4. "Use Another Skill": "Pick an installed skill that covers this. This skill stays as it is."
Follow-ups
  Set Aside: "How long should it stay aside?" -> "30 Days" / "90 Days". Then: "Set aside until Nov 3, or until its source changes this skill, whichever comes first."
  Fix This Line: show "Change to ~/.claude/skills/supabase/SKILL.md" and the diff, then "Write this change to supabase?" -> "Write Change": "supabase then counts as changed on this Mac, so updates leave it alone. /skill-health:undo puts the old file back." / "Don't Write": "Nothing changes."  Line under the diff: "Claude Code may ask you to approve the write as well."  After: "Written to supabase. Claude reads the new line the next time the skill loads. The old file is in ~/.claude/skill-health/backups."
  Draft an Issue: after the draft, "Open the new-issue page on GitHub with this filled in?" -> "Open GitHub" / "Not Now". After: "GitHub's new-issue page is open with the issue filled in. Nothing is posted until you submit it there."
  Use Another Skill: "Which skill covers this instead?" (suggested one first, or type a name). After: "Using vercel-deploy instead. The finding closes, and gcp-cloud-run stays as it is."
Between: "Next: supabase, 1 of 2."
End: "Done. Fixed 2, set aside 1, drafted 1 issue. 3 are left; /skill-health:fix picks up where you stopped." (zero/one/many on each count; omit a zero)
Nothing to fix: "Nothing to fix. None of the 5 skills you use that are checked has a failing or deprecated instruction. 74 haven't been checked: /skill-health:check."

COMMAND: /skill-health:update
description: Update the skills you use that have a newer copy at their source. Shows every changed file and asks once. An update doesn't fix instructions.
Opening: "23 skills you use have a newer copy at their source. An update brings a skill up to date with its source. It doesn't fix instructions, because a newer copy can be wrong too. Skill Health last compared with GitHub 3 hours ago."
List: one line per skill, "supabase: 3 files change, 1 is new", then every changed file name under it.
Left out: "2 more have a newer copy but changed on this Mac, so they're left out: ui-notes, my-deploy. Updating would write over your changes."
Question: "Update 23 skills?" -> "Update 23 Skills": "Each file is downloaded from its source and checked against the id GitHub lists. Current files are copied to backups first." / "Leave Some Out": "You type the names next." / "Not Now": "Nothing changes."
After: "Updated 23 skills. The old copies are in ~/.claude/skill-health/backups, and /skill-health:undo puts a skill back."
Nothing: "Nothing to update. None of the skills you use has a newer copy that's safe to take. Skill Health last compared with GitHub 3 hours ago."
Stale (over a day): "Skill Health last compared with GitHub 4 days ago, so this list may be out of date. Skill Health compares once a day while it's running."

COMMAND: /skill-health:undo
description: Put back the last fix or update of a skill from its backup.
argument-hint: [skill name]
Question (header "Undo"): "Put back which?" Options, most recent first, up to 4: "supabase": "Fixed Oct 4. 1 line." / "vite": "Updated Sep 30. 4 files." Another name can be typed.
Confirm: "Put back supabase?" -> "Put Back": "Its file returns to how it was before Oct 4. The fix is undone and the instruction opens again." / "Cancel": "Nothing changes."
Done: "supabase is back to how it was before Oct 4."
Changed since: "supabase has changed since this fix, so putting back the old file would lose those changes. Nothing was changed."
Nothing: "Nothing to undo. No fix or update has been made, or its backup is gone."

WORD LIST
check = for accuracy against current documentation (the daily comparison with sources is "compared", never "checked") · second look = the pass that tries to disprove a finding (never "second check", "second pass") · instruction = what a skill tells Claude · failing = Breaks only · deprecated = Deprecated · fix = change a line of a skill · update / newer copy = bring a skill up to its source (never "fix") · skills you use = loaded in the last 90 days · set aside · Draft an Issue (never "Tell the Author") · evidence = a finding's link · source = the repository a skill came from · Claude = the model, Claude Code = the app · Skill Health stays lowercase.
```
