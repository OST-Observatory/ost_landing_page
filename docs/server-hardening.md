# Server hardening (Apache)

The target state for this host's Apache configuration, written to be applied to a freshly
installed Apache. Each section describes what the finished configuration contains and why,
not how to get there from some particular starting point.

Host: `polaris.astro.physik.uni-potsdam.de`, `DocumentRoot /mnt/data/www`.

One `DocumentRoot` carries the landing page, a wiki, a Nextcloud instance at
`/mnt/data/www/nextcloud`, several Django applications, a PHP event calendar and some legacy
directories. They also share one browser origin, which section 6 returns to. Rules are
therefore scoped deliberately throughout: anything applied too broadly breaks a neighbour.

## 0. Where the configuration lives

```bash
a2enmod headers alias rewrite
# place the rules in /etc/apache2/conf-available/ost-hardening.conf
a2enconf ost-hardening
apache2ctl configtest && systemctl reload apache2
```

Sections 1 to 4 go in that **one file, in that order**. Three reasons, each of which has bitten
someone:

**Not in the virtual host.** Certbot is configured with `authenticator = apache`, so it edits
the virtual host on every renewal: it inserts a challenge configuration, reloads, and removes
it again. Rules that live there are exposed to a rewrite that announces itself nowhere.

**Not in an `.htaccess`.** Section 1 sets `AllowOverride None` on the web root, which makes
every `.htaccess` below it inert. A rule placed there does not fail loudly; it simply never
runs, and the file keeps sitting on disk looking authoritative.

**One file, because section 2 depends on the order.** See the note at the end of section 2.
Split across `conf-available/` files, the alphabetical include order silently decides whether
PHP works.

Note that `conf-enabled/` is included *before* `sites-enabled/`, so anything in the virtual
host still wins over these rules.

## 1. Web root defaults

```apache
<Directory /mnt/data/www>
    Options -Indexes +FollowSymLinks
    AllowOverride None
    Require all granted

    # Hidden files: .git, .gitignore, .htaccess, .idea, ...
    <FilesMatch "^\.">
        Require all denied
    </FilesMatch>

    # Repository metadata, in case a checkout is ever unpacked here by hand.
    <FilesMatch "^(README\.md|TODO\.md|LICENSE|SECURITY_AUDIT\.md|.*\.code-workspace)$">
        Require all denied
    </FilesMatch>

    # No server-side execution by default. Exceptions in section 2.
    <FilesMatch "\.(?i:php|phar|phtml|php[0-9]|cgi|pl|py|sh|inc)$">
        Require all denied
    </FilesMatch>
</Directory>

# Dot directories (.git/, .idea/) at any depth below the web root.
# The lookahead is load-bearing, see below — do not simplify it away.
<DirectoryMatch "^/mnt/data/www/(.*/)?\.(?!well-known)[^/]+">
    Require all denied
</DirectoryMatch>
```

The deploy scripts never publish repository metadata — they build the payload with
`git archive` and prune `README.md`, `LICENSE`, `docs/` and `scripts/` — so the two
`FilesMatch` denies are a safety net, not the primary control. Keep both: the net is what
holds when somebody unpacks a checkout by hand.

### Why `.well-known` is carved out

Without the `(?!well-known)` lookahead the `DirectoryMatch` denies every dot directory below
the web root, including `.well-known`. That breaks **CalDAV/CardDAV autodiscovery**:
Nextcloud clients such as iOS, Thunderbird and DAVx5 probe `/.well-known/caldav` and
`/.well-known/carddav`, and Nextcloud's own `.htaccess` rewrites `/nextcloud/.well-known/*`
onwards to `remote.php/dav`. Authorisation is evaluated before per-directory `mod_rewrite`
runs, so the deny wins and the rewrite never fires.

Everything meant to stay blocked still is: `.git/` and `.git/refs/` at any depth, `.idea/`,
`nextcloud/.git/`, and `.well-known/.git/`.

> A `<Directory /mnt/data/www/.well-known>` block re-granting access does **not** work as a
> counterpart. `<DirectoryMatch>` is merged *after* plain `<Directory>`, so the deny would win
> and the carve-out would silently do nothing. The exception has to live in the regex.

