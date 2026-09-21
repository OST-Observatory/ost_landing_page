#!/usr/bin/env bash
#
# Deploy the OST landing page from a git checkout to the web root.
#
# This script runs ON THE SERVER, from a checkout that lives OUTSIDE the web
# root (see docs/deployment.md). It never copies the working directory: the
# payload is built with `git archive`, so only committed files can ever be
# published. Untracked scratch files cannot leak into the web root even if
# somebody forgets to maintain .gitignore.
#
# Usage:
#   ./scripts/deploy.sh                 # dry run (default) — shows what would change
#   ./scripts/deploy.sh --apply         # actually write to the web root
#   ./scripts/deploy.sh --apply --verify
#
# Options:
#   --apply          Perform the deployment. Without it, rsync runs with -n.
#   --webroot DIR    Target web root (default: /mnt/data/www).
#   --ref REF        Deploy this git ref instead of the updated branch.
#   --no-pull        Skip `git fetch` / fast-forward; deploy the current HEAD.
#   --verify         Run HTTP checks against --base-url after deploying.
#   --base-url URL   Base URL for --verify (default: https://polaris.astro.physik.uni-potsdam.de).
#   -h, --help       Show this help.

set -euo pipefail

WEBROOT="/mnt/data/www"
BASE_URL="https://polaris.astro.physik.uni-potsdam.de"
APPLY=0
DO_PULL=1
DO_VERIFY=0
REF=""

# Files that are tracked in git but must never reach the web root.
PRUNE=(
  "README.md"
  "LICENSE"
  ".gitignore"
  "docs"
  "scripts"
)

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '==> %s\n' "$*"; }

usage() { sed -n '3,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --apply)    APPLY=1 ;;
    --webroot)  WEBROOT="${2:?--webroot needs a directory}"; shift ;;
    --ref)      REF="${2:?--ref needs a git ref}"; shift ;;
    --no-pull)  DO_PULL=0 ;;
    --verify)   DO_VERIFY=1 ;;
    --base-url) BASE_URL="${2:?--base-url needs a URL}"; shift ;;
    -h|--help)  usage ;;
    *)          die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Safety checks
# ---------------------------------------------------------------------------

command -v git   >/dev/null || die "git is required"
command -v rsync >/dev/null || die "rsync is required"

REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git checkout"
cd "$REPO"

[ -d "$WEBROOT" ] || die "web root does not exist: $WEBROOT"

# Resolve both paths so the containment check cannot be fooled by symlinks.
REPO_REAL="$(cd "$REPO" && pwd -P)"
WEBROOT_REAL="$(cd "$WEBROOT" && pwd -P)"

