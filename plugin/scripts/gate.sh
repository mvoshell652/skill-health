#!/bin/sh
# Skill Health's write gate: a PreToolUse hook on Bash. The only thing in the plugin that decides whether
# a skill gets written, so it is deliberately small and fails toward asking.
#
# A skill is changed by exactly three commands, each of which takes a plan the person has already
# seen previewed:
#   skill-health fix apply <plan-id>      skill-health update apply <plan-id>      skill-health undo apply <plan-id>
# No skill lists these in allowed-tools, so Claude Code would ask about them anyway. This hook makes
# that question show the change, and refuses the cases where a question would mean nothing.
#
# It does not parse the shell. It recognises one spelling, and treats every other spelling that names
# a live plan as a mistake to correct:
#   1. The whole command is "<tool> <fix|update|undo> apply <plan-id>" and nothing else (spaces around
#      it and one trailing new line are fine). The tool is the bare word skill-health or a path: a quoted
#      path, or one with backslash-escaped characters, is fine; a $ or a backtick is not. When
#      CLAUDE_PLUGIN_ROOT is set, a path must lead to $CLAUDE_PLUGIN_ROOT/bin/skill-health once both are
#      resolved, or the command isn't Skill Health's own tool. Then the plan decides, before any prompt:
#      missing, already written, for another command, more than 15 minutes old, or a summary longer
#      than 3,000 code points (the tool keeps its own to 3,000 characters): deny.
#      Prompts skipped (bypassPermissions, dontAsk): deny, so nothing writes unseen. Otherwise "ask",
#      with the plan's summary as the reason, which is what the person reads in Claude Code's prompt.
#   2. Any other command that contains "apply" and names a plan that exists in pending/ is some other
#      spelling of a run: a variable for the tool, env or sudo around it, a chain, a redirect, a
#      subshell. Deny, and give the one form that works, so the person approves the exact change.
#      Quotes, backslashes and new lines are dropped first, because they can split a word without
#      changing it.
#   3. Anything else gets no output and no opinion. A command that only mentions the words (a commit
#      message, a heredoc, a markdown code span, grep) names no plan that exists, so it is left alone.
# Without jq, or with input jq can't read, the command can't be taken apart, so one test is left: a
# command naming a plan that exists is denied, whatever else it says, and everything else gets no opinion.
#
# What this does not guarantee: a run that builds the plan id or the word apply while it runs
# (a variable, a substitution, a brace expansion, a decoded string) names no plan in the text, so
# it gets no opinion here. The tool's own checks still apply behind it: the plan must exist, be
# unused and unexpired, the file's bytes must be unchanged, and the summary is rebuilt from what is
# about to be written and must match the one the person was shown. Nor does the tool path check
# stop a bare "skill-health" that the shell finds on its own PATH.
#
# Always exits 0; the decision is in the JSON on stdout.
#   SKILL_HEALTH_DIR overrides ~/.claude/skill-health (tests).

dir="${SKILL_HEALTH_DIR:-$HOME/.claude/skill-health}"
unset CDPATH
input=$(cat)

uuid='[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}'

# The first UUID in $1 that has a plan file in pending/, as written or in the upper case the tool
# writes: sets live_id. grep and tr read once each, so a long command costs the same as a short one.
find_live_plan() {
  live_id=
  found=$(printf '%s' "$1" | LC_ALL=C grep -oE "$uuid" 2>/dev/null)
  [ -n "$found" ] || return 1
  upper=$(printf '%s' "$found" | LC_ALL=C tr 'a-f' 'A-F')
  for candidate in $found $upper; do # hex and dashes only, so splitting is safe
    if [ -f "$dir/pending/$candidate.json" ]; then
      live_id=$candidate
      return 0
    fi
  done
  return 1
}

if ! command -v jq >/dev/null 2>&1; then
  find_live_plan "$input" && printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Skill Health needs jq to show a change before it writes one, and jq isn'"'"'t installed. macOS 15 and later include it. Install jq, then run the command again."}}'
  exit 0
fi

decide() { # <allow|ask|deny> <reason>
  jq -n -c --arg decision "$1" --arg reason "$2" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: $decision, permissionDecisionReason: $reason}}'
}

# The one command that is an apply. Every piece is bounded by characters the shell treats as special,
# so nothing here can backtrack into itself.
# The tool, in one of three spellings, each captured without its quotes:
#   u  bare, or a path: any characters but the shell's own, or any character after a backslash
#   d  in double quotes: a path with spaces or an apostrophe in it, and \\ or \" for the other two
#   s  in single quotes: anything but a single quote, so a double quote is fine
tool_u='(?<u>(?:(?:[^\x00-\x20\x7f\x22\x27`;&|<>()$\\*?\[\]{}#!=^]|\\[^\n])*/)?skill-health)'
tool_d='\x22(?<d>(?:(?:[^\x22`$\\\n]|\\[\\\x22])*/)?skill-health)\x22'
tool_s='\x27(?<s>(?:[^\x27\n]*/)?skill-health)\x27'
strict="\\A[ \\t]*(?:$tool_u|$tool_d|$tool_s)[ \\t]+(?<kind>fix|update|undo)[ \\t]+apply[ \\t]+(?<id>$uuid)[ \\t]*\\z"