Certificate renewal is unaffected either way while the ACME authenticator stays `apache`:
certbot maps `/.well-known/acme-challenge/<token>` to `/var/lib/letsencrypt/http_challenges/`
with a vhost-level `RewriteRule` and grants it through a `<Location>` block — outside the web
root, and `<Location>` is merged after `<DirectoryMatch>` in any case. Choosing
`authenticator = webroot` instead makes the lookahead load-bearing for renewal too, and the
consequence is severe: `Strict-Transport-Security` with `includeSubDomains` is active for this
host, so an expired certificate takes the whole host offline with no click-through.

### Discovery redirects

Nextcloud lives in a subdirectory while clients probe the host root, so the redirects have to
be explicit:

```apache
Redirect 301 /.well-known/carddav   /nextcloud/remote.php/dav
Redirect 301 /.well-known/caldav    /nextcloud/remote.php/dav
Redirect 301 /.well-known/webfinger /nextcloud/index.php/.well-known/webfinger
Redirect 301 /.well-known/nodeinfo  /nextcloud/index.php/.well-known/nodeinfo
```

These belong at **server or virtual-host scope** — not nested inside `<Directory>`,
`<Location>` or `<Files>`. `Redirect` is mod_alias, and at server scope it runs at
translate_name, before the directory walk and before any `Require` is evaluated. Inside a
`<Directory>` container mod_alias uses a different hook and runs at fixup instead, which is
the most common reason a correct-looking redirect block does nothing.

The status code on `/.well-known/caldav` tells you which half is wrong:

- **404** — the `Redirect` lines are not in the running configuration. Either the file is not
  enabled, or Apache has not been reloaded.
- **403** — the `DirectoryMatch` is biting: the lookahead is missing or misspelled.
- **301** — correct.

Clients probe the host root, so `/nextcloud/.well-known/*` is Nextcloud's own business and is
not checked.

### Where `.htaccess` is still allowed

Exactly one place. Nextcloud needs its own `.htaccess` for rewrite rules, headers and its
blocks on `data/` and `config/`, so `AllowOverride All` is granted for that directory alone,
in section 2.

The `<FilesMatch "^\.">` deny does not interfere with it: that blocks HTTP access to
`.htaccess` and `.user.ini`, not Apache and PHP reading them from disk. Which is what we want
— the file should work and not be downloadable.

## 2. Re-enable PHP only where it is needed

PHP is required by the wiki, Nextcloud, `allsky/`, `images/` and `ost_events/`. Grant it per
directory rather than globally:

```apache
<Directory /mnt/data/www/allsky>
    <FilesMatch "\.php$">
        Require all granted
    </FilesMatch>
</Directory>

<Directory /mnt/data/www/nextcloud>
    AllowOverride All
    <FilesMatch "\.php$">
        Require all granted
    </FilesMatch>
</Directory>

# Belt and braces: the data directory must never be served, whatever the .htaccess says.
<Directory /mnt/data/www/nextcloud/data>
    Require all denied
</Directory>
```

Repeat for each path that genuinely needs it. Directories not listed keep the deny from
section 1.

Nextcloud needs the whole `\.php$` pattern rather than a list of files: it dispatches through
`index.php`, `remote.php`, `public.php`, `status.php`, `cron.php`, `ocs/v1.php` and
`ocs/v2.php`. Without the grant it answers 403 on every request. The `data/` deny is a
fallback — Nextcloud's own `.htaccess` already blocks that path, and its *Administration →
Overview* page warns when it does not.

> **Order matters, and not the way it looks.** Apache merges all `<Files>`/`<FilesMatch>`
> sections as one group *after* the `<Directory>` sections, in the order they appear in the
> configuration — not by path depth. The longer path `/mnt/data/www/nextcloud` does **not** win
> automatically; the grant works only because section 2 follows section 1 in the same file.

The same merge order works in our favour one step down: `.htaccess` is merged with the
`<Directory>` group, so the deny from section 1 survives Nextcloud's own `.htaccess`.
`AllowOverride All` does not punch a hole in section 1 — and by the same token the explicit
grant above is required, not optional.

