#!/usr/bin/env bash
#
# Verify the Apache hardening rules from docs/server-hardening.md against a
# running host.
#
# Read-only: every check is a plain HTTP request. Nothing is written, so this
# is safe to run at any time, from anywhere, including a workstation. Unlike
# the section-5 snippets it came from, this judges each result instead of
# printing a status code for you to interpret, and it exits non-zero if any
# check fails — so it can gate a deployment or run from cron.
#
# It does NOT cover the two root-only checks (`apache2ctl configtest` and
# `certbot renew --dry-run`); those must run on the host and are printed as a
# reminder at the end.
#
# NOTE ON RATE LIMITING. A full run makes around 45 requests, most of which
# deliberately provoke 403 and 404 responses. To fail2ban, mod_evasive or a
# campus firewall that is exactly the signature of a vulnerability scanner,
# and the host may block the source address mid-run. Hence --delay, and hence
# the advice to run this from the host itself (against localhost, or with the
# public name) rather than repeatedly from a workstation.
#
# Usage:
#   ./scripts/verify-hardening.sh
#   ./scripts/verify-hardening.sh --only headers --only nextcloud
#   ./scripts/verify-hardening.sh --base-url https://staging.example.org --quiet
#
# Options:
#   --base-url URL   Host to check (default: https://polaris.astro.physik.uni-potsdam.de).
#   --only GROUP     Run one group only. Repeatable. Groups: headers, metadata,
#                    site, media, neighbours, nextcloud, discovery.
#   --timeout SEC    Per-request timeout in seconds (default: 15).
#   --delay SEC      Pause between requests (default: 0.5). See the note below.
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

usage() { sed -n '3,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

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
  RED=$'\033[31m'; GREEN=$'\033[32m'; DIM=$'\033[2m'; OFF=$'\033[0m'
else
  RED=""; GREEN=""; DIM=""; OFF=""
fi

PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); [ "$QUIET" -eq 1 ] || printf '  %sok  %s %s\n' "$GREEN" "$OFF" "$*"; }
fail() { FAILED=$((FAILED + 1));                      printf '  %sFAIL%s %s\n' "$RED"   "$OFF" "$*"; }

# ---------------------------------------------------------------------------
# HTTP helpers. Both swallow curl failures: an unreachable host must show up
# as a failed check, not as an aborted script.
# ---------------------------------------------------------------------------

# Pause between requests so a full run does not look like a port scan.
throttle() { [ "$DELAY" = "0" ] || sleep "$DELAY"; }

http_code() {
  local out
  throttle
  out="$(curl -s -o /dev/null -w '%{http_code}' --max-time "$TIMEOUT" "$1" 2>/dev/null)" || out="000"
  printf '%s' "$out"
}

http_headers() { throttle; curl -sI --max-time "$TIMEOUT" "$1" 2>/dev/null || true; }
http_body()    { throttle; curl -s  --max-time "$TIMEOUT" "$1" 2>/dev/null || true; }

# check_code <path> <extended-regex of acceptable codes> [label]
check_code() {
  local path="$1" want="$2" label="${3:-/$1}" code
  code="$(http_code "$BASE_URL/$path")"
  if printf '%s' "$code" | grep -qE "^($want)$"; then
    pass "$(printf '%-42s %s' "$label" "$code")"
  else
    fail "$(printf '%-42s %s  expected %s' "$label" "$code" "$want")"
  fi
}

# ---------------------------------------------------------------------------
# Groups
# ---------------------------------------------------------------------------

group_headers() {
  info "security headers on / (section 4)"
  local hdr
  hdr="$(http_headers "$BASE_URL/")"

  if [ -z "$hdr" ]; then
    fail "no response from $BASE_URL/ — every header check below is meaningless"
    return
  fi

  # The colon trap from section 4: a header name ending in ':' produces '::'
  # in the raw response. Browsers ignore such a header silently.
  if printf '%s' "$hdr" | grep -qE '^[A-Za-z0-9-]+::'; then
    fail "a header name ends in a colon — browsers ignore it silently"
  else
    pass "no header name ends in a colon"
  fi

  local h
  for h in content-security-policy cross-origin-opener-policy \
           cross-origin-resource-policy strict-transport-security \
           x-content-type-options x-frame-options referrer-policy; do
    if printf '%s' "$hdr" | grep -qi "^$h\(-report-only\)\?:"; then
      pass "$h present"
    else
      fail "$h missing"
    fi
  done

  # Every directive the landing page actually depends on. media-src is the one
  # that is easy to drop as apparent dead weight; it carries the article videos.
  local csp d
  csp="$(printf '%s' "$hdr" | grep -i '^content-security-policy' || true)"
  if [ -n "$csp" ]; then
    for d in "default-src 'none'" "script-src 'self'" "style-src 'self'" \
             "img-src 'self'" "media-src 'self'" "font-src 'self'" \
             "connect-src 'self'" "base-uri 'none'" "form-action 'none'" \
             "frame-ancestors 'none'"; do
      if printf '%s' "$csp" | grep -qF "$d"; then
        pass "CSP has $d"
      else
        fail "CSP is missing $d"
      fi
    done
    # Case-insensitive: the header name is spelled Content-Security-Policy-Report-Only.
    if printf '%s' "$csp" | grep -qi 'report-only'; then
      [ "$QUIET" -eq 1 ] || printf '  %s--   still in Report-Only mode \u2014 nothing is enforced yet%s\n' "$DIM" "$OFF"
    fi
  fi
}