# The whole point of this script is that the checkout is not served by Apache.
# If it is, deploying would leave .git/ reachable over HTTP.
case "$REPO_REAL/" in
  "$WEBROOT_REAL"/*)
    die "the checkout ($REPO_REAL) is inside the web root ($WEBROOT_REAL).
       Move it out (e.g. to /mnt/data/src/) before deploying — see docs/deployment.md."
    ;;
esac

if [ -n "$(git status --porcelain)" ]; then
  git status --short >&2
  die "working tree is not clean; commit or stash before deploying"
fi

# ---------------------------------------------------------------------------
# Update the checkout
# ---------------------------------------------------------------------------

if [ -n "$REF" ]; then
  DEPLOY_REF="$REF"
elif [ "$DO_PULL" -eq 1 ]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  [ "$BRANCH" = "main" ] || die "on branch '$BRANCH'; deploy from 'main' or pass --ref"
  info "fetching origin"
  git fetch --quiet origin
  info "fast-forwarding $BRANCH to origin/$BRANCH"
  git merge --ff-only "origin/$BRANCH"
  DEPLOY_REF="HEAD"
else
  DEPLOY_REF="HEAD"
fi

info "deploying $(git rev-parse --short "$DEPLOY_REF") ($(git log -1 --format=%s "$DEPLOY_REF"))"

# ---------------------------------------------------------------------------
# Build the payload from git, never from the working directory
# ---------------------------------------------------------------------------

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

git archive --format=tar "$DEPLOY_REF" | tar -x -C "$STAGE"

for item in "${PRUNE[@]}"; do
  rm -rf "${STAGE:?}/$item"
done

[ -f "$STAGE/index.html" ] || die "index.html missing from the payload"
[ -d "$STAGE/static" ]     || die "static/ missing from the payload"

# ---------------------------------------------------------------------------
# Pre-flight gate 1: every local reference under static/ must exist
#
# Catches the class of bug where a file is referenced by index.html but was
# never committed (e.g. because an unanchored .gitignore pattern hid it).
# References to paths provided by other deployments (news_articles/, wiki/,
# gallery/, ...) and to external URLs are skipped on purpose.
# ---------------------------------------------------------------------------

normalize_path() {
  local path="$1" part out=() IFS='/'
  for part in $path; do
    case "$part" in
      ''|'.') ;;
      '..') [ "${#out[@]}" -gt 0 ] && unset 'out[${#out[@]}-1]' ;;
      *) out+=("$part") ;;
    esac
  done
  printf '%s' "${out[*]-}"
}

info "checking local asset references"
missing=0
while IFS= read -r file; do
  dir="$(dirname "${file#"$STAGE"/}")"
  [ "$dir" = "." ] && dir=""

  # src="...", href="..." and url(...) in one pass; quotes stripped afterwards.
  while IFS= read -r ref; do
    case "$ref" in
      ''|http://*|https://*|//*|data:*|mailto:*|\#*) continue ;;
    esac
    ref="${ref%%\#*}"
    ref="${ref%%\?*}"
    [ -n "$ref" ] || continue

    if [ "${ref#/}" != "$ref" ]; then
      target="$(normalize_path "$ref")"          # site-absolute
    else
      target="$(normalize_path "$dir/$ref")"     # relative to the file
    fi

    # Only assets we ship ourselves are our responsibility.
    case "$target" in
      static/*) ;;
      *) continue ;;
    esac

    if [ ! -e "$STAGE/$target" ]; then
      printf '  MISSING  %-34s referenced by %s\n' "$target" "${file#"$STAGE"/}" >&2
      missing=$((missing + 1))
    fi
  done < <(
    # Two separate patterns on purpose: combining them needs a backreference to
    # match the quote style of url(...), which grep -E does not support and
    # which makes the whole expression match nothing at all.
    grep -ohE '(src|href)="[^"]*"' "$file" 2>/dev/null \
      | sed -E 's/^(src|href)="//; s/"$//'
    grep -ohE 'url\([^)]*\)' "$file" 2>/dev/null \
      | sed -E 's/^url\(//; s/\)$//; s/^["'"'"']//; s/["'"'"']$//'
  )
done < <(find "$STAGE" -type f \( -name '*.html' -o -name '*.css' \))

[ "$missing" -eq 0 ] || die "$missing referenced file(s) missing from the payload — nothing was deployed"

# ---------------------------------------------------------------------------
# Pre-flight gate 2: no camera/location metadata in shipped images
# ---------------------------------------------------------------------------

if command -v exiftool >/dev/null; then
  info "checking image metadata"
  if exiftool -q -q -r -if '$GPSLatitude or $Model or $SerialNumber' \
       -p '  $directory/$filename' "$STAGE/static" 2>/dev/null | grep .; then
    die "image(s) above still carry GPS/camera metadata; strip with
       exiftool -all= -overwrite_original <file> and commit the result"
  fi
else
  printf 'note: exiftool not installed — skipping image metadata check\n' >&2
fi

# ---------------------------------------------------------------------------
# Publish
# ---------------------------------------------------------------------------

RSYNC_OPTS=(-rlptD --chmod=D755,F644 --itemize-changes)
[ "$APPLY" -eq 1 ] || RSYNC_OPTS+=(--dry-run)

# static/ belongs entirely to this repository, so --delete is safe there and
# removes files that were dropped from the repo.
info "syncing static/"
rsync "${RSYNC_OPTS[@]}" --delete "$STAGE/static/" "$WEBROOT/static/"

# NEVER use --delete against $WEBROOT itself: gallery/, ftp/, images/,
# news_articles/ and the other services live there and would be erased.
info "syncing index.html"
rsync "${RSYNC_OPTS[@]}" "$STAGE/index.html" "$WEBROOT/"

if [ "$APPLY" -eq 0 ]; then
  printf '\n(dry run — nothing was written; re-run with --apply)\n'
  exit 0
fi

# ---------------------------------------------------------------------------
# Optional post-deploy verification
# ---------------------------------------------------------------------------

if [ "$DO_VERIFY" -eq 1 ]; then
  command -v curl >/dev/null || die "curl is required for --verify"

  printf '\n==> pages and assets (expect 200)\n'
  for p in "" static/about.html static/impressum.html static/datenschutz.html \
           static/css/base.css static/js/base.js; do
    printf '  %-34s %s\n' "/$p" \
      "$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/$p")"
  done

  printf '\n==> repository metadata (expect 403 or 404)\n'
  for p in .git/HEAD .gitignore README.md LICENSE SECURITY_AUDIT.md; do
    printf '  %-34s %s\n' "/$p" \
      "$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/$p")"
  done
fi

info "done"