## 3. Legacy directories

`ftp/` is a directory listing into the data archive's data directory — a folder an
application writes to. Keep the listing, but make sure nothing there can execute or render:

```apache
<Directory /mnt/data/www/ftp>
    Options +Indexes +FollowSymLinks

    AuthType Basic
    AuthName "OST Data Archive (legacy listing)"
    AuthUserFile /etc/apache2/ost_ftp.htpasswd
    Require valid-user

    RemoveHandler .php .phar .phtml .cgi .pl .py
    RemoveType    .php .phar .phtml

    # Never render active content from a directory an application writes to:
    # on a shared origin such a file would run next to Nextcloud and the dashboard.
    <FilesMatch "\.(?i:html?|xhtml|svg|xml|js|mjs)$">
        Header always set Content-Disposition "attachment"
        Header always set X-Content-Type-Options "nosniff"
    </FilesMatch>
</Directory>
```

Apply the same `FilesMatch` rules to `/mnt/data/www/images`.

## 4. Security headers

`Strict-Transport-Security`, `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`
and `Permissions-Policy` belong on the whole virtual host. The Content-Security-Policy and the
cross-origin isolation headers do not: they are scoped to the landing page.

`^/static/` is unambiguous here — every other application uses a prefixed path
(`/inventory/static`, `/ost_status/static`, `/data_archive/static`, `/weather_station/static`):

```apache
<LocationMatch "^/(index\.html)?$|^/static/|^/news_articles/">
    Header always set Content-Security-Policy-Report-Only "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; media-src 'self'; font-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
    Header always set Cross-Origin-Opener-Policy   "same-origin"
    Header always set Cross-Origin-Resource-Policy "same-origin"
</LocationMatch>
```

The policy needs no `unsafe-inline`: the landing page and the articles carry no inline
scripts, no inline styles and no external resources. Three directives are load-bearing and
should not be trimmed as apparent dead weight:

- `connect-src 'self'` for the `fetch('news_articles/articles.json')` call in
  `static/js/base.js`.
- `font-src 'self'` for the self-hosted `@font-face` files in `static/css/base.css`.
- `media-src 'self'` for the `<video>` elements in the articles. `media-src` falls back to
  nothing but `default-src 'none'`, so without it those videos are blocked.

Nextcloud and the other applications sit outside this `LocationMatch` by design — `default-src
'none'` would break them on the first request. Confirm that no `Alias` remaps one of them into
a path the pattern covers.

Neighbouring applications send policies of their own: Nextcloud ships a nonce-based one and
the Django applications use `django-csp`. So the presence of a CSP header on a neighbour proves
nothing. What distinguishes this policy from all of them is `default-src 'none'` — every
neighbour starts from `'self'`. That string, not the header name, is what to look for when
asking whether the `LocationMatch` has spilled over.

**Roll out in two steps.** Start with `Content-Security-Policy-Report-Only` as shown, open `/`,
`/static/about.html`, `/static/impressum.html`, `/static/datenschutz.html`,
`/news_articles/index.html` and every article carrying a `<video>` element, and check the
browser console on each. Only then drop `-Report-Only` from the header name.

> When writing the header name, do not append a colon. `Header always set
> Content-Security-Policy-Report-Only: "..."` sets a header whose *name* ends in a colon, and
> browsers ignore it silently — the policy looks active but is not. It shows up in a response
> as a doubled colon.

### Reading the console (Firefox)

Check the **Network** panel first. The console cannot tell you whether the header arrived at
all. Reload, select the document request, and read the response headers with the *Raw* toggle
on — that is where a header name ending in a colon becomes visible.

Then the console. Two settings decide whether you see anything:

- **Persist Logs** must be on (gear icon in the console toolbar). Violations are emitted during
  page load, and without it the navigation clears them before you can read them.
- **Warnings** must be an active filter. In report-only mode violations are warnings, not
  errors. Filtered to errors only, a broken policy is indistinguishable from a clean one.

A violation reads:

```
Content-Security-Policy: (Report-Only policy) The page's settings would block the loading
of a resource at https://.../images/example.mp4 ("default-src").
```

