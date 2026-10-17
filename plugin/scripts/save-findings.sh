#!/bin/sh
# Saves an audit's findings for the Skill Health Mac app: the only way audit results reach it.
#   sh save-findings.sh <results.json>      (or - to read standard input)
# results.json, written by /skill-health:check (which now saves through `skill-health save-findings -`; this script
# stays for one release for plugins older than 0.4.0):
#   {"audited": ["skill", ...],
#    "findings": [{"skillName", "severity", "skillSays", "trueNow", "source", "wrongSince"?,
#                  "file"?, "suggestedText"?, "alternative"?, "keptBySecondCheck": true}, ...]}
# Everything is checked before anything is written, and the write is atomic. Names and severities
# match exactly (jq's inside would accept substrings: "break", or "supa" for "supabase"). A finding's id comes
# from its skill, file and quote, so the same wrong line keeps its id across audits and the
# person's decision about it carries over. Findings for skills this audit covered replace that
# skill's old ones; every other skill's findings are kept. Sources/SkillHealthCore/Audit/AuditResults.swift
# applies the same rules for checks run in the app; change both together.

set -u
fail() { echo "skill-health: $*" >&2; exit 1; }
[ $# -eq 1 ] || fail "usage: save-findings.sh <results.json>, or - to read standard input"
command -v jq >/dev/null 2>&1 || fail "jq is needed (macOS includes it from macOS 15)."
dir="${SKILL_HEALTH_DIR:-$HOME/.claude/skill-health}"
[ -d "$dir" ] || fail "$dir doesn't exist. This script is the old way to save a check; skill-health save-findings - makes the folder and saves."
if [ "$1" = "-" ]; then
  # The audit hands results over on standard input, so it never writes a file itself.
  input="$dir/.audit-results.$$"
  trap 'rm -f "$input"' EXIT
  cat > "$input"
else
  [ -r "$1" ] || fail "can't read $1"
  input="$1"
fi

# Characters that change what Claude reads without showing, the same rule as HiddenText.swift:
# control characters other than tab and line ends, and a carriage return that doesn't end a line;
# default-ignorable and format characters (zero-width, direction overrides, invisible operators,
# the byte-order mark, Hangul fillers, tag characters); the blank braille pattern; and a
# variation selector with no character of its own before it (a run of them can carry a message).
always='\x{0}-\x{8}\x{B}\x{C}\x{E}-\x{1F}\x{7F}-\x{9F}\x{AD}\x{34F}\x{600}-\x{605}\x{61C}\x{6DD}\x{70F}\x{890}\x{891}\x{8E2}\x{115F}\x{1160}\x{17B4}\x{17B5}\x{180B}-\x{180F}\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2060}-\x{206F}\x{2800}\x{3164}\x{FEFF}\x{FFA0}\x{FFF0}-\x{FFFB}\x{110BD}\x{110CD}\x{13430}-\x{1343F}\x{1BCA0}-\x{1BCA3}\x{1D173}-\x{1D17A}\x{E0000}-\x{E00FF}\x{E01F0}-\x{E0FFF}'
selectors='\x{FE00}-\x{FE0F}\x{E0100}-\x{E01EF}'
hidden="[$always]|\r(?!\n)|(?:\A|[\s$selectors$always])[$selectors]"

# The shape, field by field. Anything else is refused with the rule broken, in the words
# AuditResults.problem uses (SaveFindingsTests compares the two), keeping the JSON field's name.
notname="isn't a skill name (letters, digits, ., _ and -, starting with a letter or digit)"
hiddenwhy="holds characters that don't show on screen"
notin="isn't in audited"
problem=$(jq -r --arg hidden "$hidden" --arg notname "$notname" --arg hiddenwhy "$hiddenwhy" --arg notin "$notin" '
  def name: type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$");
  def hidden: test($hidden);
  # Why a text field can'"'"'t be saved, or null. $limit is how the maximum is written for people.
  def why($label; $max; $limit):
    if type != "string" then "\($label) must be text"
    elif length == 0 then "\($label) is empty"
    elif length > $max then "\($label) is over \($limit) characters"
    elif hidden then "\($label) \($hiddenwhy)"
    else null end;
  # A date that exists: one unreadable date would make every finding unreadable to the app.
  def realdate: (try (strptime("%Y-%m-%d") | mktime | strftime("%Y-%m-%d")) catch "") == .;
  # One finding'"'"'s first problem, or null.
  def problem($audited):
    [ (if (.skillName | name | not) then "skillName \($notname)" else null end),
      (if (.skillName as $n | any($audited[]; . == $n) | not) then "skillName \(.skillName) \($notin)" else null end),
      (if (.severity | IN("breaks", "deprecated", "oldVersion", "cosmetic") | not) then "severity must be breaks, deprecated, oldVersion or cosmetic" else null end),
      (.skillSays | why("skillSays"; 2000; "2,000")),
      (.trueNow | why("trueNow"; 2000; "2,000")),
      (if ((.source | type) != "string") or (.source | test("^https://[^\\s]{4,500}$") | not) then "source must be an https link" else null end),
      (if .keptBySecondCheck != true then "keptBySecondCheck must be true: only findings the second look kept are saved" else null end),
      (if has("file") and .file != null
       then (.file | why("file"; 300; "300")) // (if (.file | test("(^/)|(^|/)\\.\\.?(/|$)")) then "file must stay inside the skill folder: no leading / and no . or .. parts" else null end)
       else null end),
      (if has("suggestedText") and .suggestedText != null then (.suggestedText | why("suggestedText"; 2000; "2,000")) else null end),
      (if has("alternative") and .alternative != null and (.alternative | name | not) then "alternative \($notname)" else null end),
      (if has("wrongSince") and .wrongSince != null and (.wrongSince | (type == "string" and (. == "undated" or (test("^(written|installed|since):[0-9]{4}-[0-9]{2}-[0-9]{2}$") and (.[-10:] | realdate)))) | not) then "wrongSince must be undated, written:YYYY-MM-DD, installed:YYYY-MM-DD or since:YYYY-MM-DD" else null end)
    ] | map(select(. != null)) | first;
  if (type != "object") then "the results must be a JSON object with audited and findings"
  elif ((.audited | type) != "array") then "audited must be a list of the skill names checked"
  elif (.audited | length) == 0 then "audited is empty: it must list the skill names checked"
  elif (.audited | all(name) | not) then "audited has a name that \($notname)"
  elif ((.findings | type) != "array") then "findings must be a list of the kept findings"
  else
    (.audited) as $audited
    | [.findings | to_entries[] | .key as $i | .value
       | if (type != "object") then "finding \($i) must be an object"
         else (problem($audited)) as $p | if $p == null then empty else "finding \($i): \($p)" end end]
    | first // ""
  end' "$input" 2>&1) || fail "nothing saved: the results aren't valid JSON ($problem)"
[ -z "$problem" ] || fail "nothing saved: $problem"

# Stable ids: SHA-1 of skill, file and quote, shaped like a UUID.
ids=$(jq -c '.findings[] | [.skillName, (.file // "SKILL.md"), .skillSays]' "$input" | while IFS= read -r key; do
  h=$(printf '%s' "$key" | shasum -a 1 | cut -c1-32)
  printf '"%s-%s-5%s-a%s-%s"\n' "$(echo "$h" | cut -c1-8)" "$(echo "$h" | cut -c9-12)" "$(echo "$h" | cut -c14-16)" "$(echo "$h" | cut -c18-20)" "$(echo "$h" | cut -c21-32)" | tr 'a-f' 'A-F'
done | jq -s -c '.')
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
existing="$dir/findings.json"
previous='{"version":1,"findings":[],"audited":{}}'
if [ -s "$existing" ]; then
  previous=$(jq -c 'if (.findings | type) == "array" then . else error("not Skill Health findings") end' "$existing" 2>/dev/null) \
    || fail "$existing isn't readable as Skill Health's findings; nothing was changed. Move it aside and run /skill-health:check again."
fi

tmp="$dir/.findings.json.$$"
jq --argjson previous "$previous" --argjson ids "$ids" --arg now "$now" '
  def since: if . == null or . == "undated" then {undated: {}}
    elif startswith("written:") then {written: {on: (.[8:] + "T00:00:00Z")}}
    elif startswith("installed:") then {installed: {on: (.[10:] + "T00:00:00Z")}}
    else {since: {date: (.[6:] + "T00:00:00Z")}} end;
  .audited as $audited
  | [.findings | to_entries[] | .value + {id: $ids[.key], foundOn: $now, wrongSince: (.value.wrongSince | since)}
     | {id, skillName, severity, skillSays, trueNow, source, foundOn, wrongSince, keptBySecondCheck}
       + (if .file then {file} else {} end) + (if .suggestedText then {suggestedText} else {} end)
       + (if .alternative then {alternative} else {} end)]
    # The same line reported twice is one finding.
    | (reduce .[] as $f ([]; if any(.[]; .id == $f.id) then . else . + [$f] end)) as $new
  | {version: 1,
     findings: ([$previous.findings[] | select(.skillName as $n | any($audited[]; . == $n) | not)] + $new),
     audited: (($previous.audited // {}) + ([$audited[] | {(.): $now}] | add))}
' "$input" > "$tmp" && mv "$tmp" "$existing" || { rm -f "$tmp"; fail "couldn't write $existing; nothing was changed."; }

# What was kept: the same line reported twice is one finding, a skill listed twice one skill.
count=$(printf '%s' "$ids" | jq 'unique | length')
skills=$(jq '.audited | unique | length' "$input")
echo "skill-health: saved $count finding(s) for $skills audited skill(s). This is the old way to save a check: skill-health save-findings - also updates what Claude gets at the start of a session."
