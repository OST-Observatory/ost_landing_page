# OST Landing Page

Simple landing page for the [OST website](https://polaris.astro.physik.uni-potsdam.de).

News articles live in a separate repository and are deployed into `news_articles/` on the server. Clone [ost_news](https://github.com/OST-Observatory/ost_news) into that directory for local development:

```bash
git clone https://github.com/OST-Observatory/ost_news.git news_articles
```

The folder `news_articles/` is listed in `.gitignore` and is not part of this repository.

## Repository layout

```
├── index.html
├── static/
│   ├── css/base.css
│   ├── js/base.js           # News banner on the home page
│   ├── about.html
│   ├── impressum.html       # Legal notice (German / English)
│   ├── datenschutz.html     # Privacy policy (German / English)
│   ├── fonts/               # Open Sans + Lato (woff2)
│   └── images/              # Thumbnails and background
├── scripts/deploy.sh        # Deployment (runs on the server)
├── docs/                    # Deployment and server notes — never published
└── news_articles/           # Deploy: clone ost_news here
```

## Deployment

Deployment runs on the server from a checkout kept **outside** the web root:

```bash
cd /mnt/data/src/ost_landing_page
./scripts/deploy.sh            # dry run — always read this first
./scripts/deploy.sh --apply
```

Articles are deployed the same way from `ost_news`, and `news_articles/images/` is synced
separately. Full description, including what the script refuses to do and why:
[docs/deployment.md](docs/deployment.md).

Server configuration (security headers, legacy paths, Content-Security-Policy):
[docs/server-hardening.md](docs/server-hardening.md).

HTTP cache examples for static assets and `articles.json`: [ost_news/docs/deploy-cache.md](../ost_news/docs/deploy-cache.md) (paths apply under `static/` and `news_articles/`).

## Conventions

- **Anchor every `.gitignore` pattern with a leading `/`.** An unanchored pattern such as
  `images` matches at every level; it silently excluded `static/images/` from this repository
  and left three images referenced by `index.html` uncommitted.
- **Strip metadata from images before committing:** `exiftool -all= -overwrite_original file.jpg`.
  The deploy script refuses to publish images carrying GPS or camera data.
- **Keep scratch files outside the project folder.** `.gitignore` protects against git, not
  against `scp -r`.
- **The page runs under a strict Content-Security-Policy.** No inline `<script>`, no inline
  `<style>`, no `style=` attributes, no resources from other hosts.

## Background image

The page background uses WebP with a JPEG fallback (`image-set` in CSS):

- `static/images/ngc7000_cut_rotated_2.webp` (desktop)
- `static/images/ngc7000_cut_rotated_2_mobile.webp` (viewport ≤ 768px)
- `static/images/ngc7000_cut_rotated_2.jpg` (fallback)

Regenerate locally after editing the source JPEG (do not run image tools on the production server):

```bash
cd static/images
ffmpeg -y -i ngc7000_cut_rotated_2.jpg -q:v 75 ngc7000_cut_rotated_2.webp
ffmpeg -y -i ngc7000_cut_rotated_2.jpg -vf "scale=1280:-2" -q:v 80 ngc7000_cut_rotated_2_mobile.webp
```

## Cookies

This site sets no cookies and uses no browser storage at all. There is deliberately no cookie
banner: § 25 (2) no. 2 TDDDG exempts storage that is strictly necessary, and with nothing
stored there is nothing to consent to. The required Art. 13 GDPR information about server
logfiles lives in `static/datenschutz.html`.

Keep it that way — adding `localStorage`, `sessionStorage` or a cookie means the privacy
policy has to be updated with it.

## Central privacy policy

`static/datenschutz.html` is the privacy policy for the landing page **and** every service linked
from it (Wiki, gallery, data archive, allsky, weather station, news, status dashboard, Nextcloud,
inventory, event registration). A general part covers controller, contacts, logfiles and rights;
each service then has a short section with only what it adds (sign-in, cookies, stored data,
retention). The services link to their section instead of hosting their own policy:

| Service | German anchor | English anchor |
|---------|---------------|----------------|
| Wiki | `#wiki` | `#en-wiki` |
| Gallery | `#gallery` | `#en-gallery` |
| Data archive | `#data-archive` | `#en-data-archive` |
| Allsky | `#allsky` | `#en-allsky` |
| Weather station | `#weather-station` | `#en-weather-station` |
| News | `#news` | `#en-news` |
| Status dashboard | `#status` | `#en-status` |
| Nextcloud | `#nextcloud` | `#en-nextcloud` |
| Inventory | `#inventory` | `#en-inventory` |
| Event registration | `#events` | `#en-events` |

Keep these ids stable — they are hard-coded in the other repositories (and `/ost_status/privacy`
redirects to `#en-status`). The German text is authoritative; change both languages together.

When a service changes what it stores, which cookies it sets or how long it keeps data, update
its section here. The one exception is the camera notice of the status dashboard
(`/ost_status/datenschutz`, repo ost_oms_presence): it is linked from the information sheet
posted at the observatory and stays a separate page.

## Static images in this repo

| File | Use |
|------|-----|
| `ngc7000_cut_rotated_2.*` | Full-page background |
| `OST_family_cropped.JPG`, `messier33_tn.jpg`, … | Home page tiles |
| `news_archive.jpg` | News archive tile |
| `favicon.ico` | Site icon |

## Attributions

The hard disk image used as a thumbnail in this project was taken by Evan-Amos:

https://commons.wikimedia.org/wiki/File:Laptop-hard-drive-exposed.jpg

The archive shelf image used as a thumbnail in this project was taken by Chris93:

https://commons.wikimedia.org/wiki/File:Archives_nationales_PR3.jpg