The directive in parentheses is the part to act on. `default-src` means no directive covers
that resource type at all, so one is missing. A named directive such as `style-src` means the
directive is there but too narrow. Once `-Report-Only` is dropped the wording changes from
`would block` to `blocked the loading`, which is how you confirm the switch took effect.

Two things that look like findings and are not. Links to external sites never appear as
violations — CSP does not govern link navigation, and no directive covers `<a href>`.

The second is browser extensions, which inject scripts into any page and raise warnings that
have nothing to do with the page. The signature is a `script-src-elem` violation for an
*inline script* on a page that has no `<script>` element at all. Confirm by reloading in a
private window or a clean profile (`firefox -P`): the warning goes away. Do **not** act on
Firefox's accompanying suggestion to add the offered `'sha256-...'` hash — that would
permanently whitelist an extension's script in your own policy.

Report-only means the page works perfectly even when the policy is wrong. Nothing visible tells
you anything, and with no `report-uri` or `report-to` endpoint the console only ever covers
pages someone opens by hand. An empty console is therefore ambiguous: either the pages are
clean, or the header never arrived. The Network panel is what tells the two apart.

## 5. Verification

```bash
./scripts/verify-hardening.sh                        # everything
./scripts/verify-hardening.sh --only headers         # one group
./scripts/verify-hardening.sh --only nextcloud -q    # failures only
```

The groups are `headers`, `metadata`, `site`, `media`, `neighbours`, `nextcloud` and
`discovery`, and they line up with the sections above; `--help` lists them. Every check is a
plain HTTP request, so the script writes nothing.

A 403 where the script expects "403 or 404" does not mean the file exists. The deny rules are
evaluated before Apache discovers a file is absent, so a 403 on pruned metadata is confirmation
that section 1 is live.

> **The script is shaped like a vulnerability scan, because the checks are.** A full run makes
> around 45 requests, most of them deliberately provoking 403 and 404 responses. fail2ban,
> mod_evasive or a campus firewall can read that as scanning and block the source address
> part-way through — which surfaces as every remaining check failing with code `000`, a
> connection error rather than a result. That is why requests are spaced by `--delay` seconds.
> Prefer running it on the host itself.

Renewal is worth exercising end to end rather than guessing at it. On the host, as root:

```bash
apache2ctl configtest
certbot renew --dry-run    # inserts the challenge config, reloads, removes it again
```

Run this after every change to the rules above, and re-run `verify-hardening.sh` after a real
renewal — certbot rewrites the virtual host, and the ordering section 2 depends on is not
something Apache will warn you about.

Also worth running against the host: <https://securityheaders.com> and
<https://developer.mozilla.org/en-US/observatory>.

## 6. Shared-origin rules

Everything on this host shares one browser origin, so the path prefix is not a trust boundary.
Two consequences to design for from the start:

- **Every application needs its own cookie names.** Django defaults to `sessionid` and
  `csrftoken` for every project; two Django applications on one host overwrite each other's,
  and the last page visited wins. Set a distinct `SESSION_COOKIE_NAME` and `CSRF_COOKIE_NAME`
  per application, plus `SESSION_COOKIE_SECURE`, `SESSION_COOKIE_HTTPONLY`,
  `SESSION_COOKIE_SAMESITE = 'Lax'` and `CSRF_COOKIE_SECURE`. `CSRF_COOKIE_HTTPONLY` is
  deliberately left off — Django expects the token to be readable. The same applies to PHP
  applications, which all default to `PHPSESSID`: give each one its own `session.name`.
  `SESSION_COOKIE_PATH` adds defence in depth but is not a boundary; cookie paths are not
  enforced against script access.
- **Separate origins need DNS.** Moving Nextcloud to `cloud.polaris.…` is the only change that
  establishes a real boundary. `Strict-Transport-Security` with `includeSubDomains` is active
  for this host, so any new subdomain must have a valid certificate from the first day or
  browsers will refuse to reach it. A different port is *not* an equivalent substitute: it
  separates DOM and storage, but cookies are not port-scoped.
