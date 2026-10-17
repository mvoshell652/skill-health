# Security

Skill Health can change the files in `~/.claude/skills`, and every skill a person uses is an instruction their coding agent follows. So its safety promises are the point of the project:

- Skill Health writes a skill only through the plugin's tool, `plugin/bin/skill-health`: a preview makes a plan, and an apply writes exactly that plan. The tool applies only a plan that exists, is unused and under 15 minutes old, whose file bytes are unchanged, and it rebuilds the summary from what it is about to write and refuses if that differs from the plan's. When Claude Code asks about the apply, the prompt shows the exact change for a fix; for an update it lists the files (a very long list is cut at 3,000 characters, and the prompt says so), and the text of each change is in the preview above it. When nobody can be asked (`bypassPermissions`, `dontAsk`), the write gate refuses the apply command, within the limits below.
- The tool is a prebuilt universal binary, ad hoc signed and not notarized, committed to this repository because Claude Code installs a plugin by copying its folder. [CONTRIBUTING.md](CONTRIBUTING.md) says how to check it against its source with `Scripts/verify_plugin_bin.sh`. That check shows the binary matches the source, not that the source is safe: read it.
- The Mac app never changes a skill. It writes only into `~/.claude/skill-health`. So does the plugin's background work at the start of a session, which reads your session files and the skills you use, matches the known corrections and changes no skill.
- Skill Health's own code sends only the names of the GitHub repositories your skills came from, and when you installed them, to GitHub's API after you choose Compare Now (and then once a day while the app is open, unless you turn that off), and downloads the files an update needs from those repositories. If you choose to open a drafted issue, its text goes in the address of GitHub's new-issue page in your browser, and nothing is posted unless you submit it there. A check runs in Claude Code on your plan, so the skill text it reads goes to Claude as in any session, and its agents fetch public documentation pages.
- Text from a skill, a web page or a repository is treated as data: never as an instruction to the plugin's agents, and never as a command for the tool to run.

That last point is a mitigation, not a guarantee. A language model reading hostile text can still be steered by it, and no prompt rules that out. This is how Claude Code's [permission modes](https://code.claude.com/docs/en/permission-modes) treat a skill write:

- Default, `acceptEdits` and `plan`: Claude Code asks. For the apply command the gate makes the question show the change; for a command the gate misses, the question shows the raw command.
- `auto`: the gate's question for the apply command still reaches you. A command the gate misses, or a direct edit of a skill file, is decided by Claude Code's classifier, not by you.
- `bypassPermissions`: nothing asks. The gate refuses the apply command, and Claude can edit a skill file directly.
- `dontAsk`: anything not pre-approved is denied. The gate refuses the apply command with a clear message.

If you want a person, not a model, to approve every change, use the default mode.

What the write gate does and doesn't do:

- It refuses the apply command in `bypassPermissions` and `dontAsk`, and in every mode refuses any other spelling that contains the word `apply` and the id of a plan that exists, so the one form that shows you the change is the one that works.
- It reads the command's text; it doesn't parse the shell. A command that builds the word `apply` or the plan id while it runs names no plan in its text, so the gate has no opinion on it, and the mode's rules above apply to the raw command. This is a known limit, not a vulnerability to report.
- Whatever reaches the tool still has to pass the tool's own checks, so a write is always exactly the change in a plan the tool accepts, never something else. Those checks aren't an approval, and they don't prove a preview was shown: they can't know who made the plan or who ran the command.
- In `bypassPermissions`, and in `auto` when its classifier allows it, Claude can also edit a skill file directly with its own tools, with or without Skill Health.

A check can be misled into a wrong finding. The agents that check skills have no tool that writes.

## Report a problem privately

If you find a way around any of these, please don't open a public issue. Use GitHub's private reporting instead: the **Security** tab of this repository, then **Report a vulnerability**. If you can't see that button, open an issue that says only that you have a security report, with no details, and a private channel will be arranged.

Useful to include: what you did, what was written, sent or run that shouldn't have been, and the versions: `plugin/bin/skill-health version` for the plugin, and Get Info on `SkillHealth.app` in Finder for the app.

Examples of what counts:

- A change applied that differs from what the permission prompt showed, or an apply of the recognised form that runs with no prompt in default, `acceptEdits`, `plan` or `auto` mode.
- A plan file, a finding or a skill file crafted so the tool writes outside the skill it names.
- Hidden or look-alike characters that make the prompt read one way and the write do another.
- A skill's text or a fetched page that makes a check's agents act on it, or changes what gets saved.
- The app or the plugin's tool writing a skill outside an approved apply, or sending anything beyond what the list above says.

## Versions

Fixes go into `main`, and into the next plugin version (`plugin/.claude-plugin/plugin.json`), which is tagged `vX.Y.Z`. If you follow `main` (the default), run `claude plugin update skill-health@skill-health` to get it. If you pinned a release, that command can't move you and will say you are already on the latest version: run `claude plugin marketplace remove skill-health`, then `claude plugin marketplace add 'mvoshell652/skill-health#<new tag>' && claude plugin install skill-health@skill-health`. New versions are listed on the repository's Releases page.
