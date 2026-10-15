#!/bin/bash
#
# tmux-test-guard.test.sh
#
# Pins the two halves of keeping tmux suites off the developer's machine:
#
# (1) Enrollment: every tmux suite sources bin/tmux-test-guard.sh -- each
#     bin/tmux-*.test.sh, and any suite that invokes `tmux ... new-session` or
#     `kill-server` outside a comment. "Remember to add the guard" is the same
#     kind of rule as "remember to unset TMUX", which is the one that already
#     failed. Matching the bare words would be wrong both ways: two tmux-*
#     suites only see them as text in a stub's call log, and a zsh suite quotes
#     them in a comment and an expected string without running tmux.
# (2) Refusal: outside a container and outside CI, sourcing the guard stops the
#     caller with exit 2 before anything after it runs.
#
# And the two places that run the tmux suites agree with (1): bin/test skips
# exactly those on a laptop, and bin/test-in-docker -- run against a stubbed
# docker -- runs exactly those, asked as a laptop wherever it runs, mounted
# read-only with no tty, for the host's platform unless TEST_DOCKER_PLATFORM
# names one, refusing to run anything on a failed listing, and passing
# bin/test's verdict on.
#
# tmux-free itself: it needs GNU parallel (for the verdict cases), and the one
# case that fakes the runner puts a refusing tmux first on PATH.

set -eo pipefail

cd "$(dirname "$0")/.."
fails=0
fail() {
  printf 'FAIL %s\n' "$1"
  fails=$((fails + 1))
}

# Listings that fail must not read as "there are no tmux suites".
if ! named=$(git ls-files -- 'bin/tmux-*.test.sh'); then
  fail "could not list bin/tmux-*.test.sh"
fi
if ! invokers=$(git grep -l -E '^[^#]*tmux[^#]*(new-session|kill-server)' -- '*.test.sh' '*.test.zsh'); then
  fail "could not list the suites that invoke tmux"
fi
suites=$(printf '%s\n%s\n' "$named" "$invokers" | sort -u)
count=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  # Matches bin/tmux-*.test.sh by name, and would pass itself: the pattern
  # below is in its own text.
  [ "$f" = bin/tmux-test-guard.test.sh ] && continue
  count=$((count + 1))
  # Both lookups below are awk, not `grep -n | head -n 1`: under set -e and
  # pipefail that form ends the suite in silence. A grep that finds nothing
  # exits 1 -- for this first lookup, on exactly the suite whose missing guard
  # the FAIL below should name. awk prints the first match's line number and
  # exits 0 whether or not anything matched.
  #
  # The sourcing line, the same match bin/test-in-docker enrolls by.
  guard_line=$(awk '/^\. .*tmux-test-guard\.sh" \|\| exit 2$/ { print NR; exit }' "$f")
  if [ -z "$guard_line" ]; then
    fail "$f is a tmux suite but does not source the guard (with || exit 2)"
    continue
  fi
  # And BEFORE anything that would act on the host when the guard refuses: a
  # trap registered above it runs its cleanup -- a bare `tmux kill-server` --
  # on the exit the guard itself causes.
  #
  # This is the lookup that turned CI red. It matches many lines (136 in
  # tmux-agents.test.sh), so grep's output spans several writes; head exits
  # after one line, grep's next write gets EPIPE, and pipefail plus errexit
  # ended the run on every Linux run with no FAIL line. Do not put it back.
  first_act=$(awk '/^[[:space:]]*(trap |tmux )/ { print NR; exit }' "$f")
  if [ -n "$first_act" ] && [ "$first_act" -lt "$guard_line" ]; then
    fail "$f registers a trap or runs tmux (line $first_act) before the guard (line $guard_line)"
  fi
done <<<"$suites"
# A listing that found almost nothing would make the loop above vacuous. A
# floor, not the exact count, so adding a suite does not mean editing this.
[ "$count" -ge 5 ] || fail "found only $count tmux suite(s); the listing is broken"
[ "$fails" -eq 0 ] && printf 'ok   all %d tmux suites source the guard before any trap or tmux call\n' "$count"

# bin/test-in-docker runs the suites bin/test skips on a laptop, read from
# bin/test --list, which finds them by a COPY of the regex above. If the two
# drift, or the parsing of that listing breaks, a local run quietly stops
# running some suites and still reports them all passed. So it is run here,
# with docker stubbed to record what it was asked to run, and its list must be
# exactly the guarded suites found above.
stub=$(mktemp -d)
trap '/bin/rm -rf "$stub"' EXIT
cat >"$stub/docker" <<'EOF'
#!/bin/bash
# `docker build` and `docker run` each record their arguments, one per line,
# to a file of their own; build then succeeds. With DOCKER_EXEC set it then runs what follows the image
# name here, so the command that would run in the container -- bin/test and its
# verdict -- runs too.
if [ "$1" = build ]; then
  printf '%s\n' "$@" >"$DOCKER_ARGV.build"
  exit 0
