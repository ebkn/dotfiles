#!/bin/bash
#
# fzf-files.test.sh
#
# Pins bin/fzf-files, the list behind prefix + o and nvim's :Files: files git
# says changed come first, labelled by how, then everything else, each path once
# and relative to where it was run. A regression here does not error -- the
# picker still fills, just with the file you were editing somewhere in the
# middle, or with nothing at all.
#
# git is real (the parsing of its output is the subject). rg is a stub that lists
# the work tree the way `rg --files` does, since the runner does not carry
# ripgrep and the rest-of-the-files half is rg's own behaviour, not this
# script's.
#
# Written for bash 3.2 (/bin/bash on macOS).
set -uo pipefail

FF="$(cd "$(dirname "$0")" && pwd -P)/fzf-files"
TMP=$(mktemp -d)
TMP=$(cd "$TMP" && pwd -P)
trap '/bin/rm -rf "$TMP"' EXIT

fails=0
t() { # t <name> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}

mkdir -p "$TMP/stub"
cat >"$TMP/stub/rg" <<'STUB'
#!/bin/sh
# `rg --files --hidden`: every file under ., .git excluded, cwd-relative.
find . -type f ! -path './.git/*' | sed 's|^\./||' | sort
STUB
chmod +x "$TMP/stub/rg"
export PATH="$TMP/stub:$PATH"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
ff() { "$FF" "$@" 2>&1; }

# --- a repository with no commits yet ------------------------------------------
# `git log` exits 128 on a branch with no commits. Under set -e that ended the
# script before it printed anything: right after `git init`, the picker was
# empty.
repo0="$TMP/fresh"
git init -q "$repo0"
cd "$repo0" || exit 1
printf 'x\n' >a.txt
t "a repo with no commits still lists its files" "a.txt" "$(ff | tr '\t' ' ')"
t "and labels them, untracked" "[ untracked   ] a.txt" "$(ff --label | tr '\t' ' ')"

# --- the order, and the labels ---------------------------------------------------
repo="$TMP/repo"
git init -q "$repo"
cd "$repo" || exit 1
git config user.email t@e
git config user.name t
mkdir -p sub
for f in old.txt zz-recent.txt committed.txt staged.txt unstaged.txt sub/in-sub.txt sub/rest-sub.txt rest.txt; do
  printf 'one\n' >"$f"
done
git add -A
git commit -qm base
# Six commits later, old.txt's change is outside the last five.
printf 'two\n' >>old.txt
git commit -qam 'touch old'
for i in 1 2 3 4 5; do
  printf '%s\n' "$i" >>committed.txt
  if [ "$i" = 3 ]; then
    printf '%s\n' "$i" >>zz-recent.txt
    # Names git log quotes. core.quotePath=false stops only the octal escaping
    # of non-ASCII; a double quote is still wrapped and escaped.
    printf 'x\n' >'say "hi".txt'
    printf 'x\n' >'漢字.txt'
    # A backslash is the byte a `read` without -r, `awk -v` or `echo -e`
    # would rewrite downstream, so it pins the name surviving as bytes.
    printf 'x\n' >'zz-back\slash.txt'
    git add 'say "hi".txt' '漢字.txt' 'zz-back\slash.txt'
  fi
  git commit -qam "c$i"
done
printf 'two\n' >>staged.txt
git add staged.txt
printf 'two\n' >>unstaged.txt
printf 'new\n' >untracked.txt
# A file both committed recently AND staged now: the first label wins.
printf 'three\n' >>committed.txt
git add committed.txt
# Names git quotes in its default output: a space, and non-ASCII.
printf 'x\n' >'my file.md'
printf 'x\n' >'日本語.md'
# A deleted file is changed but not there to open.
git rm -q rest.txt

labels=$(ff --label | awk -F'\t' '{ print (NF > 1 ? $1 : "") "|" $NF }')
first_of() { printf '%s\n' "$labels" | grep -nF "|$1" | head -1 | cut -d: -f1; }
label_of() { printf '%s\n' "$labels" | grep -F "|$1" | head -1 | cut -d'|' -f1; }
t "an untracked file is labelled untracked" "[ untracked   ]" "$(label_of untracked.txt)"
t "a staged one, staged" "[ staged      ]" "$(label_of staged.txt)"
t "an unstaged one, unstaged" "[ unstaged    ]" "$(label_of unstaged.txt)"
t "staged outranks committed for the same file" "[ staged      ]" "$(label_of committed.txt)"
t "a file only changed long ago gets no label" "" "$(label_of old.txt)"
# zz-recent.txt changed in c3 and nowhere since: the third-newest commit, so it is
# labelled with that commit's short hash and (-3).
c3=$(git log --format=%h -1 --skip=2)
t "a file changed in a recent commit is labelled with its hash and how many ago" \
  "[ $(printf '%-11s' "$c3(-3)") ]" "$(label_of zz-recent.txt)"
t "and comes before the unchanged files" "yes" \
  "$([ "$(first_of zz-recent.txt)" -lt "$(first_of sub/rest-sub.txt)" ] && echo yes || echo no)"
t "a recently committed name with a double quote keeps its commit label" \
  "[ $(printf '%-11s' "$c3(-3)") ]" "$(label_of 'say "hi".txt')"
t "and a non-ASCII one" "[ $(printf '%-11s' "$c3(-3)") ]" "$(label_of '漢字.txt')"
t "and one with a backslash" "[ $(printf '%-11s' "$c3(-3)") ]" "$(label_of 'zz-back\slash.txt')"
t "untracked comes before staged" "yes" "$([ "$(first_of untracked.txt)" -lt "$(first_of staged.txt)" ] && echo yes || echo no)"
t "staged before unstaged" "yes" "$([ "$(first_of staged.txt)" -lt "$(first_of unstaged.txt)" ] && echo yes || echo no)"
t "changed files before the rest" "yes" "$([ "$(first_of unstaged.txt)" -lt "$(first_of sub/rest-sub.txt)" ] && echo yes || echo no)"
t "every path appears once" "" "$(printf '%s\n' "$labels" | cut -d'|' -f2 | sort | uniq -d)"
t "a deleted file is not offered" "0" "$(printf '%s\n' "$labels" | grep -c '|rest.txt$')"
# The path stays the LAST tab-separated field: FZF_DEFAULT_OPTS (.zshenv) sets
# --nth=-1 --accept-nth=-1, so the label must be a column of its own.
t "the label is a field of its own, the path the last" "staged.txt" \
  "$(ff --label | grep -F 'staged.txt' | grep -v unstaged | head -1 | awk -F'\t' '{ print $NF }')"
t "a name with a space is listed as changed, unquoted" "[ untracked   ]" "$(label_of 'my file.md')"
t "a non-ASCII name is listed as changed, unquoted" "[ untracked   ]" "$(label_of '日本語.md')"

plain=$(ff)
t "plain mode lists the changed files first too" "untracked.txt" \
  "$(printf '%s\n' "$plain" | grep -nx -e untracked.txt -e sub/rest-sub.txt | head -1 | cut -d: -f2)"
t "plain mode has no labels" "0" "$(printf '%s\n' "$plain" | grep -c '\[')"
t "plain mode lists a recently committed file before the unchanged ones" "zz-recent.txt" \
  "$(printf '%s\n' "$plain" | grep -nx -e zz-recent.txt -e sub/rest-sub.txt | head -1 | cut -d: -f2)"

# --- from a subdirectory -----------------------------------------------------------
# git status prints repo-root paths and rg cwd-relative ones; the two have to
# line up, or one file shows up twice under two names and neither opens.
printf 'two\n' >>sub/in-sub.txt
cd sub || exit 1
sub_labels=$(ff --label | awk -F'\t' '{ print (NF > 1 ? $1 : "") "|" $NF }')
t "from a subdirectory, a changed file there is cwd-relative" "[ unstaged    ]|in-sub.txt" \
  "$(printf '%s\n' "$sub_labels" | grep -F '|in-sub.txt' | head -1)"
t "and files outside it are left out" "0" "$(printf '%s\n' "$sub_labels" | grep -c 'staged.txt')"

# A subdirectory with backslashes in its name: the prefix stripped from git
# status paths must reach awk as data. `awk -v` interprets escapes in the value.
# The name holds `\\`, whose meaning every POSIX awk defines (one backslash):
# a lone `\s` is undefined, and mawk -- Ubuntu's, so CI's -- keeps it as is,
# which would let the old code pass there. Under `-v`, "back\\slash/" became
# "back\slash/", matched nothing, and every git status entry there lost its label
# and its place at the top.
cd "$repo" || exit 1
mkdir -p 'back\\slash'
printf 'x\n' >'back\\slash/a-old.txt'
git add 'back\\slash/a-old.txt'
git commit -qm 'a dir with backslashes'
printf 'x\n' >'back\\slash/z-new.txt'
cd 'back\\slash' || exit 1
bs_labels=$(ff --label | awk -F'\t' '{ print (NF > 1 ? $1 : "") "|" $NF }')
t "from a directory with backslashes, a changed file there keeps its label" "[ untracked   ]|z-new.txt" \
  "$(printf '%s\n' "$bs_labels" | grep -F '|z-new.txt' | head -1)"
# The log half: a file committed there just now is labelled, under its
# cwd-relative name. The only case that checks recent_log's output from a
# subdirectory, so the only one guarding --relative.
t "and a file committed there recently keeps its commit label, cwd-relative" \
  "[ $(printf '%-11s' "$(git log --format=%h -1)(-1)") ]|a-old.txt" \
  "$(printf '%s\n' "$bs_labels" | grep -F '|a-old.txt' | head -1)"
# Plain mode strips the prefix the same way, and lists status entries before
# log ones: a-old.txt is in the newest commit, so if the status entry were lost
# it would come first from the log half.
t "plain mode strips the prefix too: the untracked file there comes first" "z-new.txt" "$(ff | head -1)"

# --- a rename -------------------------------------------------------------------
# A rename is reported as the new name followed by the old one as an entry of
# its own. The new name is the file; the old one must be dropped -- without
# also dropping whatever entry comes after it.
repo2="$TMP/rename"
git init -q "$repo2"
cd "$repo2" || exit 1
git config user.email t@e
git config user.name t
printf 'a\n' >a.txt
printf 'c\n' >c.txt
git add -A
git commit -qm base
git mv a.txt b.txt
printf 'c2\n' >>c.txt
git add c.txt
r_labels=$(ff --label | awk -F'\t' '{ print (NF > 1 ? $1 : "") "|" $NF }')
t "a renamed file is listed under its new name, staged" "[ staged      ]|b.txt" \
  "$(printf '%s\n' "$r_labels" | grep -F '|b.txt')"
t "the entry after a rename is not lost" "[ staged      ]|c.txt" \
  "$(printf '%s\n' "$r_labels" | grep -F '|c.txt')"

# --- a path that is not valid UTF-8, in history ---------------------------------------
# .zshenv exports LC_ALL=en_US.UTF-8, and in that locale macOS's tr ("Illegal
# byte sequence") and awk ("towc: multibyte conversion failure") both abort on
# an invalid byte sequence -- the awk that reads the log lines is what emptied
# --label under set -e, so fixing tr alone leaves this red. APFS cannot create
# such a file, so it arrives only through a commit made elsewhere: built here
# with plumbing. GNU tr and awk are byte-wise, so on Linux this passes either
# way; it is a macOS check.
repo4="$TMP/repo4"
git init -q "$repo4"
cd "$repo4" || exit 1
git config user.email t@e
git config user.name t
printf 'x\n' >ok.txt
git add ok.txt
blob=$(printf 'x\n' | git hash-object -w --stdin)
git update-index --add --cacheinfo "100644,$blob,$(printf 'bad\377.txt')"
git commit -qm 'a name from elsewhere'
t "a path that is not UTF-8 in recent history does not empty the listing" "[ $(printf '%-11s' "$(git log --format=%h -1)(-1)") ]|ok.txt" \
  "$(LC_ALL=en_US.UTF-8 ff --label | awk -F'\t' '{ print (NF > 1 ? $1 : "") "|" $NF }' | grep -F '|ok.txt')"

# --- outside a repository ------------------------------------------------------------
mkdir -p "$TMP/plain"
cd "$TMP/plain" || exit 1
printf 'x\n' >only.txt
t "outside a repository it is rg --files" "only.txt" "$(ff)"

if [ "$fails" -eq 0 ]; then
  echo "PASS"
else
  echo "$fails failure(s)"
  exit 1
fi
