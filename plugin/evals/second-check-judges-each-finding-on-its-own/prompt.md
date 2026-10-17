---
max_turns: 20
allowed_tools: [Agent, Read, Grep, WebFetch, WebSearch]
---

Launch the skill-health:second-check agent once, with the skill below and both of its findings, numbered 1 and 2, and report the JSON array of verdicts exactly as it returns it.

Skill "dev-setup", file SKILL.md, given inline:

    # Dev setup
    Stream a chat in React with `import { useChat } from "ai/react"`.
    Create a virtual environment with `python3 -m venv .venv`.

Finding 1, from the auditor:

    {"skillName": "dev-setup", "severity": "breaks",
     "skillSays": "Stream a chat in React with `import { useChat } from \"ai/react\"`",
     "trueNow": "The ai/react export was removed in AI SDK 5.0. Import useChat from @ai-sdk/react.",
     "source": "https://ai-sdk.dev/docs/migration-guides/migration-guide-5-0"}

Finding 2, from the auditor:

    {"skillName": "dev-setup", "severity": "deprecated",
     "skillSays": "Create a virtual environment with `python3 -m venv .venv`",
     "trueNow": "The venv module is deprecated; use the virtualenv package instead.",
     "source": "https://docs.python.org/3/library/venv.html"}
