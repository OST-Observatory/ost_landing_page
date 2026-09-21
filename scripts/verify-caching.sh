#!/usr/bin/env bash
#
# Verify the caching and transfer policy from docs/caching.md against a running
# host.
#
# Read-only: every check is a plain HTTP request, so nothing is written and the
# script is safe to run at any time. It exits non-zero if any check fails.
#
# This is the performance counterpart to verify-hardening.sh and is kept
# separate on purpose: a wrong cache header is a performance bug, not a
# security one, and mixing the two would make a failing run ambiguous.
#
# NOTE ON RATE LIMITING. A full run makes around 40 requests. fail2ban,
# mod_evasive or a campus firewall can read a burst like that as scanning and
# block the source address mid-run, which surfaces as checks failing with code
# 000 rather than as a result. Hence --delay.
#
# Usage:
#   ./scripts/verify-caching.sh
#   ./scripts/verify-caching.sh --only compression --only conditional
#   ./scripts/verify-caching.sh --base-url https://staging.example.org --quiet
#
# Options:
#   --base-url URL   Host to check (default: https://polaris.astro.physik.uni-potsdam.de).
#   --only GROUP     Run one group only. Repeatable. Groups: frozen, media,
#                    revalidate, compression, conditional.
#   --timeout SEC    Per-request timeout in seconds (default: 15).
#   --delay SEC      Pause between requests (default: 0.5).
#   -q, --quiet      Print failures only.
#   -h, --help       Show this help.

set -euo pipefail

BASE_URL="https://polaris.astro.physik.uni-potsdam.de"
TIMEOUT=15
DELAY=0.5
QUIET=0
ONLY=()

die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { [ "$QUIET" -eq 1 ] || printf '\n==> %s\n' "$*"; }

usage() { sed -n '3,31p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --base-url) BASE_URL="${2:?--base-url needs a URL}"; shift ;;
    --only)     ONLY+=("${2:?--only needs a group name}"); shift ;;
    --timeout)  TIMEOUT="${2:?--timeout needs a number}"; shift ;;
    --delay)    DELAY="${2:?--delay needs a number}"; shift ;;
    -q|--quiet) QUIET=1 ;;
    -h|--help)  usage ;;
    *)          die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

command -v curl >/dev/null || die "curl is required"
BASE_URL="${BASE_URL%/}"

if [ -t 1 ]; then
  RED=$'\033[31m'; GREEN=$'\033[32m'; OFF=$'\033[0m'
else
  RED=""; GREEN=""; OFF=""
fi

PASSED=0
FAILED=0
pass() { PASSED=$((PASSED + 1)); [ "$QUIET" -eq 1 ] || printf '  %sok  %s %s\n' "$GREEN" "$OFF" "$*"; }
fail() { FAILED=$((FAILED + 1));                      printf '  %sFAIL%s %s\n' "$RED"   "$OFF" "$*"; }

# ---------------------------------------------------------------------------
# HTTP helpers. All of them swallow curl failures, so an unreachable host shows
# up as failing checks rather than as an aborted script.
# ---------------------------------------------------------------------------

throttle() { [ "$DELAY" = "0" ] || sleep "$DELAY"; }

# header_value <path> <header-name-lowercase>
header_value() {
  throttle
  curl -sI --max-time "$TIMEOUT" -H 'Accept-Encoding: gzip, br' "$BASE_URL/$1" 2>/dev/null \
    | sed -n "s/^$2: //Ip" | tr -d '\r' | head -1 || true
}

# check_cc <path> <must-contain regex|-> <must-NOT-contain regex|-> <label>
check_cc() {
  local path="$1" want="$2" unwanted="$3" label="$4" cc
  cc="$(header_value "$path" 'cache-control')"

  if [ -z "$cc" ]; then
    fail "$(printf '%-44s no Cache-Control at all' "$label")"
    return
  fi
  if [ "$want" != "-" ] && ! printf '%s' "$cc" | grep -qE "$want"; then
    fail "$(printf '%-44s %s  (missing %s)' "$label" "$cc" "$want")"
    return
  fi
  if [ "$unwanted" != "-" ] && printf '%s' "$cc" | grep -qE "$unwanted"; then
    fail "$(printf '%-44s %s  (must not contain %s)' "$label" "$cc" "$unwanted")"
    return
  fi
  pass "$(printf '%-44s %s' "$label" "$cc")"
}

