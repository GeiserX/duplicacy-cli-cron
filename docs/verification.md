# Backup verification and notifications

## List snapshots

```bash
docker exec duplicacy-cli-cron sh -c \
  'cd /local_shares/appdata && duplicacy list -storage appdata'
```

## Check backup integrity

Run an on-demand integrity check for a specific repo:

```bash
docker exec duplicacy-cli-cron sh -c \
  'cd /local_shares/appdata && duplicacy check -storage appdata -threads 4'
```

## Restore a file or directory

To restore from a specific revision to a target path:

```bash
docker exec duplicacy-cli-cron sh -c \
  'cd /local_shares/appdata && duplicacy restore -r 42 -storage appdata -stats'
```

Add `-overwrite` to replace existing files, or use `-delete` to remove files not present in the snapshot. See the [Duplicacy CLI restore docs](https://github.com/gilbertchen/duplicacy/wiki/restore) for full options.

## Verify storage usage

For Garage S3 storage, check bucket sizes to confirm data is being stored:

```bash
# Using the Garage admin API, on the Garage node itself (or through an SSH tunnel to it):
# the admin API speaks plain HTTP, so the token must never cross the network in the clear.
curl -s -H "Authorization: Bearer <garage-admin-token>" \
  http://127.0.0.1:3903/v2/GetBucketInfo?id=YOUR_BUCKET_ID | jq .bytes
```

## Notification format

Successful backup:

```
[green] MyServer -- appdata
[ok] [sync] Pruned
```

Skipped (previous run still in progress):

```
[skip] MyServer -- Multimedia
Skipped -- previous run still in progress (PID: 325)
```

Failed backup:

```
[red] MyServer -- appdata
[fail] [sync] Pruned
```

Stuck job killed:

```
[warn] MyServer -- appdata
Killed after 71h timeout (PID: 1234)
```
