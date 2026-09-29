# Getting started

## 1. Deploy the container

Clone the repository; it holds the compose file, `config/config-s3.sh` and the scripts the next steps
copy:

```bash
git clone https://github.com/GeiserX/duplicacy-cli-cron && cd duplicacy-cli-cron
```

Fill in your values in `docker-compose.yml`:

```yaml
services:
  duplicacy-cli-cron:
    image: drumsergio/duplicacy-cli-cron:3.2.5.7
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
      BUCKET: duplicacy
      REGION: garage
      MAX_RUNTIME_HOURS: "71"
      DUPLICACY_APPDATA_S3_ID: YOUR_S3_ACCESS_KEY
      DUPLICACY_APPDATA_S3_SECRET: YOUR_S3_SECRET_KEY
      DUPLICACY_APPDATA_PASSWORD: YOUR_ENCRYPTION_PASS
```

See [`docker-compose.yml`](https://github.com/GeiserX/duplicacy-cli-cron/blob/main/docker-compose.yml) in this repo for the full example with comments. Start it with `docker compose up -d`.

## 2. Initialize each backup location

Edit `config/config-s3.sh` with your storage name, snapshot ID, and repo path, and copy it into the host directory you mount at `/config`. Then run it inside the container:

```bash
mkdir -p /mnt/user/appdata/duplicacy/config && cp config/config-s3.sh /mnt/user/appdata/duplicacy/config/
```


```bash
docker exec duplicacy-cli-cron sh /config/config-s3.sh
```

Repeat for each folder you want to back up (e.g., `appdata`, `Multimedia`, `system`, `boot`).

## 3. Create daily wrapper scripts

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

## 4. Set up the weekly exhaustive prune

Copy `scripts/exhaustive-prune.sh` to the weekly cron directory:

```bash
cp scripts/exhaustive-prune.sh /mnt/user/appdata/duplicacy/cron/weekly/01-exhaustive-prune.sh
chmod +x /mnt/user/appdata/duplicacy/cron/weekly/01-exhaustive-prune.sh
```

The exhaustive prune auto-discovers all repos under `/local_shares/*/` and prunes them. It also handles extra repos (`/boot_usb` for UnRAID) and respects daily backup lock files to avoid conflicts.

## 5. Set up the monthly integrity check (optional)

Copy `scripts/monthly-integrity-check.sh` to the monthly cron directory:

```bash
cp scripts/monthly-integrity-check.sh /mnt/user/appdata/duplicacy/cron/monthly/01-integrity-check.sh
chmod +x /mnt/user/appdata/duplicacy/cron/monthly/01-integrity-check.sh
```

This script runs `duplicacy check` on every repo and sends one report with the per-repo result. Garage scrubs its own blocks on its own schedule (`garage worker get` on a node shows when the last scrub finished and the next one is due), so nothing here triggers one.
