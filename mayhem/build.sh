#!/usr/bin/env bash
#
# mayhem/build.sh — build this repo's fuzz harness(es). EDIT per repo.
#
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem. The base image
# (ghcr.io/savantenvs/base) already exports the build contract — use these, don't redefine:
#   CC, CXX             stock clang / clang++
#   LIB_FUZZING_ENGINE  -fsanitize=fuzzer   (link into each harness that has a LLVMFuzzer entry)
#   SANITIZER_FLAGS     -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer
#                       (ASan + UBSan, both set to HALT — so Mayhem catches memory AND UB defects)
#   DEBUG_FLAGS         -g -gdwarf-3   (DWARF debug info — always on for fuzz/standalone builds,
#                       independent of the sanitizer off-switch; DWARF version must be < 4)
#   RUST_DEBUG_FLAGS    -C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=-gdwarf-3
#                       (thread through RUSTFLAGS on every cargo-fuzz build)
#   GO_DEBUG_FLAGS      -gcflags=all=-N -l
#                       (thread through go build / go-fuzz-build so the linked ELF keeps symbols)
#   SRC                 /mayhem (the repo source)
#
# Contract: build EVERYTHING here — one runnable binary per fuzz harness, AND the project's test
# suite (so mayhem/test.sh only has to RUN it, never compile). Keep it ADDITIVE (build upstream as
# upstream documents; don't edit upstream files). IMPORTANT: build the PROJECT ITSELF with
# $SANITIZER_FLAGS and $DEBUG_FLAGS (not just the harness) so the fuzzed code is instrumented
# AND carries DWARF < 4 symbols — otherwise ASan/UBSan only see the harness, not the library
# you're trying to find bugs in, and backtraces won't resolve project source lines. Build the TEST
# suite with the project's NORMAL flags (a clean, independent build) so test.sh stays an honest
# functional oracle and won't false-fail on benign UB. Leave the test binary/runner where test.sh
# expects it.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# Build knobs come from the ENVIRONMENT (overridable), with sane defaults — no if-statements,
# just parameter-expansion fallbacks. Default sanitizers are the base's ASan+UBSan (halting); override
# per build via the Dockerfile's `--build-arg SANITIZER_FLAGS="..."`.
# NB: SANITIZER_FLAGS uses `=` (no colon) on purpose — `=` only fills when the var is UNSET, so an
# explicit EMPTY value (`--build-arg SANITIZER_FLAGS=`) is honored and builds with NO sanitizers
# (useful when you want the program's natural crash / full backtrace, not an ASan report). The other
# knobs use `:=` (default on empty too). MAYHEM_JOBS sets build parallelism (falls back to nproc).
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
# DEBUG_FLAGS carries DWARF debug info INDEPENDENTLY of the sanitizer off-switch (so an empty
# SANITIZER_FLAGS still yields DWARF symbols). DWARF MUST be < 4 (Mayhem triage can't read >=4); clang-19's
# plain `-g` emits DWARF-5, so `-gdwarf-3` is explicit. Apply $DEBUG_FLAGS to the fuzz/harness/standalone
# builds (NOT the test/oracle build). Rust/Go carry the same intent via their language flags below.
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=-gdwarf-3}"
: "${GO_DEBUG_FLAGS:=-gcflags=all=-N -l}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
# COVERAGE_FLAGS: empty by default → no effect on the normal oracle build. Set it via the Dockerfile's
# `--build-arg COVERAGE_FLAGS="-fprofile-instr-generate -fcoverage-mapping"` to instrument the TEST
# build for source-coverage measurement (how much of the project the test suite actually exercises —
# a quality signal for the oracle; complements the anti-reward-hack sabotage check). APPEND it to the
# test build's compile+link flags in step 3 (NOT the fuzz build); after `test.sh` runs, merge with
# `llvm-profdata` and report with `llvm-cov`. Empty value is honored (`=`, not `:=`).
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS RUST_DEBUG_FLAGS GO_DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

TARGETS="bin-copy-row-decode text-copy-row-decode text-array-decode text-record-decode bin-array-decode
  text-timestamp-decode text-simple-decode bin-simple-decode coder-encode"

# Out-of-tree build under tmp/ (gitignored upstream, so `git clean -ffdX` removes it all).
B="$SRC/tmp/mayhem-build"
mkdir -p "$B/conf" "$B/fuzz" "$B/test"

# 1) Configure: run upstream's mkmf script out of tree, only for extconf.h (the feature probes
#    against libpq). The objects are compiled below so that they can be instrumented and linked
#    statically into the harness.
(cd "$B/conf" && ruby "$SRC/ext/extconf.rb" > extconf.log 2>&1) || { cat "$B/conf/extconf.log" "$B/conf/mkmf.log" >&2 || true; exit 1; }

