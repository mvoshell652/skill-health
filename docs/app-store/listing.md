# App Store listing (draft)

Apple 2.3.7 and 4.1, and Anthropic's naming rules: no other company's or product's name in the app name, subtitle, keywords or icon. Plain description text may say what Skill Health works with.

- **Name** (30 characters max): Skill Health. Check in App Store Connect whether the name is free, reserve it early, and keep a second name ready (for example "Skill Health for Agent Skills", 29 characters).
- **Subtitle** (30 max): Keep your agent skills correct
- **Category**: Developer Tools
- **Keywords** (100 bytes max, no other products' names): skills,agent,instructions,markdown,outdated,update,diff,docs,coding,ai,developer
- **Promotional text**: See which of your agent's skills give instructions that no longer work, with the evidence, and fix them in Claude Code after seeing the exact change.
- **Description**:

  Your AI coding agent follows the instructions in its skills. When a command stops working or a package moves on, a skill keeps telling the agent to do the old thing.

  Skill Health watches the skills you actually use. It shows which carry instructions that fail or are deprecated against the tools' current documentation, each with its evidence: what the skill says, what's true now, and a link. It knows instructions already found wrong in widely used skills, and it tells you when the repository a skill came from has a newer copy, while saying plainly that a newer copy isn't a correct one.

  When you want to fix something, Skill Health's companion plugin does it in Claude Code: check more skills on your own plan, fix a line, set a finding aside, draft an issue for the author, or update a skill from its source. Nothing is written until you approve it in Claude Code's own permission prompt, which shows the exact change for a fix and lists the files for an update, and every change can be undone.

  Private by design: Skill Health reads the folder you choose, sends GitHub only the names of your skills' repositories and when you installed them when you ask it to compare (then once a day while the app is open, unless you turn that off), and collects nothing.

  Skill Health is an independent app, not affiliated with or endorsed by Anthropic.
- **Privacy** (App Store Connect › App Privacy): Data Not Collected.
- **Screenshots**: take them in the sample library (Try with Sample Skills): the menu, a skill's evidence window, and Skill Health Settings after Compare Now.
