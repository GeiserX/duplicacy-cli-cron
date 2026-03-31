<p align="center">
  <img src="docs/images/banner.svg" alt="duplicacy-cli-cron banner" width="900" />
</p>

<p align="center">
  <a href="https://hub.docker.com/r/drumsergio/duplicacy-cli-cron"><img src="https://img.shields.io/docker/v/drumsergio/duplicacy-cli-cron?sort=semver&style=flat-square&logo=docker&label=Docker%20Hub&color=1B9AAA" alt="Docker Hub version" /></a>
  <a href="https://hub.docker.com/r/drumsergio/duplicacy-cli-cron"><img src="https://img.shields.io/docker/image-size/drumsergio/duplicacy-cli-cron?sort=semver&style=flat-square&color=0D1B2A" alt="Docker image size" /></a>
  <a href="https://hub.docker.com/r/drumsergio/duplicacy-cli-cron"><img src="https://img.shields.io/docker/pulls/drumsergio/duplicacy-cli-cron?style=flat-square&logo=docker&color=1B9AAA" alt="Docker pulls" /></a>
  <a href="https://github.com/GeiserX/duplicacy-cli-cron/blob/main/LICENSE"><img src="https://img.shields.io/github/license/GeiserX/duplicacy-cli-cron?style=flat-square&color=0D1B2A" alt="License" /></a>
  <a href="https://github.com/GeiserX/duplicacy-cli-cron/stargazers"><img src="https://img.shields.io/github/stars/GeiserX/duplicacy-cli-cron?style=flat-square&logo=github&color=1B9AAA" alt="GitHub stars" /></a>
</p>

<p align="center">
  A Docker container that runs <a href="https://github.com/gilbertchen/duplicacy">Duplicacy CLI</a> backups on a cron schedule<br />
  to <strong>two independent S3-compatible storages</strong> for cross-site redundancy.
</p>

