# Configuration

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CRON_DAILY` | `0 2 * * *` | When daily backup scripts run |
| `CRON_WEEKLY` | `0 4 * * 6` | When weekly exhaustive prune runs (Saturday by default) |
| `CRON_MONTHLY` | `0 5 1 * *` | When monthly integrity check runs (1st of month) |
| `DUPLICACY_THREADS` | `4` | Default parallel upload/download threads |
| `HOST` | `$(hostname)` | Machine name shown in notifications |
| `TZ` | `Etc/UTC` | Timezone |
| `SHOUTRRR_URL` | _(empty)_ | Notification URL ([Shoutrrr format](https://containrrr.dev/shoutrrr/)) |
| `ENDPOINT_1` | _(required)_ | S3 endpoint for storage |
| `BUCKET` | _(required)_ | S3 bucket name |
| `REGION` | _(required)_ | S3 region (use `garage` for Garage) |
| `MAX_RUNTIME_HOURS` | `71` | Kill stuck backups after this many hours |

## S3 Credential Convention

Duplicacy resolves credentials from environment variables by storage name:

```
DUPLICACY_<STORAGENAME>_S3_ID       -> S3 access key ID
DUPLICACY_<STORAGENAME>_S3_SECRET   -> S3 secret access key
DUPLICACY_<STORAGENAME>_PASSWORD    -> repository encryption password
```

Example for a storage named `appdata`:

```yaml
DUPLICACY_APPDATA_S3_ID: GKabc123...
DUPLICACY_APPDATA_S3_SECRET: f42b4be...
DUPLICACY_APPDATA_PASSWORD: mySecretPassword
```

## Staggering Backups Across Servers

When multiple servers share the same S3 backend, stagger `CRON_DAILY` to avoid contention:

| Server | `CRON_DAILY` | Description |
|--------|-------------|-------------|
| Server A | `0 2 * * *` | Runs at 2:00 AM |
| Server B | `0 3 * * *` | Runs at 3:00 AM |
| Server C | `0 4 * * *` | Runs at 4:00 AM |

## Filter Files

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

## Lock File and Timeout

Each daily wrapper creates a lock file at `/tmp/duplicacy-<SNAPSHOTID>.lock`. If a previous run is still active:

- **Within `MAX_RUNTIME_HOURS`**: the new run is skipped with a Telegram notification.
- **Exceeds `MAX_RUNTIME_HOURS`**: the stuck process is killed and a fresh backup starts.

## Prune Retention Policy

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
| `scripts/dual-executor.sh` | Daily (sourced) | Shared backup + prune logic |
| `scripts/exhaustive-prune.sh` | Weekly | Full chunk scan across all repos to reclaim space |
| `scripts/monthly-integrity-check.sh` | Monthly | Chunk verification across all repos, one report |

### Example Daily Wrapper

```sh
#!/usr/bin/env sh
STORAGENAME="Multimedia"
SNAPSHOTID="Multimedia"
REPO_DIR="/local_shares/Multimedia"
THREADS_OVERRIDE="8"
. /config/dual-executor.sh
```
