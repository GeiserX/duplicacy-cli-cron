# Troubleshooting

## Backup skipped every day ("previous run still in progress")

A stale lock file may be left behind if the container was restarted mid-backup. Remove it manually:

```bash
docker exec duplicacy-cli-cron rm -f /tmp/duplicacy-<SNAPSHOTID>.lock
```

If the problem recurs, your backup may genuinely need more time. Increase `MAX_RUNTIME_HOURS` or reduce the data volume being backed up.

## "Storage not found" or initialization errors

Each repo directory must be initialized with `duplicacy init` before backups can run. Verify the `.duplicacy` directory exists:

```bash
docker exec duplicacy-cli-cron ls -la /local_shares/appdata/.duplicacy/
```

If missing, re-run the initialization script:

```bash
docker exec duplicacy-cli-cron sh /config/config-s3.sh
```

## Container logs show no cron output

Cron job output is redirected to PID 1 stdout so Docker can capture it. Check with:

```bash
docker logs --tail 100 duplicacy-cli-cron
```

If logs are empty, verify the cron scripts are executable:

```bash
docker exec duplicacy-cli-cron ls -la /etc/periodic/daily/
```

All wrapper scripts must have the execute bit set (`chmod +x`).

## Exhaustive prune takes too long

The weekly exhaustive prune scans all chunks across all repos. For large repositories, this is expected. If it overlaps with daily backups, it will wait up to 1 hour for locks to clear. Options:

- Stagger the weekly schedule earlier (e.g., `CRON_WEEKLY: "0 0 * * 6"`)
- Ensure daily backups finish well before the weekly prune starts

## High memory usage during backup

Duplicacy's memory usage scales with thread count. If the container is being OOM-killed:

- Lower `DUPLICACY_THREADS` or `THREADS_OVERRIDE`
- Add a memory limit in your `docker-compose.yml`: `mem_limit: 512m`
