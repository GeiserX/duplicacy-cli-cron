#!/usr/bin/env sh
set -eu

# ───────── S3 Storage Initialization ─────────────────────────────────────────
# Run this script once per backup location to initialize a Duplicacy storage.
# Garage S3 replication factor 3 handles redundancy across all cluster nodes.
#
# Prerequisites:
#   The following env vars must be set in docker-compose.yml:
#     ENDPOINT_1 – S3 endpoint           (e.g. 192.168.10.110:3900)
#     BUCKET     – S3 bucket name        (e.g. duplicacy)
#     REGION     – S3 region             (e.g. garage)
#     HOST       – Machine identifier    (e.g. WatchTower)
#
#   Duplicacy resolves credentials from env vars by storage name:
#     DUPLICACY_<STORAGENAME>_S3_ID       → S3 access key ID
#     DUPLICACY_<STORAGENAME>_S3_SECRET   → S3 secret access key
#     DUPLICACY_<STORAGENAME>_PASSWORD    → repository encryption password
#
# Usage:
#   1. Fill in STORAGENAME, SNAPSHOTID, and REPO below
#   2. Run: docker exec duplicacy-cli-cron sh /config/<name>-config.sh
# ───────────────────────────────────────────────────────────────────────────────

# ── Customize these three values ──────────────────────────────────────────────
STORAGENAME="..."    # Duplicacy storage name (e.g. appdata, Multimedia)
SNAPSHOTID="..."     # Snapshot identifier    (usually same as STORAGENAME)
REPO="/local_shares/..."  # Container path to the folder to back up
# ──────────────────────────────────────────────────────────────────────────────

URL="minio://${REGION}@${ENDPOINT_1}/${BUCKET}/${HOST}/${STORAGENAME}"

cd "$REPO"

if [ ! -f .duplicacy/preferences ]; then
    echo "Initializing Duplicacy repo at ${REPO}"
    echo "  Storage ($STORAGENAME): ${URL}"
    echo "  Snapshot ID: ${SNAPSHOTID}"
    duplicacy init -e -storage-name "$STORAGENAME" "$SNAPSHOTID" "$URL"
else
    echo "Duplicacy repo already initialized at ${REPO}"
fi

echo ""
echo "Verifying storage connection..."
duplicacy list -storage "$STORAGENAME"
