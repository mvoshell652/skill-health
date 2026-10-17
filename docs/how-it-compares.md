# How Skill Health compares

What each tool tells you, and what Skill Health adds. The README keeps the short version.

| If you use | It tells you | Skill Health adds |
|---|---|---|
| `gh skill update`, `npx skills update` | Whether the skill's repository has a newer copy | Which instructions in your copy are wrong, and for skills installed with openskills, updates that never write over your edits |
| Claude Code's `/skill-doctor` | How often each skill is used, which never are, and how much of Claude's context each one takes up | Which instructions in the skills you do use are wrong |
| Claude Code's `/doctor prompt-audit` | Instructions written for older Claude models or retired Claude API features, files and commands missing from your project, and instructions that contradict each other, with proposed edits | Each instruction checked against the documentation of the software it's about, not only Claude's |
| [`skills-check`](https://github.com/voodootikigod/skills-check) | Whether the package version a skill declares in its frontmatter is older than the latest on npm, package names that don't exist, links that don't answer, and, with your API key, a rewrite of the skill by an AI model from the changelog | Each instruction checked against current documentation, whether or not the skill declares a version, with a source and a second agent on each finding |
| A skill-audit skill such as skill-stocktake, or asking Claude to review a skill | A verdict on each skill (keep, improve, update, retire or merge), which includes checking its technical references against the web, or a review of the one you ask about, when you run it | Each instruction checked against the documentation of the software it's about, known corrections for identical copies, and corrections Claude gets in every session |
| Context7, or letting Claude look up current docs as it works | Current documentation, looked up when a question calls for it | The wrong instructions in the skills Claude follows, found before it follows them |
