<p align="center">
  <img src="https://raw.githubusercontent.com/GeiserX/duplicacy-cli-cron/main/docs/images/banner.svg" alt="duplicacy-cli-cron" width="900" />
</p>

<p align="center">
  <a href="https://hub.docker.com/r/drumsergio/duplicacy-cli-cron"><img src="https://img.shields.io/docker/v/drumsergio/duplicacy-cli-cron?sort=semver&style=flat-square&logo=docker&label=Docker%20Hub&color=1B9AAA" alt="Docker Hub version" /></a>
  <a href="https://github.com/GeiserX/duplicacy-cli-cron/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/GeiserX/duplicacy-cli-cron/ci.yml?style=flat-square&logo=github&label=CI" alt="CI" /></a>
  <a href="https://github.com/GeiserX/duplicacy-cli-cron/blob/main/LICENSE"><img src="https://img.shields.io/github/license/GeiserX/duplicacy-cli-cron?style=flat-square&color=0D1B2A" alt="License" /></a>
  <a href="https://hub.docker.com/r/drumsergio/duplicacy-cli-cron"><img src="https://img.shields.io/docker/pulls/drumsergio/duplicacy-cli-cron?style=flat-square&logo=docker&color=1B9AAA" alt="Docker pulls" /></a>
  <a href="https://github.com/GeiserX/duplicacy-cli-cron/stargazers"><img src="https://img.shields.io/github/stars/GeiserX/duplicacy-cli-cron?style=flat-square&logo=github&color=1B9AAA" alt="GitHub stars" /></a>
</p>

<p align="center">
  A Docker container that runs <a href="https://github.com/gilbertchen/duplicacy">Duplicacy CLI</a> backups on a cron schedule<br />
  to an <strong>S3-compatible storage</strong> with encryption, pruning, and notifications.
</p>

---

## Features

- **S3-compatible storage** -- Garage, MinIO, AWS S3, Backblaze B2, and any S3-compatible provider
- **Multi-repo from a single container** -- one tiny daily wrapper per repository, with per-repo AES-256-GCM encryption passwords
- **Parallel uploads and staggered schedules** -- `DUPLICACY_THREADS` per container, `CRON_DAILY` per server
- **Per-repo lock files** -- automatic timeout kills stuck backups after `MAX_RUNTIME_HOURS`
- **Weekly exhaustive prune** -- reclaims actual storage space by scanning all chunks
- **Monthly integrity check** -- verifies every backup chunk in every repo and reports the result
- **Notifications** -- Telegram by default, or any of the 20+ services [Shoutrrr](https://github.com/containrrr/shoutrrr) speaks (Discord, Slack, ntfy, Gotify, email...)
- **Multi-architecture, Alpine-based image** -- amd64 and arm64
- **UnRAID and Linux support** -- back up shares, boot USB, `/etc`, `/home`, crontabs, Tailscale state

## Quick start

Edit `docker-compose.yml` (mounts, S3 endpoint, credentials, `SHOUTRRR_URL`) and `config/config-s3.sh` after cloning, then copy `config-s3.sh` into the host directory you mount at `/config`:

```bash
git clone https://github.com/GeiserX/duplicacy-cli-cron && cd duplicacy-cli-cron
mkdir -p /mnt/user/appdata/duplicacy/config && cp config/config-s3.sh /mnt/user/appdata/duplicacy/config/
docker compose up -d
docker exec duplicacy-cli-cron sh /config/config-s3.sh
```

Then add one daily wrapper script per repository, plus the weekly prune and monthly check. [Getting started](https://github.com/GeiserX/duplicacy-cli-cron/blob/main/docs/getting-started.md) walks through every step.

## Documentation

- [Getting started](https://github.com/GeiserX/duplicacy-cli-cron/blob/main/docs/getting-started.md): deploy, initialize, wrapper scripts, prune and integrity check
- [Configuration](https://github.com/GeiserX/duplicacy-cli-cron/blob/main/docs/configuration.md): environment variables, S3 credentials, staggering, filters, locks, retention, scripts
- [Usage](https://github.com/GeiserX/duplicacy-cli-cron/blob/main/docs/usage.md): list, check and restore snapshots, storage usage, notification formats
- [How it works](https://github.com/GeiserX/duplicacy-cli-cron/blob/main/docs/how-it-works.md)
- [Troubleshooting](https://github.com/GeiserX/duplicacy-cli-cron/blob/main/docs/troubleshooting.md)
- [Development](https://github.com/GeiserX/duplicacy-cli-cron/blob/main/docs/development.md): building the image, contributing
- [Related projects](https://github.com/GeiserX/duplicacy-cli-cron/blob/main/docs/related.md): the Garage S3 setup guide, monitoring, the Duplicacy family

## Related projects

[duplicacy-container](https://github.com/GeiserX/duplicacy-container), [duplicacy-exporter](https://github.com/GeiserX/duplicacy-exporter), [duplicacy-ha](https://github.com/GeiserX/duplicacy-ha), [duplicacy-mcp](https://github.com/GeiserX/duplicacy-mcp), [Duplicacy](https://duplicacy.com).

## License

[GPL-3.0-or-later](https://github.com/GeiserX/duplicacy-cli-cron/blob/main/LICENSE)
