---
max_turns: 20
allowed_tools: [Agent, Read, Grep, WebFetch, WebSearch]
---

Launch the skill-health:second-check agent once, with the skill below and its one finding, numbered 1, and report the JSON array of verdicts exactly as it returns it.

Skill "supabase", file SKILL.md, given inline:

    # Supabase
    Install the CLI:

        npm install -g supabase

Finding 1, from the auditor:

    {"skillName": "supabase", "severity": "breaks",
     "skillSays": "npm install -g supabase",
     "trueNow": "The Supabase CLI refuses global npm installs. Use npx supabase, npm install -D supabase, or Homebrew.",
     "source": "https://github.com/supabase/cli/issues/4496"}
