#!/bin/sh
# Skill Health's SessionStart hook. It prints one of two files, already in the hook's JSON format, that
# the plugin's tool (`skill-health refresh`) and the Skill Health Mac app both write, with the same code.
#   hook-note.json   the line for the person, plus any corrections for Claude
#   hook-quiet.json  the corrections alone
# When neither file's maker has run for a day, and there is a skills folder to look at, it starts
# `skill-health refresh` in the background and does not wait for it, so the plugin works without the
# app: this session prints what is there, and the next one prints what the refresh found. The refresh
# reads which skills you use from Claude Code's session files and matches the plugin's known
# corrections; it sends nothing and changes no skill. A refresh that can't finish is tried again
# at a later session start, no sooner than ten minutes on.
# The note shows only when a session starts fresh, at most once a day; corrections go every
# time, including after /clear and /compact, which drop what Claude was told before.
# Silent when there is nothing to say, off a Mac, or when the files are older than 7 days (whatever
# makes them has stopped, so nothing in them can be trusted to be current).
#
# Two options, changed with /plugin configure skill-health (Claude Code passes them in the environment,
# unset or "true" until the person turns one off):
#   session_note             CLAUDE_PLUGIN_OPTION_SESSION_NOTE             off: the note never prints
#   corrections_for_claude   CLAUDE_PLUGIN_OPTION_CORRECTIONS_FOR_CLAUDE   off: Claude gets nothing
# Off for both means this hook prints nothing at all and starts no refresh. The tool and the app write
# both files either way.
#
# Every run also writes plugin.json (the plugin's version and when it ran), which is how the app
# knows the plugin is connected and whether it is new enough for the commands its menu opens.

[ "$(uname -s)" = Darwin ] || exit 0
dir="${SKILL_HEALTH_DIR:-$HOME/.claude/skill-health}"
now=$(date +%s)

# age_of <path>: how many seconds ago it was written; fails when it can't be read. Negative when
# its date is in the future (a clock that ran ahead once). The system's stat, not whichever is first
# on PATH: a GNU stat (Homebrew coreutils) takes other flags.
age_of() {
  written=$(/usr/bin/stat -f %m "$1" 2>/dev/null) || return 1
  echo $((now - written))
}

# recent <path> <seconds>: written no longer ago than that. A date in the future doesn't count.
recent() {
  age=$(age_of "$1") || return 1
  [ "$age" -ge 0 ] && [ "$age" -lt "$2" ]
}

# turned_off <option value>: the person set it to false.
turned_off() {
  case $(printf '%s' "$1" | tr 'A-Z' 'a-z') in false) return 0 ;; esac
  return 1
}
note_on=yes
corrections_on=yes
turned_off "${CLAUDE_PLUGIN_OPTION_SESSION_NOTE:-}" && note_on=no
turned_off "${CLAUDE_PLUGIN_OPTION_CORRECTIONS_FOR_CLAUDE:-}" && corrections_on=no

# Starts `skill-health refresh` in the background when what Claude gets is a day old or was never
# made: neither status.json (the app's, or the tool's) nor .refreshed (the tool's) written in the last
# 20 hours. Claimed by making .refresh-lock, which only one of several sessions starting together
# can do; a lock ten minutes old was left by a refresh that never finished and is replaced.
# Detached, with every stream closed, so Claude Code has nothing to wait for.
refresh_in_background() {
  [ "$note_on" = yes ] || [ "$corrections_on" = yes ] || return 0
  [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -x "$CLAUDE_PLUGIN_ROOT/bin/skill-health" ] || return 0
  # Told which folder to read and write: the one this hook reads, whatever the account's home says.
  claude_home="${SKILL_HEALTH_CLAUDE_HOME:-$(dirname "$dir")}"
  # No skills folder, nothing to look at, and no folder of ours to make for it.
  [ -d "$claude_home/skills" ] || return 0
  # Skill Health works on ~/.claude. With Claude Code pointed at another folder (CLAUDE_CONFIG_DIR)
  # it would read the skills and sessions of a profile Claude Code isn't using.
  case "${CLAUDE_CONFIG_DIR:-}" in ''|"$HOME/.claude"|"$HOME/.claude/") ;; *) return 0 ;; esac
  recent "$dir/status.json" 72000 && return 0
  recent "$dir/.refreshed" 72000 && return 0
  lock="$dir/.refresh-lock"
  age=$(age_of "$lock") && { [ "$age" -gt 600 ] || [ "$age" -lt 0 ]; } && rmdir "$lock" 2>/dev/null
  mkdir -p "$dir" 2>/dev/null && mkdir "$lock" 2>/dev/null || return 0
  ( SKILL_HEALTH_CLAUDE_HOME="$claude_home" \
      nohup "$CLAUDE_PLUGIN_ROOT/bin/skill-health" refresh </dev/null >/dev/null 2>&1 & ) 2>/dev/null
  return 0
}
refresh_in_background

