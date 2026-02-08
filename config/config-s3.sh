#!/usr/bin/env sh
set -eu

# ───────── S3 Repository Initialization ────────────────────────────────────
# Run this script once per backup location to initialize the Duplicacy repo
# and connect it to your S3-compatible storage (Garage, MinIO, AWS S3, etc.).
#
# Prerequisites:
#   The following env vars must be set in docker-compose.yml:
#     ENDPOINT  – S3 endpoint          (e.g. 192.168.1.100:9000)
#     BUCKET    – S3 bucket name       (e.g. duplicacy)
#     REGION    – S3 region            (e.g. garage)
#     HOST      – Machine identifier   (e.g. WatchTower)
#
#   Duplicacy resolves credentials from env vars by storage name:
#     DUPLICACY_<STORAGENAME>_S3_ID       → S3 access key ID
#     DUPLICACY_<STORAGENAME>_S3_SECRET   → S3 secret access key
#     DUPLICACY_<STORAGENAME>_PASSWORD    → repository encryption password
#
# Usage:
#   1. Fill in STORAGENAME, SNAPSHOTID, and REPO below
#   2. Run: docker exec duplicacy-cli-cron sh /config/config-s3.sh
# ───────────────────────────────────────────────────────────────────────────

# ── Customize these three values ──────────────────────────────────────────
STORAGENAME="..."    # Duplicacy storage name (e.g. appdata, Multimedia)
SNAPSHOTID="..."     # Snapshot identifier    (usually same as STORAGENAME)
REPO="/local_shares/..."  # Container path to the folder to back up
# ──────────────────────────────────────────────────────────────────────────

URL="minio://${REGION}@${ENDPOINT}/${BUCKET}/${HOST}/${STORAGENAME}"

cd "$REPO"

if [ ! -f .duplicacy/preferences ]; then
    echo "Initializing Duplicacy repo at ${REPO}"
    echo "  Storage: ${URL}"
    echo "  Snapshot ID: ${SNAPSHOTID}"
    duplicacy init -e -storage-name "$STORAGENAME" "$SNAPSHOTID" "$URL"
else
    echo "Duplicacy repo already initialized at ${REPO}"
fi

echo ""
echo "Verifying storage connection..."
duplicacy list -storage "$STORAGENAME"
