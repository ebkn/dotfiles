#!/bin/bash
# Claude Code statusLine — p10k-flavored, two rows.
#   Row 1: <launch-dir>[ (in ./<working-dir-relative-to-launch>)]
#   Row 2: <model>[ (<effort>)][  <pct>% Used]
# Row 1 names the directory Claude was launched from and, only when the live
# working directory has moved elsewhere, appends where it is now. Row 2 lists
# session info: model, effort, and consumed context. Parsing is a single jq
# pass with no per-field subprocess, keeping the status line fast on every prompt.

input=$(cat)

# Pull every field in one jq pass, one value per line. Reading each line whole
# with `IFS= read -r` preserves empty values (e.g. effort absent on models that
# don't support it) — a plain space/tab split would collapse them and misalign
# the rest. Indexing a missing object yields null in jq, so the // "" / null
# guards degrade gracefully when a field isn't present.
{
  IFS= read -r launch_dir
  IFS= read -r work_dir
  IFS= read -r model
  IFS= read -r effort
  IFS= read -r used
} < <(echo "$input" | jq -r '
  (.workspace.project_dir // ""),
  (.workspace.current_dir // ""),
  .model.display_name,
  (.effort.level // ""),
  (.context_window.used_percentage | if . == null then "" else (round | tostring) end)
')

# Abbreviate a path for display: ghq's github.com checkout root collapses to
# [ghq] (most repos live there, so it's the biggest win); otherwise $HOME
# collapses to ~, mirroring p10k. ghq is checked first as the more specific
# prefix. The escaped \~ matters: under bash a leading unescaped ~ in a
# ${var/pat/repl} replacement is special-cased and the substitution no-ops. The
# quoted prefix in ${p#"$ghq"/} matches literally so glob chars aren't patterns.
abbrev_path() {
  local p=$1 ghq="$HOME/ghq/github.com"
  if [ "$p" = "$ghq" ]; then
    printf '[ghq]'
  elif [ "${p#"$ghq"/}" != "$p" ]; then
    printf '[ghq]/%s' "${p#"$ghq"/}"
  else
    printf '%s' "${p/#$HOME/\~}"
  fi
}
launch_disp=$(abbrev_path "$launch_dir")
work_disp=$(abbrev_path "$work_dir")

# Row 1: just the directory when the working dir matches the launch dir (the
# common case); otherwise show the launch dir and where work has moved to,
# relative to it with a leading ./ so it reads as relative. The quoted prefix in
# ${work_dir#"$launch_dir"/} matches literally so glob chars in the path aren't
# treated as patterns; when the working dir isn't under the launch dir the
# prefix doesn't strip and we fall back to the ~-abbreviated absolute path
# (no ./, since it isn't relative) instead of a "../.."-laden relative.
if [ -z "$launch_dir" ] || [ "$launch_dir" = "$work_dir" ]; then
  row1="$work_disp"
else
  rel="${work_dir#"$launch_dir"/}"
  if [ "$rel" = "$work_dir" ]; then
    rel="$work_disp"
  else
    rel="./$rel"
  fi
  row1="$launch_disp (in $rel)"
fi

# Row 2: model, then effort (parenthesized so it doesn't read as part of the
# model name) and consumed-context percentage, each appended only when present.
row2="$model"
[ -n "$effort" ] && row2="$row2 ($effort)"
[ -n "$used" ] && row2="$row2  ${used}% Used"

printf '%s\n%s' "$row1" "$row2"
