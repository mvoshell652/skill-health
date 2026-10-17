# Sample skills

The Skill Health app ships copies of these three skills as its sample library ("Try with Sample Skills"),
so it can be tried, including by App Review, without Claude Code. Their install records point here,
at `mvoshell652/skill-health`, so comparing them works like any other skill. Each was installed from the first version of its folder here;
`python-env` has a newer version in a later commit, which is what makes the app show a newer copy.

- `supabase-basics` carries one instruction that is no longer true (`supabase.auth.signIn`, which
  supabase-js v2 removed; it is `signInWithPassword` now), with a finding and a suggested fix, so every
  decision can be tried on a copy.
- `python-env` is changed here after the version the app ships, so it shows as having a newer copy.
- `git-hygiene` is current.

Don't edit the shipped versions without updating `Resources/SampleClaude` to match.
