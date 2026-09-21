# Caching and transfer (Apache)

The target state for cache headers and compression on this host, written to be applied to a
freshly installed Apache rather than to be diffed against a running one.

This is optimisation, not hardening. Nothing here changes what is reachable or who may reach
it; for that see `server-hardening.md`. Both documents write to the same configuration file,
so read section 0 there first.

Host: `polaris.astro.physik.uni-potsdam.de`, `DocumentRoot /mnt/data/www`. The landing page
occupies `/` (`index.html`), `static/` and `news_articles/`; the rules below are scoped to
those and deliberately leave the neighbouring applications alone.

## 0. Prerequisites

```bash
a2enmod headers brotli deflate
```

`mod_expires` is deliberately **not** enabled. See the rule at the end of section 2.

The rules live in `/etc/apache2/conf-available/ost-caching.conf`, enabled with
`a2enconf ost-caching`. A separate file from the hardening rules is fine here: unlike the
hardening sections, nothing in this document depends on merge order.

## 1. The constraint that decides everything

**Asset filenames carry no content hash.** `static/css/base.css` is called that before and
after a deploy, and `deploy.sh` rsyncs over the old file in place. A long cache lifetime on
that name therefore does not mean "this file is cached", it means "visitors keep the previous
release until the cache expires".

Every rule below follows from that one fact. It is also why the usual "cache static assets
for a year" snippet is wrong here: those snippets assume hashed filenames.

The single exception is the fonts. `open-sans-v34-latin-regular.woff2` carries its version in
the name, so a new version arrives under a new name and the cached copy can never be stale.

## 2. Classify by mutability, not by MIME type

MIME type is a poor proxy for how often something changes. It groups `base.css`, which
changes on every deploy, with `open-sans-v34-latin-regular.woff2`, which cannot change at
all without becoming a different file. Sort by mutability instead:

**A — versioned by filename.** The four self-hosted fonts. Freeze them: a year, and
`immutable`.

**B — written once, name could be reused.** Article media under `news_articles/images/`
belongs to one article and is not edited after publication. Site chrome under
`static/images/` changes rarely, but its names are generic and *will* be reused when the
picture changes. Long lifetimes, but never `immutable`.

**C — changes on every deploy.** `base.css`, `base.js`, `index.html`, the article pages and
`articles.json`. These must revalidate.

```apache
# --- A: versioned by name -------------------------------------------------
<Directory /mnt/data/www/static/fonts>
    <FilesMatch "-v[0-9]+-.*\.woff2$">
        Header set Cache-Control "public, max-age=31536000, immutable"
    </FilesMatch>
</Directory>

# --- B: write-once media --------------------------------------------------
<Directory /mnt/data/www/news_articles/images>
    <FilesMatch "\.(?i:jpe?g|png|webp|gif|mp4|webm)$">
        Header set Cache-Control "public, max-age=31536000"
    </FilesMatch>
</Directory>

<Directory /mnt/data/www/static/images>
    <FilesMatch "\.(?i:jpe?g|png|webp|svg)$">
        Header set Cache-Control "public, max-age=604800"
    </FilesMatch>
</Directory>

# --- C: deploy-coupled, always revalidate ---------------------------------
<LocationMatch "^/(index\.html)?$|^/static/(css|js)/|^/news_articles/[^/]*\.html$">
    Header set Cache-Control "no-cache"
</LocationMatch>

<Directory /mnt/data/www/news_articles>
    <Files "articles.json">
        Header set Cache-Control "no-cache"
    </Files>
</Directory>
```

An unversioned font, or any file the patterns miss, ends up with no `Cache-Control` at all.
That is the safe direction to fail in: the browser falls back to heuristic freshness and
revalidates against the `ETag`.

> **`immutable` only on names that cannot be reused.** It suppresses revalidation *even on an
> explicit reload*, so it is the one directive a user cannot escape from. On a filename like
> `archive.jpg`, which keeps its name when the picture behind it is replaced, that turns a
> content update into an invisible one for the length of the `max-age`. Version in the name,
> or no `immutable`.

