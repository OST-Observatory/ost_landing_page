# OST Landing Page

Simple landing page for the [OST website](https://polaris.astro.physik.uni-potsdam.de).

News articles live in a separate repository and are deployed into `news_articles/` on the server. Clone [ost_news](https://github.com/) into that directory for local development:

```bash
git clone <ost_news-repo-url> news_articles
```

The folder `news_articles/` is listed in `.gitignore` and is not part of this repository.

## Repository layout

```
├── index.html
├── static/
│   ├── css/base.css
│   ├── js/base.js           # News banner on the home page
│   ├── js/cookie-notice.js  # Essential-cookie information bar
│   ├── fonts/               # Open Sans + Lato (woff2)
│   └── images/              # Thumbnails and background
└── news_articles/           # Deploy: clone ost_news here
```

## Deployment

1. Deploy this repository to the web root.
2. Clone or pull **ost_news** into `news_articles/`.
3. Sync `news_articles/images/` and `news_articles/images/thumbs/` on the server (see ost_news README).

HTTP cache examples for static assets and `articles.json`: [ost_news/docs/deploy-cache.md](../ost_news/docs/deploy-cache.md) (paths apply under `static/` and `news_articles/`).

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

## Cookie notice

A small custom script (`static/js/cookie-notice.js`) informs visitors that only essential cookies are used. Dismissing the bar stores `ost_cookie_notice_ack` in `localStorage`.

Linked services (Wiki, Nextcloud, cameras, etc.) may set their own cookies when opened.

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
