# Deployment

The landing page is deployed with `scripts/deploy.sh`, which runs **on the server** from a
git checkout kept **outside** the web root.

## Layout on the server

```
/mnt/data/src/ost_landing_page/   git checkout — never served by Apache
/mnt/data/src/ost_news/           git checkout — never served by Apache
/mnt/data/www/                    DocumentRoot
├── index.html                    from ost_landing_page
├── static/                       from ost_landing_page
└── news_articles/                from ost_news
    └── images/                   synced separately (not in git)
```

The checkouts must stay outside `/mnt/data/www`. If they were inside it, `.git/`,
`README.md` and every other repository file would be reachable over HTTP. The deploy script
refuses to run in that situation.

## Deploying

```bash
cd /mnt/data/src/ost_landing_page
./scripts/deploy.sh                 # dry run — shows exactly what would change
./scripts/deploy.sh --apply         # write to the web root
./scripts/deploy.sh --apply --verify
```

Always read the dry run before applying. Articles are deployed the same way:

```bash
cd /mnt/data/src/ost_news
./scripts/deploy.sh --apply
```

Useful options: `--webroot DIR`, `--ref REF`, `--no-pull`. Run `--help` for the full list.

## What the script does

1. Refuses to run unless the working tree is clean, the branch is `main`, and the checkout
   is outside the web root.
2. Fast-forwards to `origin/main`.
3. Builds the payload with `git archive`, **not** from the working directory. Only committed
   files can be published — untracked scratch files cannot leak into the web root even if
   `.gitignore` is wrong.
4. Removes files that are tracked but not meant for production: `README.md`, `LICENSE`,
   `.gitignore`, `docs/`, `scripts/`.
5. Runs two pre-flight gates and aborts before writing anything if either fails (see below).
6. Syncs `static/` with `--delete` and copies `index.html`.

The result in the web root is exactly `index.html` plus `static/`.

### `--delete` and the web root

`--delete` is used **only** inside `static/`, because that directory belongs entirely to this
repository. It must never be used against `/mnt/data/www` itself: `gallery/`, `ftp/`,
`images/`, `news_articles/` and other services live there and would be erased.

In the `ost_news` script `--delete` does apply to `news_articles/`, which the repository owns
in full. `images/` is excluded there and is therefore protected — rsync does not delete
excluded paths.

## Pre-flight gates

**Asset references.** Every local `src=`, `href=` and `url()` reference resolving into
`static/` must exist in the payload. This catches the case where a file is referenced by
`index.html` but was never committed — which is easy to cause with an unanchored
`.gitignore` pattern (see below).

**Image metadata.** If `exiftool` is installed, the deploy aborts when a shipped image still
carries GPS coordinates, a camera model or a serial number.

For `ost_news` the second gate is replaced by a validation of `articles.json` against the
same rules `static/js/base.js` applies on the landing page: filename pattern, `YYYY-MM-DD`
date, thumbnail path, and the existence of the referenced article file. A typo is caught at
deploy time instead of silently dropping an article from the news banner.

## Images

`news_articles/images/` is not in git (the files are too large) and is synced separately from
a developer machine. Generate thumbnails locally with `ost_news/scripts/generate-thumbnails.sh`.

Never run image tools on the production server.

## Conventions worth keeping

- **Anchor every `.gitignore` pattern with a leading `/`.** An unanchored pattern such as
  `images` matches at every level and silently excluded `static/images/` from this repository
  until 2026-09. Three images referenced by `index.html` had never been committed as a result.
- **Strip image metadata before committing:** `exiftool -all= -overwrite_original file.jpg`.
- **Keep scratch files outside the project folder.** `.gitignore` protects against git, not
  against `scp -r` or `rsync -a ./`.
- **The landing page runs under a strict Content-Security-Policy.** No inline `<script>`, no
  inline `<style>`, no `style=` attributes, no external resources. See
  [server-hardening.md](server-hardening.md).

HTTP cache header examples: [ost_news/docs/deploy-cache.md](../../ost_news/docs/deploy-cache.md).
