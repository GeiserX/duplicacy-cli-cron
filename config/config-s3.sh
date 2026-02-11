#!/usr/bin/env sh
set -eu

# ───────── S3 Dual-Storage Initialization ─────────────────────────────────────
# Run this script once per backup location to initialize two Duplicacy storages:
#   1. Primary:   backs up to ENDPOINT_1 (one remote server)
#   2. Secondary: backs up to ENDPOINT_2 (another remote server)
#
# This implements the cross-backup architecture: each server's data is stored
# ONLY on the other two servers, never on itself.
#
# Prerequisites:
#   The following env vars must be set in docker-compose.yml:
#     ENDPOINT_1 – S3 endpoint of first remote  (e.g. 192.168.1.100:9000)
#     ENDPOINT_2 – S3 endpoint of second remote  (e.g. 192.168.1.200:9000)
#     BUCKET     – S3 bucket name                (e.g. duplicacy)
#     REGION     – S3 region                     (e.g. garage)
#     HOST       – Machine identifier            (e.g. WatchTower)
#
#   Duplicacy resolves credentials from env vars by storage name:
#     DUPLICACY_<STORAGENAME>_S3_ID       → S3 access key ID (primary)
#     DUPLICACY_<STORAGENAME>_S3_SECRET   → S3 secret access key (primary)
#     DUPLICACY_<STORAGENAME>_PASSWORD    → repository encryption password (primary)
#     DUPLICACY_<STORAGENAME>C_S3_ID      → S3 access key ID (secondary)
#     DUPLICACY_<STORAGENAME>C_S3_SECRET  → S3 secret access key (secondary)
#     DUPLICACY_<STORAGENAME>C_PASSWORD   → repository encryption password (secondary)
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

STORAGENAME_C="${STORAGENAME}C"

URL_1="minio://${REGION}@${ENDPOINT_1}/${BUCKET}/${HOST}/${STORAGENAME}"
URL_2="minio://${REGION}@${ENDPOINT_2}/${BUCKET}/${HOST}/${STORAGENAME}"

cd "$REPO"

if [ ! -f .duplicacy/preferences ]; then
    echo "Initializing Duplicacy repo at ${REPO}"
    echo "  Primary storage ($STORAGENAME): ${URL_1}"
    echo "  Snapshot ID: ${SNAPSHOTID}"
    duplicacy init -e -storage-name "$STORAGENAME" "$SNAPSHOTID" "$URL_1"
    echo ""
    echo "Adding secondary storage ($STORAGENAME_C): ${URL_2}"
    duplicacy add -e -copy -storage-name "$STORAGENAME_C" "$SNAPSHOTID" "$URL_2"
else
    echo "Duplicacy repo already initialized at ${REPO}"
fi

echo ""
echo "Verifying primary storage connection..."
duplicacy list -storage "$STORAGENAME"

echo ""
echo "Verifying secondary storage connection..."
duplicacy list -storage "$STORAGENAME_C"
