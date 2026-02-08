# Duplicacy CLI (Cron)

A single Docker container that runs [Duplicacy CLI](https://github.com/gilbertchen/duplicacy) backups on a cron schedule to S3-compatible storage. One container handles multiple backup locations, with per-repo lock files, stuck-job timeouts, Telegram notifications, and weekly exhaustive pruning built in.

Primarily designed for UnRAID but works on any Docker host.

## Features

- **Multi-repo backups** from a single container (one daily script per repo)
- **S3-compatible storage** (Garage, MinIO, AWS S3, Backblaze B2, etc.)
- **Encrypted** backups with per-repo passwords
- **Parallel uploads** via configurable `DUPLICACY_THREADS`
- **Staggered cron schedules** across servers to avoid storage contention
- **Lock files** with automatic timeout to kill stuck backups
- **Saturday prune skip** — daily prune skipped when the weekly exhaustive prune runs
- **Weekly exhaustive prune** — reclaims actual storage space by scanning all chunks
- **Filter files** — exclude regenerable caches, thumbnails, and temporary data
- **Telegram notifications** via [Shoutrrr](https://github.com/containrrr/shoutrrr)
- **Boot USB backup** — back up Unraid flash drive config alongside your shares

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
      CRON_WEEKLY: "0 3 * * 6"
      DUPLICACY_THREADS: "16"
      HOST: MyServer
      TZ: Europe/Madrid
      SHOUTRRR_URL: telegram://TOKEN@telegram?chats=CHAT_ID&notification=no&parseMode=markdown
      ENDPOINT: "192.168.1.100:9000"
      BUCKET: duplicacy
      REGION: garage
      # One credential set per storage name:
      DUPLICACY_APPDATA_S3_ID: YOUR_S3_ACCESS_KEY
      DUPLICACY_APPDATA_S3_SECRET: YOUR_S3_SECRET_KEY
      DUPLICACY_APPDATA_PASSWORD: YOUR_ENCRYPTION_PASSWORD
```

See `docker-compose.yml` in this repo for the full example with comments.

### 2. Initialize each backup location

Edit `config/config-s3.sh` with your storage name, snapshot ID, and repo path. Then run it inside the container:

```bash
docker exec duplicacy-cli-cron sh /config/config-s3.sh
```

Repeat for each folder you want to back up (e.g., `appdata`, `Multimedia`, `system`).

### 3. Create daily backup scripts

Copy `scripts/executor-s3.sh`, set the three constants at the top, and place it in the cron directory:

```bash
# Example for appdata
cp scripts/executor-s3.sh /mnt/user/appdata/duplicacy/cron/daily/01-appdata.sh
chmod +x /mnt/user/appdata/duplicacy/cron/daily/01-appdata.sh
```

Edit the constants:

```sh
REPO_DIR="/local_shares/appdata"
STORAGENAME="appdata"
SNAPSHOTID="appdata"
```

### 4. Set up the weekly exhaustive prune

Copy `scripts/exhaustive-prune.sh` to the weekly cron directory:

```bash
cp scripts/exhaustive-prune.sh /mnt/user/appdata/duplicacy/cron/weekly/01-exhaustive-prune.sh
chmod +x /mnt/user/appdata/duplicacy/cron/weekly/01-exhaustive-prune.sh
```

This auto-discovers all repos under `/local_shares/*/` and runs `duplicacy prune -exhaustive` on each. If you have extra repos (like `/boot_usb`), uncomment and customize the extra repos section in the script.

## Configuration Reference

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CRON_DAILY` | `0 2 * * *` | When daily backup scripts run |
| `CRON_WEEKLY` | `0 3 * * 6` | When weekly exhaustive prune runs (Saturday by default) |
| `DUPLICACY_THREADS` | `8` | Parallel upload/download threads |
| `HOST` | `$(hostname)` | Machine name shown in notifications |
| `TZ` | `Etc/UTC` | Timezone |
| `SHOUTRRR_URL` | _(empty)_ | Notification URL ([Shoutrrr format](https://containrrr.dev/shoutrrr/)) |
| `ENDPOINT` | _(required)_ | S3 endpoint for `config-s3.sh` |
| `BUCKET` | _(required)_ | S3 bucket name for `config-s3.sh` |
| `REGION` | _(required)_ | S3 region for `config-s3.sh` |
| `MAX_RUNTIME_HOURS` | `71` | Kill stuck backups after this many hours |

### S3 Credential Convention

Duplicacy resolves credentials from environment variables by storage name:

```
DUPLICACY_<STORAGENAME>_S3_ID       → S3 access key ID
DUPLICACY_<STORAGENAME>_S3_SECRET   → S3 secret access key
DUPLICACY_<STORAGENAME>_PASSWORD    → repository encryption password
```

For a storage named `appdata`:

```yaml
DUPLICACY_APPDATA_S3_ID: GKabc123...
DUPLICACY_APPDATA_S3_SECRET: f42b4be...
DUPLICACY_APPDATA_PASSWORD: mySecretPassword
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

Each daily script creates a lock file at `/tmp/duplicacy-<SNAPSHOTID>.lock`. If a previous run is still active:

- **Within `MAX_RUNTIME_HOURS`**: the new run is skipped with a notification
- **Exceeds `MAX_RUNTIME_HOURS`**: the stuck process is killed and a fresh backup starts

### Saturday Prune Skip

The daily script (`executor-s3.sh`) skips its normal prune step on Saturdays. This avoids overlapping with the weekly exhaustive prune which runs on the same day (configurable via `CRON_WEEKLY`) and performs a more thorough cleanup.

## Scripts

| Script | Schedule | Purpose |
|--------|----------|---------|
| `scripts/executor-s3.sh` | Daily | Backup + prune for a single S3-backed repo |
| `scripts/exhaustive-prune.sh` | Weekly | Full chunk scan across all repos to reclaim space |
| `scripts/executor_unraid.sh` | _(legacy)_ | NFS-based backup with copy to second destination |
| `scripts/executor_ubuntu.sh` | _(legacy)_ | NFS-based backup for Ubuntu hosts |

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
