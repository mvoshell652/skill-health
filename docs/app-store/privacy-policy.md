# Skill Health privacy policy

Last updated: 16 October 2026

Skill Health is a Mac app and a Claude Code plugin that help you keep the instructions in your AI agent's skills correct.

**What the app reads.** The folder you choose (usually ~/.claude), and only after you choose it: the skills in it, Skill Health's own files in ~/.claude/skill-health, and, to count which skills you use, your agent's session files. From those it keeps skill names, line identifiers and times, and, so that it doesn't read a session file twice, each session file's path, size and date (a path names the project folder the session ran in). All of this stays on your Mac.

**What the app sends.** To GitHub, and only after you choose Compare Now the first time: the names of the repositories your skills were installed from, and when you installed them (to find the version you have), to api.github.com, to see whether they have newer copies. After that first time it compares once a day while the app is open, unless you turn Compare daily off. Nothing else about you, your files or your usage. No account needed. The app sends nothing anywhere else.

**What the plugin does.** The Skill Health plugin runs inside Claude Code, on your Mac, under your own Claude account and its terms. It needs no app. About once a day, at the start of a Claude Code session, it starts a background process that works out what to tell Claude: it reads your agent's session files (to count which skills you use), the skills in ~/.claude/skills and Skill Health's own files, matches the known corrections, and writes the result into ~/.claude/skill-health. As the app does, it keeps skill names, line identifiers and times there, and each session file's path, size and date (a path names the project folder the session ran in). That sends nothing and changes no skill. The two options under /plugin configure skill-health, the session note and the corrections for Claude, stop it only when both are off. When you run its commands:

- /skill-health:check has Claude read the skills you choose and look up current documentation, after it says which skills and what it costs.
- /skill-health:update, like the app's Compare Now, sends GitHub the names of the repositories your skills were installed from, and when you installed them (to api.github.com), to see whether they have newer copies. It then downloads the newer public files (raw.githubusercontent.com) and checks each against the id GitHub lists.
- /skill-health:fix can open GitHub's new-issue page in your browser with a draft filled in. Nothing is posted unless you submit it there.

**What Skill Health writes.** Its own files in ~/.claude/skill-health. A skill's files only through the plugin, after you approve the write in Claude Code's own permission prompt (for a fix the prompt shows the exact change; for an update it lists the files, and says so if a very long list is cut short, and the text of each change is in the preview above it); the files it replaces are kept in ~/.claude/skill-health/backups, and /skill-health:undo puts them back. Uninstalling the plugin leaves ~/.claude/skill-health; delete that folder to remove what the plugin stored. /skill-health:check, if you choose to check the skills for this project, has Claude read that project's dependency list (package.json and similar). A drafted issue's text is put on the clipboard when it is too long for a link.

**What Skill Health collects.** Nothing. There are no analytics, no tracking, no advertising identifiers, and no data sent to the developer.

**Known corrections.** Skill Health includes a list of instructions already found wrong in public skills, matched against your skills by exact file contents on your Mac. Matching sends nothing.

Questions: open an issue at github.com/mvoshell652/skill-health.
