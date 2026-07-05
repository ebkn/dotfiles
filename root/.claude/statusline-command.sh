#!/bin/bash
# Claude Code statusLine — p10k-flavored layout.
# Renders: <dir>  <branch>[*]  ·  <model>[ (<effort>)][  <pct>% Used]
# Git is the only external command consulted (no language/tool version
# shell-outs) to keep the status line fast on every prompt.

input=$(cat)

# Pull every field in one jq pass, one value per line. Reading each line whole
# with `IFS= read -r` preserves empty values (e.g. effort absent on models that
# don't support it) — a plain space/tab split would collapse them and misalign
# the rest. Indexing a missing object (.effort / .context_window) yields null in
# jq, so the // "" / null guards degrade gracefully when a field isn't present.
{
  IFS= read -r dir
  IFS= read -r model
  IFS= read -r effort
  IFS= read -r used
} < <(echo "$input" | jq -r '
  .workspace.current_dir,
  .model.display_name,
  (.effort.level // ""),
  (.context_window.used_percentage | if . == null then "" else (round | tostring) end)
')

# Abbreviate $HOME to ~, mirroring p10k's directory segment.
# The replacement tilde is escaped: under bash a leading unescaped ~ in a
# ${var/pat/repl} replacement is special-cased and the substitution no-ops.
segment="${dir/#$HOME/\~}"

# --no-optional-locks avoids contending with concurrent git operations
# (e.g. another shell mid-commit) since this runs on every prompt render.
if git -C "$dir" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$dir" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)
  if [ -z "$branch" ]; then
    # Detached HEAD: fall back to short commit hash.
    branch=$(git -C "$dir" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  fi
  if [ -n "$branch" ]; then
    if [ -n "$(git -C "$dir" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
      branch="${branch}*"
    fi
    segment="${segment}  ${branch}"
  fi
fi

# Right group: model, then effort (parenthesized so it doesn't read as part of
# the model name) and consumed-context percentage when each is available.
right="$model"
[ -n "$effort" ] && right="$right ($effort)"
[ -n "$used" ] && right="$right  ${used}% Used"

# Justified layout mirroring p10k's split left/right prompts: dir+git flush
# left, the model group flush right. Claude Code sets COLUMNS to the terminal
# width (v2.1.153+); pad the gap with spaces to push the right group to the
# edge. Fall back to a single "·"-joined line when COLUMNS is unset (older
# client) or too narrow to fit both groups with a gap.
#
# Width uses ${#var}, i.e. character count. Both groups are ASCII in the common
# case so this equals the on-screen column count. A path containing full-width
# (CJK) or other multi-column glyphs will shift the right group by a few columns
# since one such character occupies two terminal columns but counts as one here;
# a pure-bash wcwidth is not worth the per-render cost.
gap=$(( ${COLUMNS:-0} - ${#segment} - ${#right} ))
if [ "$gap" -ge 2 ]; then
  printf '%s%*s%s' "$segment" "$gap" '' "$right"
else
  printf '%s  ·  %s' "$segment" "$right"
fi