# Words on separate lines: skip, other, or canonical with mode, kind, id, which spelling and the tool
# as written. One trailing new line is dropped first. A command that isn't Bash is skipped.
verdict=$(printf '%s' "$input" | jq -r --arg strict "$strict" '
  (.tool_name // "") as $tool
  | (.tool_input.command // "") as $raw
  | (.permission_mode // "default") as $mode
  | if $tool != "Bash" or ($raw | type) != "string" then "skip"
    else
      ($raw | if endswith("\n") then .[:-1] else . end) as $cmd
      | (first($cmd | capture($strict)) // null) as $m
      | if $m == null then "other"
        else
          (if $m.u != null then ["u", $m.u] elif $m.d != null then ["d", $m.d] else ["s", $m.s] end) as $spelled
          | "canonical",
            (if $mode == "bypassPermissions" or $mode == "dontAsk" then "deny" else "ask" end),
            $m.kind, $m.id, $spelled[0], $spelled[1]
        end
    end' 2>/dev/null) || {
  find_live_plan "$input" && decide deny "Skill Health couldn't read this command, so it won't write a change. Run the apply command again, by itself."
  exit 0
}

result= mode= kind= id= form= program=
{
  IFS= read -r result
  IFS= read -r mode
  IFS= read -r kind
  IFS= read -r id
  IFS= read -r form
  IFS= read -r program
} <<EOF
$verdict
EOF

# A file path with its directory resolved through links, and its name; nothing if the directory isn't there.
resolve() {
  case $1 in
    */*) rdir=${1%/*} rname=${1##*/} ;;
    *) rdir=. rname=$1 ;;
  esac
  [ -n "$rdir" ] || rdir=/
  (cd -P -- "$rdir" 2>/dev/null && printf '%s/%s' "$(pwd -P)" "$rname")
}

# The plugin's tool as a word this gate accepts back, for the reason it gives: the full path, quoted
# the way that path needs; plain skill-health (a word the gate always accepts) when no quoting fits.
tool_word() {
  [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || { printf skill-health; return; }
  tool_path="${CLAUDE_PLUGIN_ROOT%/}/bin/skill-health"
  case $tool_path in
    *[!A-Za-z0-9_./+@%:,~-]*) ;;
    *) printf '%s' "$tool_path"; return ;;
  esac
  case $tool_path in
    *\'*) ;;
    *) printf "'%s'" "$tool_path"; return ;;
  esac
  case $tool_path in
    *[\"\`\$\\]*) printf skill-health ;;
    *) printf '"%s"' "$tool_path" ;;
  esac
}

case $result in
  canonical)
    # Where the tool is, as the shell would read it.
    case $form in
      u)
        literal=$(printf '%s' "$program" | LC_ALL=C sed 's/\\\(.\)/\1/g')
        case $program in "~/"*) [ -n "$HOME" ] && literal="$HOME/${literal#"~/"}" ;; esac
        ;;
      d) literal=$(printf '%s' "$program" | LC_ALL=C sed 's/\\\([\\"]\)/\1/g') ;;
      *) literal=$program ;;
    esac
    if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ "$literal" != skill-health ]; then
      have=$(resolve "$literal")
      want=$(resolve "${CLAUDE_PLUGIN_ROOT%/}/bin/skill-health")
      if [ -z "$have" ] || [ "$have" != "$want" ]; then
        decide deny "That isn't Skill Health's own tool. Run the apply command exactly as the preview printed it."
        exit 0
      fi
    fi
    # The plan's state, then its summary. An expiry that can't be read counts as passed.
    plan="$dir/pending/$id.json"
    [ -f "$plan" ] || plan="$dir/pending/$(printf '%s' "$id" | LC_ALL=C tr 'a-f' 'A-F').json"
    state=$(jq -r --arg kind "$kind" '
      if type != "object" or (.summary | type) != "string" or (.summary | length) == 0 then "missing"
      elif .used == true then "used"
      elif .kind != $kind then "kind"
      elif ((try (.expiresAt | fromdateiso8601) catch 0) <= now) then "expired"
      elif (.summary | length) > 3000 then "long"
      else "ready" end' "$plan" 2>/dev/null)
    case $state in
      ready) ;;
      used) decide deny "That change has already been written."; exit 0 ;;
      expired) decide deny "That change was prepared more than 15 minutes ago. Run the preview again, so what's written is what you see now."; exit 0 ;;
      kind) decide deny "That plan isn't for skill-health $kind apply. Run the preview again, then apply with the plan id it prints."; exit 0 ;;
      long) decide deny "That change is too long to show in full here, so it can't be approved. Run the preview again."; exit 0 ;;
      *) decide deny "That change isn't ready any more. Run the preview again."; exit 0 ;;
    esac
    if [ "$mode" = deny ]; then
      decide deny "Skill Health doesn't write a skill while permission prompts are skipped. Switch to a mode that asks (Shift+Tab), then run the command again."
      exit 0
    fi
    summary=$(jq -r '.summary' "$plan" 2>/dev/null)
    if [ -z "$summary" ]; then
      decide deny "That change isn't ready any more. Run the preview again."
      exit 0
    fi
    decide ask "$(printf 'Skill Health will write this change.\n\n%s' "$summary")"
    ;;

  other)
    # Quotes, backslashes and new lines can split a word without changing it (ap''ply, 3F25\04E0,
    # ap\ then a new line, then ply), so look for the word and the plan id with them taken out.
    words=$(printf '%s' "$input" | jq -j '(.tool_input.command // "") | if type == "string" then . else "" end' 2>/dev/null | LC_ALL=C tr -d '\042\047\134\012')
    case $words in *apply*) ;; *) exit 0 ;; esac
    find_live_plan "$words" || exit 0
    plan_kind=$(jq -r '.kind // ""' "$dir/pending/$live_id.json" 2>/dev/null)
    case $plan_kind in fix|update|undo) ;; *) plan_kind='<fix|update|undo>' ;; esac
    decide deny "Skill Health writes a change only from its own apply command, run by itself: $(tool_word) $plan_kind apply $live_id. Run it that way."
    ;;
esac
exit 0
