# stack-ebooks

Git-backed Compose for the z2 **ebook** pipeline: **Shelfmark** (discovery/request/download) and **BookOrbit** (library, reading UI, Send-to-Kindle).

Shelfmark downloads via **remote qBittorrent on SeedHost** (ebooks category); completed files are read over SFTP (rclone mount, read-only), processed into `/nas/eBookDownloads`, then ingested by BookOrbit into `/nas/eBooks`. Originals stay on SeedHost for seeding.

Uses the **existing Prowlarr** instance from [stack-audiobooks](https://github.com/GregDog/stack-audiobooks) (MAM indexers). Does not modify ReadMeABook or Audiobookshelf.

Public access via **stackproxy**:

| URL | Service | Auth |
|-----|---------|------|
| https://ebookrequests.cvss.io | Shelfmark | Pocket ID OIDC (native) |
| https://library.cvss.io | BookOrbit | Pocket ID OIDC (admin UI) |

## Architecture

```text
SeedHost (city.seedhost.eu)
  └── qBittorrent → /home16/harenix/downloads/ebooks  (seed forever, category: ebooks)

Z2 host
  └── rclone SFTP mount (read-only) → /mnt/seedhost-ebooks
        └── shelfmark container
              ├── /home16/harenix/downloads/ebooks  (ro, same path as qBittorrent)
              └── /nas/eBookDownloads  (rw, processed ebooks)

BookOrbit container
  ├── /nas/eBooks  (rw, final library)
  └── /nas/eBookDownloads  (Book Dock — watches for new imports)

Prowlarr (audiobooks stack, lab 192.168.2.4) → MAM / indexers for Shelfmark
```

| Service | Network | Public |
|---------|---------|--------|
| shelfmark | `lab` + `stackproxy` | `ebookrequests.cvss.io` |
| bookorbit | `lab` + `stackproxy` | `library.cvss.io` |
| bookorbit-db | `internal` | — |

## Paths

| Path | Purpose |
|------|---------|
| `/mnt/seedhost-ebooks` | Host rclone mount (read-only SFTP from SeedHost) |
| `/home16/harenix/downloads/ebooks` | In-container path (**must match qBittorrent save path**) |
| `/nas/eBookDownloads` | Shelfmark ingest + BookOrbit Book Dock (Synology via `synology-media`) |
| `/nas/eBooks` | BookOrbit library root |
| `/opt/ebooks/shelfmark/{config,rclone}/` | Shelfmark config + rclone logs (not in Git) |
| `/opt/ebooks/bookorbit/data/` | BookOrbit app + Postgres data |

Create **`eBooks`** and **`eBookDownloads`** folders on the Synology share backing the `synology-media` Docker volume before first deploy.

## SeedHost qBittorrent (manual, one-time)

On SeedHost, create category **`ebooks`** with save path:

```text
/home16/harenix/downloads/ebooks
```

Ensure the directory exists. Shelfmark sends torrents to this category; the read-only mount prevents deleting SeedHost files after import.

## First-time setup

1. **Secrets**

```bash
cd /opt/stacks/ebooks
cp .env.example .env
chmod 600 .env
# Fill: SEEDHOST_SFTP_PASSWORD, QBITTORRENT_*, SHELFMARK_OIDC_*, BookOrbit secrets
# PROWLARR_API_KEY is auto-copied from /opt/audiobooks/prowlarr on deploy if empty
openssl rand -hex 32  # BOOKORBIT_JWT_SECRET
openssl rand -hex 16  # BOOKORBIT_SETUP_BOOTSTRAP_TOKEN
```

2. **Install rclone mount**

```bash
bash scripts/install-seedhost-mount.sh
```

3. **Deploy stackproxy** (if not already — adds DNS + Caddy for new hostnames)

```bash
cd /opt/stacks/stackproxy && bash scripts/deploy.sh
```

4. **Pocket ID OIDC clients** at https://id.cvss.io

| App | Redirect URI |
|-----|--------------|
| Shelfmark | `https://ebookrequests.cvss.io/api/auth/oidc/callback` |
| BookOrbit | `https://library.cvss.io/oauth2-callback` |

5. **Deploy ebooks stack**

```bash
cd /opt/stacks/ebooks
bash scripts/deploy.sh
```

6. **BookOrbit initial setup**

- Open https://library.cvss.io/auth/setup
- Header: `x-setup-token: <BOOKORBIT_SETUP_BOOTSTRAP_TOKEN from .env>`
- Create admin account, then add library rooted at **`/nas/eBooks`**
- Settings → OIDC / SSO → configure Pocket ID (`https://id.cvss.io`)
- Settings → Email → configure SMTP for Send-to-Kindle (see below)

7. **Shelfmark**

- Log in via Pocket ID at https://ebookrequests.cvss.io
- Deploy promotes `SHELFMARK_ADMIN_EMAIL` to admin after first login
- Settings → confirm Prowlarr + qBittorrent (env defaults apply; verify category `ebooks`)

## Family access (multi-user)

Ingress group policy lives in [stackproxy](../stackproxy/README.md#access-groups-pocket-id--tinyauth). On deploy, this stack configures:

| App | Script | Behaviour |
|-----|--------|-----------|
| Shelfmark | `configure-shelfmark-requests.sh` | Request workflow enabled (`request_book` — you pick release on fulfil) |
| BookOrbit | `configure-bookorbit-family-oidc.sh` | Pocket ID group **media-users** → `library_download`; default library access; no admin default perms |

Set `SHELFMARK_ADMIN_EMAIL` and `BOOKORBIT_ADMIN_EMAIL` in `.env`. Optional: `BOOKORBIT_MEDIA_OIDC_GROUP=media-users`, `BOOKORBIT_DEFAULT_LIBRARY_ID=1`.

Family must be in Pocket ID group **media_users** only (not `stackproxy_admins`).

### OIDC trust (stackproxy network)

Shelfmark (Python) and BookOrbit (Node) join `stackproxy` and mount `stackproxy_caddy_data` for internal `https://id.cvss.io` OIDC discovery and token exchange. Compose sets `SSL_CERT_FILE` / `REQUESTS_CA_BUNDLE` (Shelfmark) and `NODE_EXTRA_CA_CERTS` (BookOrbit). Deploy stackproxy before this stack. See [stackproxy internal OIDC](../stackproxy/README.md#internal-oidc-docker--pocket-id).

## Send-to-Kindle (BookOrbit)

Configured in **BookOrbit admin → Settings → Email** (not in Git):

| Setting | Example / notes |
|---------|-----------------|
| SMTP host/port | Your mail provider (e.g. Amazon SES, Gmail app password) |
| From address | Verified sender allowed by your SMTP provider |
| Kindle address | `you@kindle.com` from Amazon account |

Document placeholders in `.env.example`; add real credentials only in the BookOrbit UI or a local secrets note.

## Validation

```bash
bash scripts/validate-seedhost-mount.sh
```

Checks:

- systemd `rclone-seedhost-ebooks.service` active
- `/mnt/seedhost-ebooks` mounted read-only
- Shelfmark sees SeedHost path (ro) and `/nas/eBookDownloads` (rw)
- BookOrbit sees `/nas/eBooks` and Book Dock `/nas/eBookDownloads`

### End-to-end test

1. Request an ebook in Shelfmark (Prowlarr/MAM → SeedHost qBittorrent)
2. Wait for qBittorrent completion; file appears under `/mnt/seedhost-ebooks` within ~1 minute
3. Shelfmark processes into `/nas/eBookDownloads`
4. BookOrbit Book Dock imports into `/nas/eBooks`
5. Optional: Send to Kindle from BookOrbit

## Deploy

```bash
cd /opt/stacks/ebooks
bash scripts/deploy.sh
```

Production path: `/opt/stacks/ebooks`.

## CI/CD

- **Repo:** [GregDog/stack-ebooks](https://github.com/GregDog/stack-ebooks)
- **Runner:** `actions-runner-stack-ebooks` on z2 (install after first push)
- **Deploy path:** `/opt/stacks/ebooks`
- **Trigger:** push to `main` → `bash scripts/deploy.sh`

## Troubleshooting

| Issue | Fix |
|-------|-----|
| OIDC login fails (`unable to get local issuer certificate`) | Redeploy stackproxy, then `docker compose up -d` here. Check CA mounts on shelfmark/bookorbit and run `bash ../stackproxy/scripts/ensure-caddy-internal-ca-readable.sh`. |
| Mount not active | `sudo systemctl status rclone-seedhost-ebooks` |
| Shelfmark ENOENT on download | rclone dir cache — restart mount + `docker compose up -d --force-recreate shelfmark` |
| Transport endpoint not connected | Recreate shelfmark after rclone restart |
| Missing NAS folders | Create `eBooks` and `eBookDownloads` on Synology share |
| Not admin after SSO (Shelfmark) | Log in once via Pocket ID, re-run deploy (runs `ensure-shelfmark-admin.sh`), then **log out and back in** so the session picks up admin. |
| Failed to load setup wizard (Shelfmark) | Same as above — onboarding is admin-only; OIDC first login creates a non-admin user until deploy promotes your email. |
| Not admin after SSO (BookOrbit) | Enable **Allow local account linking** on OIDC provider; deploy runs `ensure-bookorbit-admin.sh`. Log out and sign in via Pocket ID again. Or log in locally as your setup user. |
| Your account has not been set up (BookOrbit) | Pocket ID `preferred_username` must match your local username (case-sensitive). Deploy lowercases the local username; or enable auto-provision + local linking in OIDC settings. |

Mount logs: `/opt/ebooks/shelfmark/rclone/rclone-mount.log`