group_metadata() {
  info "repository metadata and scratch paths (section 1) — expect 403 or 404"
  local p
  for p in .git/HEAD .gitignore README.md LICENSE SECURITY_AUDIT.md \
           .idea/workspace.xml news_articles/.git/HEAD news_articles/README.md \
           landing_page_test/ possible_thumbnails/ static/ news_articles/images/; do
    check_code "$p" '403|404'
  done
}

group_site() {
  info "the site itself — expect 200"
  local p
  for p in "" static/about.html static/impressum.html static/datenschutz.html \
           static/css/base.css static/js/base.js \
           news_articles/index.html news_articles/articles.json \
           static/images/archive.jpg static/images/inventory.jpg \
           static/images/outreach.jpg; do
    check_code "$p" '200'
  done
}

group_media() {
  info "article videos — expect 200 (these are what media-src covers)"
  local p
  for p in news_articles/SN2023ixf.html news_articles/C_2022_E3_ZTF.html \
           news_articles/images/blink_cross_fade.mp4 \
           news_articles/images/Comet_20230131.mp4; do
    check_code "$p" '200'
  done
}

group_neighbours() {
  info "neighbouring services — our CSP must not reach them (section 4)"
  # Testing for "any CSP header" here gives false positives: Nextcloud ships its
  # own policy, and the Django apps use django-csp. What must not appear is OUR
  # policy, and the landing page is the only one that starts from
  # `default-src 'none'` — every neighbour uses `'self'`. That is the fingerprint.
  local p code csp
  for p in wiki/ nextcloud/ gallery/ inventory/ ost_events/ data_archive/ \
           weather_station/; do
    code="$(http_code "$BASE_URL/$p")"
    csp="$(http_headers "$BASE_URL/$p" | grep -i '^content-security-policy' || true)"
    if [ "$code" = "000" ]; then
      fail "$(printf '%-42s unreachable' "/$p")"
    elif printf '%s' "$csp" | grep -qF "default-src 'none'"; then
      fail "$(printf '%-42s %s  OUR policy leaked into this path' "/$p" "$code")"
    elif [ -n "$csp" ]; then
      pass "$(printf '%-42s %s  own policy, not ours' "/$p" "$code")"
    else
      pass "$(printf '%-42s %s  no CSP' "/$p" "$code")"
    fi
  done
}

group_nextcloud() {
  info "Nextcloud must work (section 2)"
  check_code "nextcloud/" '200|302' "/nextcloud/"
  if http_body "$BASE_URL/nextcloud/status.php" | grep -q '"installed":true'; then
    pass "status.php reports installed:true"
  else
    fail "status.php did not report installed:true — PHP may still be denied"
  fi

  info "... without leaking anything — expect 403 or 404"
  local p
  for p in nextcloud/.htaccess nextcloud/.user.ini nextcloud/config/config.php \
           nextcloud/data/ nextcloud/db_structure.xml; do
    check_code "$p" '403|404'
  done
}

group_discovery() {
  # Clients probe the HOST ROOT, not the subdirectory, so these four are the
  # ones that matter and they map 1:1 onto the Redirect block in section 1.
  # /nextcloud/.well-known/* is Nextcloud-internal and deliberately not checked.
  info "CalDAV/CardDAV discovery (section 1) — expect 301 or 302, never 403 or 404"
  local p
  for p in .well-known/caldav .well-known/carddav .well-known/webfinger \
           .well-known/nodeinfo; do
    check_code "$p" '301|302'
  done
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

ALL=(headers metadata site media neighbours nextcloud discovery)
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

if [ "$FAILED" -eq 0 ] && [ "$QUIET" -eq 0 ]; then
  cat <<'REMINDER'

Not covered here — run these on the host, as root:
  apache2ctl configtest
  certbot renew --dry-run    # inserts the challenge config, reloads, removes it
REMINDER
fi

[ "$FAILED" -eq 0 ]
