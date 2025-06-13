#!/usr/bin/env sh
set -eu

STORAGENAME="..."
SNAPSHOTID="..."
REPO="/local_shares/..."

URL="minio://${REGION}@${ENDPOINT}/${BUCKET}/${HOST}/${STORAGENAME}"

cd "$REPO"

if [ ! -f .duplicacy/preferences ]; then
    duplicacy init -e -storage-name "$STORAGENAME" "$SNAPSHOTID" "$URL"
fi

duplicacy list -storage $STORAGENAME