fi
[ "$1" = run ] || exit 0
printf '%s\n' "$@" >"$DOCKER_ARGV"
[ -n "${DOCKER_EXEC:-}" ] || exit 0
while [ $# -gt 0 ] && [ "$1" != dotfiles-test ]; do shift; done
shift
exec "$@"
EOF
chmod +x "$stub/docker"
# A tmux that refuses, first on PATH for everything run through the stub. The
# case below fakes the runner (GITHUB_ACTIONS=true), which is what lets the
# guard through; if a suite were ever run on this host from here -- DOCKER_EXEC
# left in the caller's environment, or a test-in-docker that stopped going
# through docker -- it would reach this, not the developer's server.
printf '#!/bin/sh\necho "tmux-test-guard.test.sh: tmux refused on the host" >&2\nexit 99\n' >"$stub/tmux"
chmod +x "$stub/tmux"
# Run in the environment furthest from a laptop -- GITHUB_ACTIONS=true and a
# container mark that exists -- because test-in-docker promises to ask bin/test
# as a laptop wherever it runs. Run from a laptop, a test-in-docker that let
# either variable through would still list the right suites here.
if out=$(DOCKER_EXEC='' GITHUB_ACTIONS=true TEST_CONTAINER_MARK="$stub/docker" \
  PATH="$stub:$PATH" DOCKER_ARGV="$stub/argv" bash bin/test-in-docker 2>&1) &&
  [ -f "$stub/argv" ]; then
  # Everything after the command bin/test is the suite list.
  ran=$(sed -n '/^bin\/test$/,$p' "$stub/argv" | sed 1d | sort)
  want=$(printf '%s\n' "$suites" | grep -vxF bin/tmux-test-guard.test.sh | sed '/^$/d' | sort)
  if [ "$ran" = "$want" ]; then
    printf 'ok   test-in-docker runs exactly the %d guarded suites, asked as a laptop\n' "$count"
  else
    fail "test-in-docker's suite list differs from the guarded suites: $(diff <(printf '%s\n' "$want") <(printf '%s\n' "$ran") | tr '\n' ' ')"
  fi
  # Read-only, and no -t: the runner has no TERM, and a writable mount lets a
  # suite edit the checkout it is testing. TEST_JOBS and TEST_TIMEOUT reach
  # bin/test in the container only if docker is told to pass them.
  shape_ok=true
  grep -qx -- "$PWD:/work:ro" "$stub/argv" || {
    fail "test-in-docker does not mount the checkout read-only"
    shape_ok=false
  }
  if grep -qxE -- '-[a-z]*t[a-z]*|--tty' "$stub/argv"; then
    fail "test-in-docker allocates a tty, so TERM is set unlike on the runner"
    shape_ok=false
  fi
  for v in TEST_JOBS TEST_TIMEOUT; do
    grep -qx -- "$v" "$stub/argv" || {
      fail "test-in-docker does not pass $v into the container"
      shape_ok=false
    }
  done
  $shape_ok && printf 'ok   mounted read-only, no tty, TEST_JOBS and TEST_TIMEOUT passed in\n'
else
  fail "test-in-docker failed, or never ran docker, with docker stubbed: $out"
fi

# A listing that fails must run nothing and say so -- "ran nothing, all green"
# is the most expensive trap this repo has had (bin/lint-shell). bin/test
# --list fails here because git cannot find the repository.
rm -f "$stub/argv" "$stub/argv.build"
if out=$(GIT_DIR=/nonexistent PATH="$stub:$PATH" DOCKER_ARGV="$stub/argv" bash bin/test-in-docker 2>&1); then
  fail "test-in-docker exited 0 though bin/test --list failed: $out"
elif [ -e "$stub/argv" ] || [ -e "$stub/argv.build" ]; then
  fail "test-in-docker built or ran docker though bin/test --list failed: $out"
else
  case "$out" in
    *"bin/test --list failed"*) printf 'ok   a failed listing builds and runs nothing and exits non-zero\n' ;;
    *) fail "test-in-docker failed, but not at the listing: $out" ;;
  esac
fi

