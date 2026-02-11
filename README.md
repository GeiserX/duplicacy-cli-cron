# Duplicacy CLI (Cron)

A single Docker container that runs [Duplicacy CLI](https://github.com/gilbertchen/duplicacy) backups on a cron schedule to **two S3-compatible storages** simultaneously. One container handles multiple backup locations, with per-repo lock files, stuck-job timeouts, Telegram notifications, and weekly exhaustive pruning built in.

Primarily designed for UnRAID but works on any Docker host (Ubuntu, Debian, etc.).

## Features

- **Dual-storage backups** — every backup writes to two independent S3 endpoints (cross-backup architecture)
- **Multi-repo** from a single container (one tiny daily wrapper per repo)
- **S3-compatible storage** (Garage, MinIO, AWS S3, Backblaze B2, etc.)
- **Encrypted** backups with AES-256-GCM (per-repo passwords)
- **Parallel uploads** via configurable `DUPLICACY_THREADS`
- **Staggered cron schedules** across servers to avoid storage contention
- **Lock files** with automatic timeout to kill stuck backups after `MAX_RUNTIME_HOURS`
- **Saturday prune skip** — daily prune skipped when the weekly exhaustive prune runs
- **Weekly exhaustive prune** — reclaims actual storage space by scanning all chunks
- **Filter files** — exclude regenerable caches, thumbnails, and temporary data
- **Telegram notifications** via [Shoutrrr](https://github.com/containrrr/shoutrrr)
- **Boot USB backup** — back up Unraid flash drive config alongside your shares
- **Ubuntu/Debian support** — back up `/etc`, `/home`, crontabs, Tailscale state, etc.

## Architecture

Each server backs up to **two remote S3 endpoints** (never to itself). This ensures data redundancy across sites:

```
Server A ──backup──▶ S3 on Server B (primary)
           ──backup──▶ S3 on Server C (secondary)

Server B ──backup──▶ S3 on Server A (primary)
           ──backup──▶ S3 on Server C (secondary)

Server C ──backup──▶ S3 on Server A (primary)
           ──backup──▶ S3 on Server B (secondary)
```

The daily wrapper scripts are tiny (4 lines each) and source the shared `dual-executor.sh` which handles locking, backup, prune, and notification logic.

## Quick Start

### 1. Deploy the container

Copy `docker-compose.yml` and fill in your values:

```yaml
services:
  duplicacy-cli-cron:
    image: drumsergio/duplicacy-cli-cron:3.2.5.2
    container_name: duplicacy-cli-cron
    restart: unless-stopped
    volumes:
      - /mnt/user/appdata/duplicacy/config:/config
      - /mnt/user/appdata/duplicacy/cron:/etc/periodic
      - /mnt/user:/local_shares
      - /boot:/boot_usb
    environment:
      CRON_DAILY: "0 2 * * *"
      CRON_WEEKLY: "0 4 * * 6"
      DUPLICACY_THREADS: "8"
      HOST: MyServer
      TZ: Europe/Madrid
      SHOUTRRR_URL: telegram://TOKEN@telegram?chats=CHAT_ID&notification=no&parseMode=markdown
      ENDPOINT_1: "192.168.1.100:9000"
      ENDPOINT_2: "192.168.1.200:9000"
      BUCKET: duplicacy
      REGION: garage
      MAX_RUNTIME_HOURS: "71"
      # Credentials for each storage (primary + secondary):
      DUPLICACY_APPDATA_S3_ID: YOUR_PRIMARY_KEY
      DUPLICACY_APPDATA_S3_SECRET: YOUR_PRIMARY_SECRET
      DUPLICACY_APPDATA_PASSWORD: YOUR_ENCRYPTION_PASS
      DUPLICACY_APPDATAC_S3_ID: YOUR_SECONDARY_KEY
      DUPLICACY_APPDATAC_S3_SECRET: YOUR_SECONDARY_SECRET
      DUPLICACY_APPDATAC_PASSWORD: YOUR_ENCRYPTION_PASS
```

See `docker-compose.yml` in this repo for the full example with comments.

### 2. Initialize each backup location

Edit `config/config-s3.sh` with your storage name, snapshot ID, and repo path. Then run it inside the container:

```bash
docker exec duplicacy-cli-cron sh /config/config-s3.sh
```

Repeat for each folder you want to back up (e.g., `appdata`, `Multimedia`, `system`, `boot`).

### 3. Create daily wrapper scripts

Each backup location gets a tiny wrapper script placed in the daily cron directory. The wrapper sets per-repo constants and sources the shared `dual-executor.sh`:

```sh
#!/usr/bin/env sh
STORAGENAME="appdata"
SNAPSHOTID="appdata"
REPO_DIR="/local_shares/appdata"
THREADS_OVERRIDE="8"
. /config/dual-executor.sh
```

Place `dual-executor.sh` in the config volume, then create one wrapper per repo:

```bash
# Copy the executor to the config volume
cp scripts/dual-executor.sh /mnt/user/appdata/duplicacy/config/

# Create wrapper scripts in the cron directory
cat > /mnt/user/appdata/duplicacy/cron/daily/00-boot.sh << 'EOF'
#!/usr/bin/env sh
STORAGENAME="boot"
SNAPSHOTID="boot"
REPO_DIR="/boot_usb"
THREADS_OVERRIDE="8"
. /config/dual-executor.sh
EOF
chmod +x /mnt/user/appdata/duplicacy/cron/daily/00-boot.sh
```

Scripts are executed alphabetically by `run-parts`, so prefix with numbers to control order (e.g., `00-boot.sh`, `01-Multimedia.sh`, `02-appdata.sh`).

> **Tip**: Use `THREADS_OVERRIDE` per repo to tune performance. For HDD-backed repos with large files (media), lower threads (4-8) reduce disk seek contention. For SSD/NVMe or small-file repos, higher threads (8-16) improve throughput.

### 4. Set up the weekly exhaustive prune

Copy `scripts/exhaustive-prune.sh` to the weekly cron directory:

```bash
cp scripts/exhaustive-prune.sh /mnt/user/appdata/duplicacy/cron/weekly/01-exhaustive-prune.sh
chmod +x /mnt/user/appdata/duplicacy/cron/weekly/01-exhaustive-prune.sh
```

The exhaustive prune auto-discovers all repos under `/local_shares/*/` and prunes both primary and secondary storages. It also handles extra repos (`/boot_usb` for Unraid, `/local_*` for Ubuntu/Debian) and respects daily backup lock files to avoid conflicts.

## Configuration Reference

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CRON_DAILY` | `0 2 * * *` | When daily backup scripts run |
| `CRON_WEEKLY` | `0 4 * * 6` | When weekly exhaustive prune runs (Saturday by default) |
| `DUPLICACY_THREADS` | `4` | Default parallel upload/download threads |
| `HOST` | `$(hostname)` | Machine name shown in notifications |
| `TZ` | `Etc/UTC` | Timezone |
| `SHOUTRRR_URL` | _(empty)_ | Notification URL ([Shoutrrr format](https://containrrr.dev/shoutrrr/)) |
| `ENDPOINT_1` | _(required)_ | S3 endpoint for primary storage |
| `ENDPOINT_2` | _(required)_ | S3 endpoint for secondary storage |
| `BUCKET` | _(required)_ | S3 bucket name |
| `REGION` | _(required)_ | S3 region (use `garage` for Garage) |
| `MAX_RUNTIME_HOURS` | `71` | Kill stuck backups after this many hours |

### S3 Credential Convention

Duplicacy resolves credentials from environment variables by storage name. For dual-storage, you need **two sets** — one for the primary and one for the secondary (C-suffix):

```
# Primary storage
DUPLICACY_<STORAGENAME>_S3_ID       → S3 access key ID
DUPLICACY_<STORAGENAME>_S3_SECRET   → S3 secret access key
DUPLICACY_<STORAGENAME>_PASSWORD    → repository encryption password

# Secondary storage (same name + "C" suffix)
DUPLICACY_<STORAGENAME>C_S3_ID      → S3 access key ID
DUPLICACY_<STORAGENAME>C_S3_SECRET  → S3 secret access key
DUPLICACY_<STORAGENAME>C_PASSWORD   → repository encryption password
```

Example for a storage named `appdata`:

```yaml
DUPLICACY_APPDATA_S3_ID: GKabc123...
DUPLICACY_APPDATA_S3_SECRET: f42b4be...
DUPLICACY_APPDATA_PASSWORD: mySecretPassword
DUPLICACY_APPDATAC_S3_ID: GKdef456...
DUPLICACY_APPDATAC_S3_SECRET: a83c1d2...
DUPLICACY_APPDATAC_PASSWORD: mySecretPassword
```

### Staggering Backups Across Servers

When multiple servers share the same S3 backend, stagger `CRON_DAILY` to avoid contention:

| Server | `CRON_DAILY` | Description |
|--------|-------------|-------------|
| Server A | `0 2 * * *` | Runs at 2:00 AM |
| Server B | `0 3 * * *` | Runs at 3:00 AM |
| Server C | `0 4 * * *` | Runs at 4:00 AM |

### Filter Files

Create `.duplicacy/filters` inside a repo to exclude paths from backup. This reduces backup time and storage for regenerable data:

```
# Exclude cache and generated content
-Cache/
-EncodedVideo/
-Thumbs/
-.DS_Store
-Thumbs.db
-*.tmp
```

See the [Duplicacy wiki on filters](https://github.com/gilbertchen/duplicacy/wiki/Include-Exclude-Patterns) for the full syntax.

### Lock File and Timeout

Each daily wrapper creates a lock file at `/tmp/duplicacy-<SNAPSHOTID>.lock`. If a previous run is still active:

- **Within `MAX_RUNTIME_HOURS`**: the new run is skipped with a Telegram notification
- **Exceeds `MAX_RUNTIME_HOURS`**: the stuck process is killed and a fresh backup starts

### Prune Retention Policy

Daily prune (skipped on Saturdays):

```
-keep 0:180    # Delete all snapshots older than 180 days
-keep 30:90    # Keep one snapshot every 30 days if older than 90 days
-keep 7:30     # Keep one snapshot every 7 days if older than 30 days
-keep 1:7      # Keep one snapshot every day if older than 7 days
```

Weekly exhaustive prune runs with `-exhaustive` flag to scan all chunks and actually reclaim storage space.

## Scripts

| Script | Schedule | Purpose |
|--------|----------|---------|
| `scripts/dual-executor.sh` | Daily (sourced) | Shared backup + prune logic for dual-storage repos |
| `scripts/exhaustive-prune.sh` | Weekly | Full chunk scan across all repos to reclaim space |
| `scripts/executor_unraid.sh` | _(legacy)_ | NFS-based backup with copy to second destination |
| `scripts/executor_ubuntu.sh` | _(legacy)_ | NFS-based backup for Ubuntu hosts |

### Example Daily Wrapper

```sh
#!/usr/bin/env sh
STORAGENAME="Multimedia"
SNAPSHOTID="Multimedia"
REPO_DIR="/local_shares/Multimedia"
THREADS_OVERRIDE="8"
. /config/dual-executor.sh
```

## Notification Format

Successful backup:

```
🟢 MyServer — appdata
Primary: ✅
Secondary: ✅
🔄 Pruned
```

Skipped (previous run still in progress):

```
⏭️ MyServer — Multimedia
Skipped — previous run still in progress (PID: 325)
```

Failed backup:

```
🔴 MyServer — appdata
Primary: ✅
Secondary: ❌
🔄 Pruned
```

## Guides

- [Deploying Garage S3 (v2.x) and Hooking It Up to Duplicacy](https://geiser.cloud/deploying-garage-s3-v2-x-and-hooking-it-up-to-duplicacy/) — S3 approach (recommended)
- [Backup Bliss: A Dockerized Duplicacy Setup for Your Home Servers](https://geiser.cloud/cool-backups-for-the-people-duplicacy/) — NFS approach (legacy)

## Maintainers

[@GeiserX](https://github.com/GeiserX).

## Contributing

Feel free to dive in! [Open an issue](https://github.com/GeiserX/duplicacy-cli-cron/issues/new) or submit PRs.

Duplicacy CLI (Cron) follows the [Contributor Covenant](http://contributor-covenant.org/version/2/1/) Code of Conduct.

### Contributors

This project exists thanks to all the people who contribute.
<a href="https://github.com/GeiserX/duplicacy-cli-cron/graphs/contributors"><img src="https://opencollective.com/duplicacy-cli-cron/contributors.svg?width=890&button=false" /></a>