> **Use one mechanism, not two.** Everything above is `Header set Cache-Control`, and
> `mod_expires` stays disabled. With both active, `mod_expires` emits `Cache-Control:
> max-age=N` alongside `Expires`, and a later `Header set` replaces the `Cache-Control` while
> leaving `Expires` untouched — a response whose two freshness statements disagree. Symptom
> to recognise: a `Cache-Control` with no `max-age` next to an `Expires` header that has one.

`no-cache` does not mean "do not cache". It means "store it, but revalidate before every
reuse": the browser keeps the file and sends `If-None-Match`, and Apache answers `304 Not
Modified` with headers only. For a stylesheet of a few kilobytes that trades the body for
roughly 150 bytes, on a connection HTTP/2 has already opened. The directive that forbids
storing is `no-store`, and it is wanted nowhere on this site.

## 3. Compression

Compress text, leave already-compressed formats alone:

```apache
AddOutputFilterByType BROTLI_COMPRESS;DEFLATE \
    text/html text/plain text/xml text/css \
    text/javascript application/javascript \
    application/json application/xml image/svg+xml
```

The argument is a filter chain, and it reads as a preference order: Brotli is offered first,
gzip second. Each filter removes itself when the client's `Accept-Encoding` does not name its
encoding, and again when the response already carries a `Content-Encoding` other than
`identity` — so the second filter never re-compresses what the first one produced. Keep both
in this single directive rather than writing a second `AddOutputFilterByType` for the same
media types.

**Both JavaScript spellings.** Apache serves `.js` as `text/javascript`; older `mime.types`
emitted `application/javascript`, and an update can move it back. A configuration that lists
only one of them silently stops compressing JavaScript the day the mapping changes — the
response simply arrives uncompressed, with no error anywhere.

Do not add `woff2`, `jpeg`, `png`, `webp` or `mp4`. Those formats are already compressed;
running them through Brotli spends CPU to make them marginally larger.

`Vary: Accept-Encoding` is added automatically wherever these filters apply. It is what stops
an intermediate cache from handing a Brotli body to a client that asked for gzip, so do not
strip it.

## 4. Video

Leave `Accept-Ranges: bytes` enabled — it is Apache's default and it is what lets a viewer
seek inside an article video without downloading the tail. Keep `mp4` out of the compression
filter, and keep `news_articles/images/` excluded from the deploy script's `--delete` (it
already is; the images are not in git).

This is the one place where the class B lifetime genuinely pays. The article videos run to
about two megabytes each, against a few kilobytes for all of the CSS and JavaScript together.

## 5. Hashed filenames: why not here

The textbook fix for class C is to emit `base.7f3a9c1.css` at deploy time and rewrite the
references, which would move CSS and JavaScript into class A and allow a one-year freeze.

It is not worth doing on this site. Class C amounts to a few kilobytes compressed, so
freezing it saves a returning visitor almost nothing, while revalidation already costs only
a pair of 304s. Against that stands a deploy script that would have to rewrite references
inside HTML and CSS, and a pre-flight gate (`docs/deployment.md`) that checks every local
reference resolves and would have to learn about hashed names too.

Revisit this only if a large JavaScript dependency is ever added. The fonts, which are the
bulk of the static payload, already carry versions in their names.

## 6. Verification

```bash
./scripts/verify-caching.sh                       # everything
./scripts/verify-caching.sh --only conditional    # one group
./scripts/verify-caching.sh --delay 2 --quiet
```

The groups are `frozen`, `media`, `revalidate`, `compression` and `conditional`, mapping onto
the classes in section 2 plus the two transport checks. `--help` lists them. Every check is a
plain HTTP request, so the script writes nothing.

`conditional` is the group worth re-running after any change. It sends the `ETag` back as
`If-None-Match` and requires a `304`; if it reports `200`, revalidation is not working and
class C is downloading in full on every page view — which is the failure mode that makes
`no-cache` expensive instead of nearly free.

`verify-hardening.sh` deliberately covers none of this. A wrong cache header is a performance
bug, not a security one, and mixing the two would make a failing run ambiguous.
