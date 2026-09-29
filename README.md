<p align="center">
  <img src="https://raw.githubusercontent.com/GeiserX/duplicacy-cli-cron/main/docs/images/banner.svg" alt="duplicacy-cli-cron banner" width="900" />
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
- **Telegram notifications** -- via [Shoutrrr](https://github.com/containrrr/shoutrrr) (supports 70+ services)
- **Multi-architecture, Alpine-based image** -- amd64, arm64, armv7
- **UnRAID and Linux support** -- back up shares, boot USB, `/etc`, `/home`, crontabs, Tailscale state

## Quick start

Fill in [`docker-compose.yml`](https://github.com/GeiserX/duplicacy-cli-cron/blob/main/docker-compose.yml) and `config/config-s3.sh`, then:

```bash
docker compose up -d
docker exec duplicacy-cli-cron sh /config/config-s3.sh
```

Then add one daily wrapper script per repository, plus the weekly prune and monthly check. The [installation guide](https://github.com/GeiserX/duplicacy-cli-cron/blob/main/docs/installation.md) walks through every step.

## Documentation

- [Installation](https://github.com/GeiserX/duplicacy-cli-cron/blob/main/docs/installation.md): deploy, initialize, wrapper scripts, prune and integrity check
- [Configuration](https://github.com/GeiserX/duplicacy-cli-cron/blob/main/docs/configuration.md): environment variables, S3 credentials, staggering, filters, locks, retention, scripts
- [Backup verification and notifications](https://github.com/GeiserX/duplicacy-cli-cron/blob/main/docs/verification.md): list, check, restore, storage usage, message formats
- [Troubleshooting](https://github.com/GeiserX/duplicacy-cli-cron/blob/main/docs/troubleshooting.md)
- [Architecture](https://github.com/GeiserX/duplicacy-cli-cron/blob/main/docs/architecture.md)
- [Guides, related projects and contributing](https://github.com/GeiserX/duplicacy-cli-cron/blob/main/docs/community.md), including the Garage S3 setup guide

## Related projects

[duplicacy-container](https://github.com/GeiserX/duplicacy-container), [duplicacy-exporter](https://github.com/GeiserX/duplicacy-exporter), [duplicacy-ha](https://github.com/GeiserX/duplicacy-ha), [Duplicacy](https://duplicacy.com).

## License

[GPL-3.0](https://github.com/GeiserX/duplicacy-cli-cron/blob/main/LICENSE)
