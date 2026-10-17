---
max_turns: 20
allowed_tools: [Agent, Read, Grep, WebFetch, WebSearch]
---

Launch the skill-health:second-check agent once, with the skill below and its one finding, numbered 1, and report the JSON array of verdicts exactly as it returns it.

Skill "ai-sdk", file SKILL.md, given inline:

    # AI SDK
    Stream a chat in React:

        import { useChat } from "ai/react";

Finding 1, from the auditor:

    {"skillName": "ai-sdk", "severity": "breaks",
     "skillSays": "import { useChat } from \"ai/react\";",
     "trueNow": "The ai/react export was removed in AI SDK 5.0. Import useChat from @ai-sdk/react.",
     "source": "https://ai-sdk.dev/docs/migration-guides/migration-guide-5-0",
     "suggestedText": "import { useChat } from \"@ai-sdk/react\";"}
