# Notes for App Review

Paste into App Store Connect › App Review Information › Notes (the field holds 4,000 bytes; this is about 2,100).

---

Skill Health watches the instructions people give their AI coding agent. Agents such as Claude Code load "skills": plain folders of Markdown instructions in ~/.claude/skills. Those instructions go out of date: a command stops working, a flag is removed, a package is renamed. Skill Health shows which skills a person actually uses, which of those carry instructions known to fail or to be deprecated (with the evidence: what the skill says, what is true now, and a link), and which have a newer copy at the GitHub repository they came from.

The app works on its own (guideline 4.2.3): it reads the folder the person chooses, shows the results in its menu, and shows each finding's evidence in a read-only window. Fixing a skill is optional and happens in the person's own Claude Code, through a companion plugin they install there themselves with a command the app shows; the app installs nothing and runs no other program.

To try it without an AI agent: open Skill Health, and in the window that appears choose "Try with Sample Skills". Skill Health copies three small sample skills into its own container. Then:
- The menu bar icon (a document with a magnifying glass) opens the menu. Its first line says "These are sample skills", and under it "supabase-basics" opens that skill's page: what Skill Health knows about it and the evidence for its failing instruction.
- In Skill Health Settings, "Compare Now" compares the samples with their source on GitHub (github.com/mvoshell652/skill-health, folder samples/). Settings then says "1 sample skill has a newer copy" (python-env), and so does the menu, above Settings….

With their own folder, a person chooses ~/.claude once in an open panel (a security-scoped bookmark keeps it). The app reads that folder and writes only into ~/.claude/skill-health. It never changes a skill: the plugin does that inside Claude Code, after the person approves the write there (the prompt shows the exact change for a fix, and lists the files for an update).

Network: only after the person chooses Compare Now (and then once a day while the app is open, unless they turn that off), the app calls the GitHub REST API with the names of the repositories their skills came from and when they installed them. No account, analytics or tracking. Nothing else about the person, their files or their usage is sent.
