---
max_turns: 20
allowed_tools: [Agent, Read, Grep, WebFetch, WebSearch]
---

Launch the skill-health:second-check agent once, with the skill below and its one finding, numbered 1, and report the JSON array of verdicts exactly as it returns it.

Skill "github-cli", file SKILL.md, given inline:

    # GitHub CLI
    Install on macOS with `brew install gh`, then run `gh auth login`.

Finding 1, from the auditor:

    {"skillName": "github-cli", "severity": "breaks",
     "skillSays": "Install on macOS with `brew install gh`",
     "trueNow": "GitHub CLI is no longer distributed through Homebrew; install the signed .pkg from the website.",
     "source": "https://cli.github.com/", "suggestedText": "Install on macOS from the .pkg at https://cli.github.com/"}