---

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Quick Start](#quick-start)
- [Configuration Reference](#configuration-reference)
- [Scripts](#scripts)
- [Backup Verification](#backup-verification)
- [Notification Format](#notification-format)
- [Troubleshooting](#troubleshooting)
- [Guides](#guides)
- [Contributing](#contributing)

## Features

- **Dual-storage backups** -- every backup writes to two independent S3 endpoints (cross-site redundancy)
- **Multi-repo from a single container** -- one tiny daily wrapper per repository
- **S3-compatible storage** -- Garage, MinIO, AWS S3, Backblaze B2, and any S3-compatible provider
- **AES-256-GCM encryption** -- per-repo encryption passwords
- **Parallel uploads** -- configurable thread count via `DUPLICACY_THREADS`
- **Staggered cron schedules** -- avoid storage contention across servers
- **Per-repo lock files** -- automatic timeout kills stuck backups after `MAX_RUNTIME_HOURS`
- **Retry with exponential backoff** -- secondary storage retries with configurable attempts
- **Secondary endpoint pre-flight** -- verifies S3 reachability before attempting backup
- **Weekly exhaustive prune** -- reclaims actual storage space by scanning all chunks
- **Monthly integrity check** -- verifies all backup chunks and triggers Garage data scrubs
- **Filter files** -- exclude caches, thumbnails, and temporary data
- **Telegram notifications** -- via [Shoutrrr](https://github.com/containrrr/shoutrrr) (supports 70+ services)
- **Multi-architecture Docker image** -- amd64, arm64, armv7
- **Alpine-based** -- minimal image footprint
- **UnRAID and Linux support** -- back up shares, boot USB, `/etc`, `/home`, crontabs, Tailscale state

## Architecture

Each server backs up to **two remote S3 endpoints** (never to itself), ensuring data survives the loss of any single node:

```
Server A --backup--> S3 on Server B (primary)
           --backup--> S3 on Server C (secondary)

Server B --backup--> S3 on Server A (primary)
           --backup--> S3 on Server C (secondary)

Server C --backup--> S3 on Server A (primary)
           --backup--> S3 on Server B (secondary)
```

The daily wrapper scripts are four lines each and source the shared `dual-executor.sh`, which handles locking, backup, prune, and notification logic.

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

> **Tip:** Use `THREADS_OVERRIDE` per repo to tune performance. For HDD-backed repos with large files (media), lower threads (4-8) reduce disk seek contention. For SSD/NVMe or small-file repos, higher threads (8-16) improve throughput.

### 4. Set up the weekly exhaustive prune

Copy `scripts/exhaustive-prune.sh` to the weekly cron directory:

```bash
cp scripts/exhaustive-prune.sh /mnt/user/appdata/duplicacy/cron/weekly/01-exhaustive-prune.sh
chmod +x /mnt/user/appdata/duplicacy/cron/weekly/01-exhaustive-prune.sh
```

The exhaustive prune auto-discovers all repos under `/local_shares/*/` and prunes both primary and secondary storages. It also handles extra repos (`/boot_usb` for UnRAID, `/local_*` for Ubuntu/Debian) and respects daily backup lock files to avoid conflicts.

### 5. Set up the monthly integrity check (optional)

Copy `scripts/monthly-integrity-check.sh` to the monthly cron directory:

```bash
cp scripts/monthly-integrity-check.sh /mnt/user/appdata/duplicacy/cron/monthly/01-integrity-check.sh
chmod +x /mnt/user/appdata/duplicacy/cron/monthly/01-integrity-check.sh
```

This script verifies all backup chunks across every repo and, if you use Garage, triggers a data scrub on both target storage nodes.

## Configuration Reference

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CRON_DAILY` | `0 2 * * *` | When daily backup scripts run |
| `CRON_WEEKLY` | `0 4 * * 6` | When weekly exhaustive prune runs (Saturday by default) |
| `CRON_MONTHLY` | `0 5 1 * *` | When monthly integrity check runs (1st of month) |
| `DUPLICACY_THREADS` | `4` | Default parallel upload/download threads |
| `HOST` | `$(hostname)` | Machine name shown in notifications |
| `TZ` | `Etc/UTC` | Timezone |
| `SHOUTRRR_URL` | _(empty)_ | Notification URL ([Shoutrrr format](https://containrrr.dev/shoutrrr/)) |
| `ENDPOINT_1` | _(required)_ | S3 endpoint for primary storage |
| `ENDPOINT_2` | _(required)_ | S3 endpoint for secondary storage |
| `BUCKET` | _(required)_ | S3 bucket name |
| `REGION` | _(required)_ | S3 region (use `garage` for Garage) |
| `MAX_RUNTIME_HOURS` | `71` | Kill stuck backups after this many hours |
| `SECONDARY_RETRIES` | `3` | Max retry attempts for secondary storage |
| `SECONDARY_PREFLIGHT_TIMEOUT` | `120` | Seconds to wait for secondary endpoint reachability |
| `GARAGE_ADMIN_TOKEN` | _(empty)_ | Garage admin API token (for monthly scrub trigger) |

### S3 Credential Convention

Duplicacy resolves credentials from environment variables by storage name. For dual-storage, you need **two sets** -- one for the primary and one for the secondary (C-suffix):

```
# Primary storage
DUPLICACY_<STORAGENAME>_S3_ID       -> S3 access key ID
DUPLICACY_<STORAGENAME>_S3_SECRET   -> S3 secret access key
DUPLICACY_<STORAGENAME>_PASSWORD    -> repository encryption password

# Secondary storage (same name + "C" suffix)
DUPLICACY_<STORAGENAME>C_S3_ID     -> S3 access key ID
DUPLICACY_<STORAGENAME>C_S3_SECRET -> S3 secret access key
DUPLICACY_<STORAGENAME>C_PASSWORD  -> repository encryption password
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

- **Within `MAX_RUNTIME_HOURS`**: the new run is skipped with a Telegram notification.
- **Exceeds `MAX_RUNTIME_HOURS`**: the stuck process is killed and a fresh backup starts.

### Prune Retention Policy

Daily prune (skipped on Saturdays when the weekly exhaustive prune runs):

```
-keep 0:180    # Delete all snapshots older than 180 days
-keep 30:90    # Keep one snapshot every 30 days if older than 90 days
-keep 7:30     # Keep one snapshot every 7 days if older than 30 days
-keep 1:7      # Keep one snapshot every day if older than 7 days
```

Weekly exhaustive prune runs with the `-exhaustive` flag to scan all chunks and reclaim actual storage space.

## Scripts

| Script | Schedule | Purpose |
|--------|----------|---------|
| `scripts/dual-executor.sh` | Daily (sourced) | Shared backup + prune logic for dual-storage repos |
| `scripts/exhaustive-prune.sh` | Weekly | Full chunk scan across all repos to reclaim space |
| `scripts/monthly-integrity-check.sh` | Monthly | Chunk verification and Garage scrub trigger |
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

## Backup Verification

### List snapshots

Verify that snapshots are being created on both storages:

```bash
docker exec duplicacy-cli-cron sh -c \
  'cd /local_shares/appdata && duplicacy list -storage appdata'

docker exec duplicacy-cli-cron sh -c \
  'cd /local_shares/appdata && duplicacy list -storage appdataC'
```

### Check backup integrity

Run an on-demand integrity check for a specific repo:

```bash
docker exec duplicacy-cli-cron sh -c \
  'cd /local_shares/appdata && duplicacy check -storage appdata -threads 4'
```

### Restore a file or directory

To restore from a specific revision to a target path:

```bash
docker exec duplicacy-cli-cron sh -c \
  'cd /local_shares/appdata && duplicacy restore -r 42 -storage appdata -stats'
```

Add `-overwrite` to replace existing files, or use `-delete` to remove files not present in the snapshot. See the [Duplicacy CLI restore docs](https://github.com/gilbertchen/duplicacy/wiki/restore) for full options.

### Verify storage usage

For Garage S3 storage, check bucket sizes to confirm both destinations are receiving data:

```bash
# Using the Garage admin API
curl -s -H "Authorization: Bearer ${GARAGE_ADMIN_TOKEN}" \
  http://192.168.1.100:3903/v2/GetBucketInfo?id=YOUR_BUCKET_ID | jq .bytes
```

## Notification Format

Successful backup:

```
[green] MyServer -- appdata
Primary: [ok]
Secondary: [ok]
[sync] Pruned
```

Skipped (previous run still in progress):

```
[skip] MyServer -- Multimedia
Skipped -- previous run still in progress (PID: 325)
```

Failed backup:

```
[red] MyServer -- appdata
Primary: [ok]
Secondary: [fail]
[sync] Pruned
```

Stuck job killed:

```
[warn] MyServer -- appdata
Killed after 71h timeout (PID: 1234)
```

## Troubleshooting

### Backup skipped every day ("previous run still in progress")

A stale lock file may be left behind if the container was restarted mid-backup. Remove it manually:

```bash
docker exec duplicacy-cli-cron rm -f /tmp/duplicacy-<SNAPSHOTID>.lock
```

If the problem recurs, your backup may genuinely need more time. Increase `MAX_RUNTIME_HOURS` or reduce the data volume being backed up.

### Secondary storage always fails

1. **Verify endpoint reachability** from inside the container:
   ```bash
   docker exec duplicacy-cli-cron wget -q -O /dev/null -T 5 http://192.168.1.200:9000/
   ```
   Exit code 0 or 8 (HTTP 403) means the endpoint is reachable.

2. **Check credentials**: ensure the `DUPLICACY_<STORAGENAME>C_S3_ID` and `DUPLICACY_<STORAGENAME>C_S3_SECRET` variables match the secondary storage's access keys.

3. **Increase retry attempts**: set `SECONDARY_RETRIES=5` for unreliable network links.

### "Storage not found" or initialization errors

Each repo directory must be initialized with `duplicacy init` before backups can run. Verify the `.duplicacy` directory exists:

```bash
docker exec duplicacy-cli-cron ls -la /local_shares/appdata/.duplicacy/
```

If missing, re-run the initialization script:

```bash
docker exec duplicacy-cli-cron sh /config/config-s3.sh
```

### Container logs show no cron output

Cron job output is redirected to PID 1 stdout so Docker can capture it. Check with:

```bash
docker logs --tail 100 duplicacy-cli-cron
```

If logs are empty, verify the cron scripts are executable:

```bash
docker exec duplicacy-cli-cron ls -la /etc/periodic/daily/
```

All wrapper scripts must have the execute bit set (`chmod +x`).

### Exhaustive prune takes too long

The weekly exhaustive prune scans all chunks across all repos. For large repositories, this is expected. If it overlaps with daily backups, it will wait up to 1 hour for locks to clear. Options:

- Stagger the weekly schedule earlier (e.g., `CRON_WEEKLY: "0 0 * * 6"`)
- Ensure daily backups finish well before the weekly prune starts

### High memory usage during backup

Duplicacy's memory usage scales with thread count. If the container is being OOM-killed:

- Lower `DUPLICACY_THREADS` or `THREADS_OVERRIDE`
- Add a memory limit in your `docker-compose.yml`: `mem_limit: 512m`

## Guides

- [Deploying Garage S3 (v2.x) and Hooking It Up to Duplicacy](https://geiser.cloud/deploying-garage-s3-v2-x-and-hooking-it-up-to-duplicacy/) -- S3 approach (recommended)
- [Backup Bliss: A Dockerized Duplicacy Setup for Your Home Servers](https://geiser.cloud/cool-backups-for-the-people-duplicacy/) -- NFS approach (legacy)

## Monitoring & Home Assistant

| Project | Description |
|---------|-------------|
| [duplicacy-exporter](https://github.com/GeiserX/duplicacy-exporter) | Prometheus exporter for real-time backup metrics |
| [duplicacy-ha](https://github.com/GeiserX/duplicacy-ha) | Home Assistant integration for backup monitoring |


## Contributing

Contributions are welcome. [Open an issue](https://github.com/GeiserX/duplicacy-cli-cron/issues/new) or submit a pull request.

This project follows the [Contributor Covenant](http://contributor-covenant.org/version/2/1/) Code of Conduct.

## License

[GPL-3.0](LICENSE)

## Maintainers

[@GeiserX](https://github.com/GeiserX)
