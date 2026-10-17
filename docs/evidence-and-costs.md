# What Skill Health has found, and what a check costs

The numbers behind the README, with the dates they were measured on. They come from one person's skills so far (see the README's Limits).

## Why it exists

- **A copy that matches its repository can still be wrong.** On September 27, 2026, a first check looked at 12 skills for fast-moving software (Next.js, Supabase, Stripe, Cloud Run and others). Every file they got from their repository still matched it byte for byte, so an update would have changed nothing, yet 10 of the 12 had an instruction that fails or is deprecated. Most of those instructions were already wrong when the skill was first published.
- **Wrong instructions are common.** On October 9, 2026, a check of the 79 skills Skill Health's author had used by then found 104 failing and 36 deprecated instructions that held up against the second agent.
- **Even the most used skills have them.** `gcp-cloud-run`, the second most used skill on the author's Mac, tells Claude to push images to `gcr.io`. Container Registry stopped accepting new images on March 18, 2025; Google says `gcr.io` URLs hosted on Artifact Registry are not affected, so whether that push works depends on the project's Artifact Registry setup. `supabase`, the most used, tells Claude to use the `anon` and `service_role` keys, which Supabase is deprecating by the end of 2026.

## The claims, with their evidence

- **It checks against the software's own documentation.** Each instruction is checked against the current documentation of the software it's about, such as Supabase's, Google Cloud's or the AI SDK's. On October 9, 2026, the second agent threw out 15 of 155 findings. One was among Skill Health's own known corrections, which said `npm install -g supabase` fails; since Supabase CLI 2.99.0, it works.
- **Copies of skills already checked cost no tokens.** Known corrections ship with Skill Health and match your skills by their exact file contents, so a copy identical to one already checked shows its wrong instructions without a check. Security scanners share their verdicts the same way; Skill Health's say which instruction is wrong and what's true now. The author adds them after checking unedited copies of public skills. Today there are 89, for 62 checked copies of 61 skills from three collections: TerminalSkills/skills, aj-geddes/useful-ai-prompts and HoangNguyen0403/agent-skills-standard.

## What a check costs

A check runs on your own Claude plan, with no API key. Before anything runs, it asks which skills to check, up to six at a time, and shows what they will cost. Its agents run on Claude Sonnet. Claude Code reports about 80,000 tokens for a typical skill, which counts what the agents end up holding: across the 81 skills the author uses now, the median estimate was 82,000, and 9 in 10 were under 100,000. The agents process several times that, because each step re-reads everything opened before it, mostly from cache. In the October 9 check, the median skill's first agent alone processed about 260,000. A skill is left out if its files haven't changed since a check in the last 90 days, whether you ran that check or a known correction came from it. After 90 days it's due again, since documentation moves on even when a skill doesn't.
