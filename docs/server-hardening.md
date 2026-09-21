# Server hardening (Apache)

These snippets belong in the Apache configuration, **not** in this repository as an
`.htaccess` file. They are scoped deliberately: the landing page shares one host with several
Django applications, a wiki, a Nextcloud instance and some legacy directories, and a rule
applied too broadly will break one of them.

Host: `polaris.astro.physik.uni-potsdam.de`, `DocumentRoot /mnt/data/www`.

## Before changing anything

The paths below assume that the legacy directories and the PHP applications live under
`/mnt/data/www`. Confirm that first — a `<Directory>` block on the wrong path is dead
configuration that looks protective:

```bash
apache2ctl -S
grep -rn 'mnt/data/www\|nextcloud\|DocumentRoot\|AllowOverride' /etc/apache2/ | sort
ls -la /mnt/data/www/
```

Take a backup of the web root before the first deployment with the new scripts:

```bash
tar czf /mnt/data/backup/www-$(date +%F).tar.gz -C /mnt/data www
```

## 1. Web root defaults

```apache
<Directory /mnt/data/www>
    Options -Indexes +FollowSymLinks
    Require all granted

    # Hidden files: .git, .gitignore, .htaccess, .idea, ...
    <FilesMatch "^\.">
        Require all denied
    </FilesMatch>

    # Repository metadata. The deploy script never ships these; this is a safety net
    # for leftovers from the old "git pull into the web root" deployment.
    <FilesMatch "^(README\.md|TODO\.md|LICENSE|SECURITY_AUDIT\.md|.*\.code-workspace)$">
        Require all denied
    </FilesMatch>

    # No server-side execution by default. Exceptions in section 2.
    <FilesMatch "\.(?i:php|phar|phtml|php[0-9]|cgi|pl|py|sh|inc)$">
        Require all denied
    </FilesMatch>
</Directory>

# Dot directories (.git/, .idea/) below the web root
<DirectoryMatch "^/mnt/data/www/(.*/)?\.[^/]+">
    Require all denied
</DirectoryMatch>
```

Do not add `AllowOverride None` here without checking first whether Nextcloud lives below
this path — Nextcloud requires its own `.htaccess`.

## 2. Re-enable PHP only where it is needed

PHP is required by the wiki, Nextcloud, `allsky/`, `images/` and `ost_events/`. Grant it per
directory rather than globally:

```apache
<Directory /mnt/data/www/allsky>
    <FilesMatch "\.php$">
        Require all granted
    </FilesMatch>
</Directory>
```

Repeat for each path that genuinely needs it. Directories not listed keep the deny rule from
section 1.

## 3. Legacy directories

`ftp/` is a directory listing into the **data archive's data directory** — a folder an
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
and `Permissions-Policy` are already set for the whole virtual host. What is missing is a
Content-Security-Policy and the cross-origin isolation headers.

Scope them to the landing page. `^/static/` is unambiguous — every other application uses a
prefixed path (`/inventory/static`, `/ost_status/static`, `/data_archive/static`,
`/weather_station/static`):

```apache
<LocationMatch "^/(index\.html)?$|^/static/|^/news_articles/">
    Header always set Content-Security-Policy-Report-Only "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; font-src 'self'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
    Header always set Cross-Origin-Opener-Policy   "same-origin"
    Header always set Cross-Origin-Resource-Policy "same-origin"
</LocationMatch>
```

The policy needs no `unsafe-inline`: the landing page and the articles contain no inline
scripts, no inline styles and no external resources. `connect-src 'self'` is required for the
`fetch('news_articles/articles.json')` call in `static/js/base.js`.

**Roll out in two steps.** Start with `Content-Security-Policy-Report-Only` as shown, open
`/`, `/static/about.html`, `/static/impressum.html`, `/static/datenschutz.html`,
`/news_articles/index.html` and one article, and check the browser console. Only then drop
`-Report-Only` from the header name.

> When writing the header name, do not append a colon. `Header always set
> Content-Security-Policy-Report-Only: "..."` sets a header whose *name* ends in a colon, and
> browsers ignore it silently — the policy looks active but is not.

Anything the landing page adds later must obey this policy. That applies to articles in the
`ost_news` repository too: no inline styles, no embedded third-party videos or iframes.

## 5. Verification

```bash
H=https://polaris.astro.physik.uni-potsdam.de

curl -sI $H/ | grep -iE "content-security|x-frame|x-content-type|referrer|strict-transport|cross-origin"

# Repository metadata and scratch paths — expect 403 or 404
for p in .git/HEAD .gitignore README.md LICENSE SECURITY_AUDIT.md .idea/workspace.xml \
         news_articles/.git/HEAD news_articles/README.md \
         landing_page_test/ possible_thumbnails/ static/ news_articles/images/; do
  printf "%-32s %s\n" "$p" "$(curl -s -o /dev/null -w '%{http_code}' $H/$p)"
done

# The site itself — expect 200 throughout
for p in "" static/about.html static/impressum.html static/datenschutz.html \
         news_articles/index.html news_articles/articles.json \
         static/images/archive.jpg static/images/inventory.jpg static/images/outreach.jpg; do
  printf "%-34s %s\n" "/$p" "$(curl -s -o /dev/null -w '%{http_code}' $H/$p)"
done

# Neighbouring services must be unaffected — the CSP must not reach them
for p in wiki/ nextcloud/ gallery/ inventory/ ost_events/ data_archive/ weather_station/; do
  printf "%-20s %s  CSP:%s\n" "$p" \
    "$(curl -s -o /dev/null -w '%{http_code}' $H/$p)" \
    "$(curl -sI $H/$p | grep -ci content-security-policy)"
done
```

Also worth running against the host: <https://securityheaders.com> and
<https://developer.mozilla.org/en-US/observatory>.

## 6. Shared-origin notes

Everything on this host shares one browser origin, so the path prefix is not a trust
boundary. Two consequences worth acting on:

- **Django cookie names must differ per application.** The defaults are `sessionid` and
  `csrftoken` for every Django project; with several of them on one host they overwrite each
  other. Set a distinct `SESSION_COOKIE_NAME` and `CSRF_COOKIE_NAME` per application, plus
  `SESSION_COOKIE_SECURE`, `SESSION_COOKIE_HTTPONLY`, `SESSION_COOKIE_SAMESITE = 'Lax'` and
  `CSRF_COOKIE_SECURE`. `SESSION_COOKIE_PATH` adds defence in depth but is not a security
  boundary — cookie paths are not enforced against script access.
- **Separate origins need DNS.** Moving Nextcloud to `cloud.polaris.…` is the only change
  that establishes a real boundary. Note that `Strict-Transport-Security` with
  `includeSubDomains` is already active for this host, so any new subdomain must have a valid
  certificate from the first day or browsers will refuse to reach it. A different port is
  *not* an equivalent substitute: it separates DOM and storage, but cookies are not
  port-scoped.