# check_encoding <path> <yes|no> <label>
check_encoding() {
  local path="$1" want="$2" label="$3" enc
  enc="$(header_value "$path" 'content-encoding')"
  case "$want" in
    yes)
      if [ -n "$enc" ]; then pass "$(printf '%-44s %s' "$label" "$enc")"
      else                   fail "$(printf '%-44s NOT COMPRESSED' "$label")"; fi ;;
    no)
      if [ -z "$enc" ]; then pass "$(printf '%-44s not re-compressed' "$label")"
      else                   fail "$(printf '%-44s %s  (already a compressed format)' "$label" "$enc")"; fi ;;
  esac
}

# ---------------------------------------------------------------------------
# Groups. Paths mirror the three classes in docs/caching.md section 1.
# ---------------------------------------------------------------------------

group_frozen() {
  info "class A, versioned by filename — expect a year and immutable"
  local p
  for p in static/fonts/open-sans-v34-latin-regular.woff2 \
           static/fonts/open-sans-v34-latin-700.woff2 \
           static/fonts/lato-v24-latin-regular.woff2 \
           static/fonts/lato-v24-latin-700.woff2; do
    check_cc "$p" 'max-age=31536000' '-' "/$p"
    check_cc "$p" 'immutable' '-' "  ^ immutable"
  done
}

group_media() {
  info "class B, write-once media — expect max-age, and never immutable"
  local p
  for p in static/images/archive.jpg static/images/inventory.jpg \
           static/images/outreach.jpg \
           news_articles/images/Comet_20230131.mp4 \
           news_articles/images/blink_cross_fade.mp4; do
    check_cc "$p" 'max-age=[0-9]+' 'immutable' "/$p"
  done
}

group_revalidate() {
  info "class C, deploy-coupled — expect no-cache"
  local p
  for p in "" static/css/base.css static/js/base.js \
           news_articles/articles.json news_articles/index.html \
           news_articles/SN2023ixf.html; do
    check_cc "$p" 'no-cache' 'immutable' "/$p"
  done
}

group_compression() {
  info "compression — text formats must be encoded"
  local p
  for p in "" static/css/base.css static/js/base.js \
           news_articles/articles.json news_articles/index.html; do
    check_encoding "$p" yes "/$p"
  done

  info "... and already-compressed formats must not be"
  for p in static/fonts/open-sans-v34-latin-regular.woff2 \
           static/images/archive.jpg \
           news_articles/images/Comet_20230131.mp4; do
    check_encoding "$p" no "/$p"
  done
}

group_conditional() {
  info "conditional requests — a matching ETag must return 304, not 200"
  local p etag code
  for p in static/css/base.css static/js/base.js news_articles/articles.json \
           static/images/archive.jpg; do
    etag="$(header_value "$p" 'etag')"
    if [ -z "$etag" ]; then
      fail "$(printf '%-44s no ETag — cannot revalidate' "/$p")"
      continue
    fi
    throttle
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" \
              -H "If-None-Match: $etag" "$BASE_URL/$p" 2>/dev/null)" || code="000"
    if [ "$code" = "304" ]; then
      pass "$(printf '%-44s 304' "/$p")"
    else
      fail "$(printf '%-44s %s  expected 304 — full body on every view' "/$p" "$code")"
    fi
  done
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

ALL=(frozen media revalidate compression conditional)
if [ "${#ONLY[@]}" -eq 0 ]; then
  ONLY=("${ALL[@]}")
fi

for g in "${ONLY[@]}"; do
  case " ${ALL[*]} " in
    *" $g "*) "group_$g" ;;
    *)        die "unknown group: $g (known: ${ALL[*]})" ;;
  esac
done

printf '\n%s: %d passed, %d failed\n' "$BASE_URL" "$PASSED" "$FAILED"
[ "$FAILED" -eq 0 ]
