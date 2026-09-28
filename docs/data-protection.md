# Data protection — rules, jobs, checklist

Internal notes behind the public privacy policy (`static/datenschutz.html`). The policy states
concrete periods and cookie lifetimes for every service; this file records the rules they follow,
the jobs that enforce them and what to check when something changes. It is not published
(`docs/` is excluded by `scripts/deploy.sh`).

Whenever a service changes what it stores, how long, or which cookies it sets: update its section
in `static/datenschutz.html` (German **and** English, anchors stay stable), bump "Stand" /
"Last updated", and update the tables below.

## Rules for all services

New services and changes follow these rules; deviations need a reason in the service's README.

### Retention

| Kind of data | Retention | Examples |
|---|---|---|
| Technical logs (web server access/error logs, application logs in the journal) | **7 days** | Apache logs, journald (`MaxRetentionSec=7day`), `ost-events` activity log |
| Security logs of sign-ins (who signed in from where, failed attempts) | **30 days**; failed-attempt counters only until the lockout ends | weather station admin (django-axes) |
| Person-linked history kept for traceability (who changed what, who borrowed what, who observed) | pseudonymise or anonymise after **1–2 years**; keep the content | data archive history/audit log (2 years), inventory loans (1 year after return) |
| Event registrations | anonymise 14 days after the event, backups 14 days — **≤ 4 weeks** in total | `ost_events` |
| Backups containing personal data | not longer than the data itself would be kept | `ost_events` backups (14 days) |
| Data that is not needed | not collected | IP/user agent of event registrations, CSRF cookie for public pages |
| Accounts of people who left (name/e-mail copied from LDAP) | deactivated and blanked within a day after the LDAP entry is gone | inventory, data archive |
| Credits kept on purpose, **with consent** | permanent; withdrawal removes the name | gallery photographers, observing session log of the status dashboard |

### Cookies

- Login sessions: **at most 12 hours**, deleted on sign-out; expired sessions are removed from the
  database daily.
- CSRF cookies: **browser session only** (Django: `CSRF_COOKIE_AGE = None`; default would be a year).
- Public pages without sign-in set **no cookies**.
- Names carry the project prefix (`ost_inventory_…`, `ostdata_…`, `ost_weather_…`, `ost_status_…`,
  `ost_events_…`) and the path is restricted to the app, so services on this host never share or
  overwrite cookies.
- No analytics, no third-party content (only exception: the Aladin Lite sky map in the data archive,
  loaded from CDS Strasbourg, stated in the policy).

## Jobs that enforce the retention

If one of these stops running, the policy is no longer true. Check them once a month (commands in
the last column; replace unit names/paths if the server uses different ones).

| Service | Job | Schedule | What it deletes / anonymises | Check |
|---|---|---|---|---|
| Server | journald, Apache logrotate | continuous / daily | logs older than 7 days | `journalctl --disk-usage`, `grep MaxRetentionSec /etc/systemd/journald.conf{,.d/*}`, `/etc/logrotate.d/apache2` |
| Event registration (`ost_events`) | cron → `cron.php` | daily 08:00 | expired pending registrations; PII 14 days after the event; backups > 14 days; legacy `email_log` / IP data | `journalctl -t ost-events --since -35d \| grep "Data retention"` |
| Inventory (`ost_inventory`) | systemd timer `ost-inventory-purge` → `manage.py purge_personal_data`, then `deactivate_departed_ldap_users` | daily 03:30 | borrower data 1 year after return (+ admin log entries); expired sessions; accounts whose LDAP entry is gone (deactivated, name/e-mail cleared) | `systemctl list-timers ost-inventory-purge.timer`, `journalctl -u ost-inventory-purge -n 20` |
| Data archive (`ost_data_archive`) | Celery beat (`celery-beat.service` + worker `celery.service`) | hourly :15, daily 04:40, 04:50, 04:55 | download ZIPs after 72 h, job rows 30 days later; expired sessions; user link in history/audit log after 2 years; accounts whose LDAP entry is gone (deactivated, name/e-mail cleared) | `journalctl -u celery -u celery-beat --since -2d \| grep -E "Cleanup expired downloads\|Expired sessions\|Pseudonymise\|Departed LDAP"`; health page shows `download_cleanup_enabled`, `personal_data_retention_enabled` |
| Weather station | cron → `systemd-cat -t ost-weather-purge manage.py purge_personal_data` | daily 00:31 | expired sessions; admin sign-in logs > 30 days; expired failed-login records | `journalctl -t ost-weather-purge --since -2d` |
| Status dashboard (`ost_oms_presence`) | — | — | login events: journal (7 days); observing session log kept permanently by consent (credits observers) | — |
| Status dashboard cameras | outside these repositories | rolling | outdoor camera recordings after 48 h (stated in the camera notice) | verify on the recording host |
| Gallery (`ost_gallery`) | cron → `systemd-cat -t ost-gallery-build … gallery build` | daily 06:30 | build log goes to the journal (7 days); photographer names by consent, removed on request | `journalctl -t ost-gallery-build --since -2d` |
| News, allsky, landing page | — | — | no personal data beyond the web server logs | — |
| Wiki, Nextcloud | own settings | | link the central policy (done); retention settings see open items | |

## Open items

- **Nextcloud retention** is still at the defaults (no entries in `config.php`): activity log
  365 days (`activity_expire_days`), trash bin and versions `auto` (kept as long as space allows),
  `nextcloud.log` rotated by size only. Set values, then state them in the `#nextcloud` section.
- **DokuWiki** keeps the IP address of every edit in the page history (`data/meta/*.changes`,
  `data/media_meta/*.changes`) without limit. Options: the `anonip` plugin for new edits plus a
  one-time clean-up of existing entries; then update the `#wiki` section.
- **Server backups:** find out whether the host or its databases are backed up (university backup,
  `pg_dump`) and for how long; the policy says nothing about it yet.

## Contact details — where they appear

When one of these changes (new president, data protection officer, contact person, phone numbers),
update **all** places in the same go:

| Detail | `static/datenschutz.html` (DE + EN) | `static/impressum.html` (DE + EN) | `ost_oms_presence/templates/datenschutz.html` (camera notice, DE) | Posted camera notice at the observatory (paper, QR code) |
|---|---|---|---|---|
| Controller: University of Potsdam, represented by the president (name) | ✓ | ✓ | ✓ | check |
| University phone / fax | phone | phone, fax **+49 331 97 21 63** | phone, fax **+49 331 977-1089** | check |
| Contact for data protection questions (Dr. Rainer Hainich) | ✓ | as person responsible for content | ✓ | check |
| Data protection officer (Dr. Marek Kneis) | ✓ | — | ✓ (with fax) | check |
| Supervisory authority (LDA Brandenburg) | ✓ | — | named without address | — |
| "Stand" / "Last updated" | ✓ | — | — | — |

The two fax numbers of the university differ between the legal notice and the camera notice —
one of them is outdated and needs checking.