[ -d "$dir" ] || exit 0

# Lets older apps show that Claude Code reads their notes.
touch "$dir/hook-read" 2>/dev/null

# The handshake. The version comes from the plugin's own manifest and is only trusted if it looks
# like a version, because it is written into JSON by hand; anything else is "unknown", which the
# app treats as older than it needs. Written to a temp file in the same folder and moved into
# place, so the app never reads half of it.
version=unknown
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && command -v jq >/dev/null 2>&1; then
  read_version=$(jq -r '.version // empty | strings' "$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null)
  case $read_version in
    ''|*[!0-9A-Za-z.+-]*) ;;
    *) [ ${#read_version} -le 64 ] && version=$read_version ;;
  esac
fi
handshake="$dir/.plugin.json.$$"
{ printf '{"version":"%s","readAt":"%s"}\n' "$version" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$handshake"; } 2>/dev/null \
  && mv -f "$handshake" "$dir/plugin.json" 2>/dev/null
rm -f "$handshake" 2>/dev/null

fresh() {
  [ -r "$1" ] && recent "$1" 604801
}

input=$(cat)
starting=no
printf '%s' "$input" | grep -q '"source"[[:space:]]*:[[:space:]]*"startup"' && starting=yes

# The note's once-a-day stamp lives in the plugin's own data folder, which Claude Code keeps
# across plugin updates and removes on uninstall. Without that folder the note stays quiet.
if [ "$note_on" = yes ] && [ "$starting" = yes ] && [ -n "${CLAUDE_PLUGIN_DATA:-}" ] && fresh "$dir/hook-note.json"; then
  stamp="$CLAUDE_PLUGIN_DATA/note-shown"
  # Due when the last note was a day ago, or its date is in the future.
  last_age=$(age_of "$stamp") || last_age=86400
  if [ "$last_age" -ge 86400 ] || [ "$last_age" -lt 0 ]; then
    if [ "$corrections_on" = yes ]; then
      # Only a note that was printed ends the hook; if it couldn't be, the corrections still go.
      mkdir -p "$CLAUDE_PLUGIN_DATA" && cat "$dir/hook-note.json" && { touch "$stamp"; exit 0; }
    else
      # The note without what is meant for Claude, and without the sentence that says Claude gets
      # it (StatusSnapshot.correctionsTail, word for word). Without jq, or without a note in the
      # file, nothing prints and the stamp stays unset.
      note_only=$(jq -c 'del(.hookSpecificOutput) | select(.systemMessage != null)
        | .systemMessage |= (if endswith(" Claude gets the corrections at the start of every session.")
            then .[0:(length - (" Claude gets the corrections at the start of every session." | length))] else . end)' \
        "$dir/hook-note.json" 2>/dev/null)
      [ -n "$note_only" ] && mkdir -p "$CLAUDE_PLUGIN_DATA" && printf '%s\n' "$note_only" && { touch "$stamp"; exit 0; }
    fi
  fi
fi

[ "$corrections_on" = yes ] && fresh "$dir/hook-quiet.json" && cat "$dir/hook-quiet.json"
exit 0
