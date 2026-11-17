#!/usr/bin/env bash
#
# mayhem/test.sh — RUN this repo's OWN functional test suite (already built by mayhem/build.sh).
# exit 0 = pass. EDIT per repo. PATCH-grade oracle: after an agent patches the source, the grader
# rebuilds (build.sh) then runs this. DELETE this file if the repo has no meaningful tests.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# Upstream's whole rspec suite, run as upstream CI does (`rspec spec/*_spec.rb spec/**/*_spec.rb`)
# with mayhem/spec_ruby.c (a ruby with this build of the extension linked in; built by build.sh with
# normal flags). spec/helpers.rb starts its own throwaway PostgreSQL server (initdb + pg_ctl from
# `pg_config --bindir`, apt postgresql-17) on localhost:23456 under ./tmp_test_specs (gitignored),
# so the suite runs offline; upstream's own filters skip the :ipv6 / :postgresql_NN examples.
# mayhem/rspec_excludes.rb drops only the examples that assert a libpq >= 18 behaviour on Debian's
# libpq 17 (see that file for the reason).
RUNNER="$SRC/tmp/mayhem-build/test/spec-ruby"
[ -x "$RUNNER" ] || { echo "test.sh: $RUNNER missing — run mayhem/build.sh first" >&2; emit_ctrf rspec 0 1 0; exit 1; }
RSPEC="$(command -v rspec)" || { echo "test.sh: rspec missing (apt ruby-rspec)" >&2; emit_ctrf rspec 0 1 0; exit 1; }

log="$(mktemp)"
"$RUNNER" -I"$SRC/tmp/mayhem-build/test/lib" -I"$SRC/lib" "$RSPEC" --require "$SRC/mayhem/rspec_excludes.rb" --no-color --format progress spec/*_spec.rb spec/**/*_spec.rb 2>&1 | tee "$log"
rc=${PIPESTATUS[0]}

# rspec's summary line: "N examples, F failures[, P pending]"
line="$(grep -E '^[0-9]+ examples?, [0-9]+ failures?' "$log" | tail -1)"
rm -f "$log"
if [ -z "$line" ]; then
  echo "test.sh: no rspec summary line (runner exit $rc)" >&2
  emit_ctrf rspec 0 1 0
  exit 1
fi
examples=$(sed -E 's/^([0-9]+) examples?.*/\1/' <<<"$line")
failures=$(sed -E 's/.* ([0-9]+) failures?.*/\1/' <<<"$line")
pending=$(grep -oE '[0-9]+ pending' <<<"$line" | grep -oE '[0-9]+' || echo 0)
passed=$(( examples - failures - pending ))
# A non-zero rspec exit with no failing example (load error, crash) still fails the suite.
[ "$rc" -eq 0 ] || [ "$failures" -gt 0 ] || failures=1
emit_ctrf rspec "$passed" "$failures" "$pending"