# The platform. Native by default: under amd64 emulation on Apple silicon the
# tmux suites took ~60 s against ~8 s, which was most of a laptop run -- and a
# --platform put back by habit would only show as a slow run, never a red one.
# TEST_DOCKER_PLATFORM asks for another, and must reach the build as well as
# the run: the image is one tag, so a run alone would start whatever the last
# build left there. One suite named, so a broken listing cannot redden these.
platform_of() { # platform_of <argv file> -- the --platform value, or "none"
  awk 'p { print; f = 1; exit }
    $0 == "--platform" { p = 1; next }
    /^--platform=/ { sub(/^--platform=/, ""); print; f = 1; exit }
    END { if (!f) print "none" }' "$1"
}
platform_case() { # platform_case <what> <want "build run"> <env argument...>
  local what=$1 want=$2 out got
  shift 2
  rm -f "$stub/argv" "$stub/argv.build"
  if ! out=$(env "$@" PATH="$stub:$PATH" DOCKER_ARGV="$stub/argv" \
    /bin/bash bin/test-in-docker bin/tmux-pane-titles.test.sh 2>&1); then
    fail "$what: test-in-docker failed with docker stubbed: $out"
  elif [ ! -f "$stub/argv.build" ] || [ ! -f "$stub/argv" ]; then
    fail "$what: docker build or docker run was never called: $out"
  else
    got="$(platform_of "$stub/argv.build") $(platform_of "$stub/argv")"
    if [ "$got" = "$want" ]; then
      printf 'ok   %s\n' "$what"
    else
      fail "$what: --platform for (build, run): want [$want] got [$got]"
    fi
  fi
}
# Unset, not empty: that is what "by default" means. /bin/bash, the shebang's
# shell, so an empty array's expansion is checked under bash 3.2 on a Mac.
platform_case 'by default the image is built and run for the host platform' \
  'none none' -u TEST_DOCKER_PLATFORM
# Empty is unset too, not `--platform ''`.
platform_case 'an empty TEST_DOCKER_PLATFORM is the default too' \
  'none none' TEST_DOCKER_PLATFORM=
# Not linux/amd64, the value the old code hard-coded: an implementation that
# added that whenever the variable was set would pass with it.
platform_case 'TEST_DOCKER_PLATFORM reaches both the build and the run' \
  'linux/s390x linux/s390x' TEST_DOCKER_PLATFORM=linux/s390x

# bin/test holds the second copy of the regex, deciding which suites a laptop
# run skips -- and so which suites test-in-docker runs. Checked on its own as
# well as through the run above, so a red here alone points at the regex and a
# red above alone at test-in-docker's reading of the listing.
if host_list=$(GITHUB_ACTIONS=false TEST_CONTAINER_MARK=/nonexistent bin/test --list); then
  skipped=$(sed -n 's/^skip \([^ ]*\)  (a tmux suite: .*)$/\1/p' <<<"$host_list" | sort)
  want=$(printf '%s\n' "$suites" | grep -vxF bin/tmux-test-guard.test.sh | sed '/^$/d' | sort)
  if [ "$skipped" = "$want" ]; then
    printf 'ok   bin/test skips exactly the %d guarded suites on a laptop\n' "$count"
  else
    fail "bin/test's tmux skips differ from the guarded suites: $(diff <(printf '%s\n' "$want") <(printf '%s\n' "$skipped") | tr '\n' ' ')"
  fi
else
  fail "bin/test --list failed"
fi

# The verdict, run for real through the stub. test-in-docker is the only way to
# run the tmux suites locally, and its exit status is what a caller -- an agent
# included -- believes. The tally itself is bin/test's (bin/test.test.sh pins
# it); what is pinned here is that test-in-docker hands its suites to bin/test
# and passes its verdict on. The fixtures are given by absolute path, which
# bin/test resolves as the container would.
tally=$(mktemp -d)
trap '/bin/rm -rf "$stub" "$tally"' EXIT
printf 'exit 0\n' >"$tally/pass.test.sh"
printf 'exit 3\n' >"$tally/fail.test.sh"
run_tally() {
  PATH="$stub:$PATH" DOCKER_ARGV="$stub/argv" DOCKER_EXEC=1 bash bin/test-in-docker "$@" 2>&1
}
if out=$(run_tally "$tally/pass.test.sh" "$tally/fail.test.sh"); then
  fail "test-in-docker exited 0 with a failing suite: $out"
else
  case "$out" in
    *"FAIL $tally/fail.test.sh (exit 3)"*"1 passed, 1 failed"*)
      printf 'ok   a failing suite makes test-in-docker exit non-zero, naming it, both suites run\n'
      ;;
    *) fail "test-in-docker failed without bin/test naming the failing suite: $out" ;;
  esac
fi
if out=$(run_tally "$tally/pass.test.sh"); then
  case "$out" in
    *"1 passed, 0 failed"*) printf 'ok   a passing suite makes it exit 0, run by bin/test\n' ;;
    *) fail "test-in-docker passed without bin/test's verdict: $out" ;;
  esac
else
  fail "test-in-docker failed a passing suite: $out"
fi

# Refusal. Only checkable where the guard is meant to refuse: in a container
# /.dockerenv exists and it rightly lets the caller through.
if [ ! -f /.dockerenv ]; then
  set +e
  out=$(env -u GITHUB_ACTIONS bash -c '. bin/tmux-test-guard.sh; echo REACHED' 2>&1)
  status=$?
  set -e
  if [ "$status" -eq 2 ] && [ "${out#*REACHED}" = "$out" ]; then
    printf 'ok   outside a container and CI, the guard exits 2 before the caller continues\n'
  else
    fail "outside a container and CI the guard let the caller run (exit $status): $out"
  fi
fi

if [ "$fails" -eq 0 ]; then
  echo "PASS"
else
  echo "$fails failure(s)"
  exit 1
fi