rb() { ruby -e "print RbConfig::CONFIG['$1']"; }
INC=(-DRUBY_EXTCONF_H='"extconf.h"' -I"$B/conf" -I"$SRC/ext" -I"$(rb rubyhdrdir)" -I"$(rb rubyarchhdrdir)" -I"$(pg_config --includedir)")
LIBS=(-L"$(rb libdir)" -l"$(rb RUBY_SO_NAME)" -L"$(pg_config --libdir)" -lpq -lm)

# Ruby's conservative GC scans the machine stack for object references; ASan's fake stack frames
# (detect_stack_use_after_return) would hide them, so build without use-after-return instrumentation.
EXTRA_SAN=()
case "$SANITIZER_FLAGS" in *address*) EXTRA_SAN+=(-fsanitize-address-use-after-return=never) ;; esac
# UBSan's `function` check fires on every decode through a record decoder: upstream declares e.g.
# pg_text_dec_record(t_pg_coder *, char *, ...) but calls it through t_pg_coder_dec_func, whose
# second parameter is `const char *`. Benign at the ABI level; only that one check is relaxed.
case "$SANITIZER_FLAGS" in *undefined*|*function*) EXTRA_SAN+=(-fno-sanitize=function) ;; esac

# 2) The extension, instrumented: $SANITIZER_FLAGS + coverage + DWARF 3.
FUZZ_CFLAGS=($SANITIZER_FLAGS "${EXTRA_SAN[@]}" $DEBUG_FLAGS -O1 -fsanitize=fuzzer-no-link)
objs=()
for c in "$SRC"/ext/*.c; do
  o="$B/fuzz/$(basename "${c%.c}").o"
  $CC "${FUZZ_CFLAGS[@]}" "${INC[@]}" -c "$c" -o "$o"
  objs+=("$o")
done
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$B/fuzz/lsan_off.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$B/fuzz/standalone_main.o"

# 3) One harness per target: fuzz_coder.c with that target's Ruby driver (prelude.rb + <target>.rb)
#    embedded as a C byte array, linked once with libFuzzer and once with the standalone driver.
for t in $TARGETS; do
  d="$B/fuzz/$t"; mkdir -p "$d"
  ruby -e 'src = ARGV.map { |f| File.binread(f) }.join("\n")
           puts "static const char FUZZ_SCRIPT[] = {#{(src.bytes + [0]).join(",")}};"' \
    "$SRC/mayhem/harnesses/prelude.rb" "$SRC/mayhem/harnesses/$t.rb" > "$d/fuzz_script.h.new"
  cmp -s "$d/fuzz_script.h.new" "$d/fuzz_script.h" 2>/dev/null && rm "$d/fuzz_script.h.new" || mv "$d/fuzz_script.h.new" "$d/fuzz_script.h"
  $CC "${FUZZ_CFLAGS[@]}" "${INC[@]}" -I"$d" -c "$SRC/mayhem/harnesses/fuzz_coder.c" -o "$d/fuzz_coder.o"
  $CC $SANITIZER_FLAGS "${EXTRA_SAN[@]}" $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$d/fuzz_coder.o" "${objs[@]}" "$B/fuzz/lsan_off.o" \
    "${LIBS[@]}" -o "$SRC/fuzz-$t"
  $CC $SANITIZER_FLAGS "${EXTRA_SAN[@]}" $DEBUG_FLAGS "$B/fuzz/standalone_main.o" "$d/fuzz_coder.o" "${objs[@]}" "$B/fuzz/lsan_off.o" \
    "${LIBS[@]}" -o "$SRC/fuzz-$t-standalone"
done

# 4) The test build, with normal flags: the extension linked into a ruby launcher (spec_ruby.c)
#    that mayhem/test.sh uses to run upstream's rspec suite.
tobjs=()
for c in "$SRC"/ext/*.c; do
  o="$B/test/$(basename "${c%.c}").o"
  $CC -O2 -g -fPIC $COVERAGE_FLAGS "${INC[@]}" -c "$c" -o "$o"
  tobjs+=("$o")
done
$CC -O2 -g $COVERAGE_FLAGS "${INC[@]}" "$SRC/mayhem/spec_ruby.c" "${tobjs[@]}" "${LIBS[@]}" -o "$B/test/spec-ruby"
# extconf.rb's generated pg/postgresql_lib_path.rb, which `make install` puts in RUBYLIBDIR/pg/
# ($INSTALLFILES); test.sh adds $B/test/lib to the load path so lib/pg.rb finds it.
mkdir -p "$B/test/lib/pg"
cp "$B/conf/postgresql_lib_path.rb" "$B/test/lib/pg/postgresql_lib_path.rb"
echo "build.sh: done"
