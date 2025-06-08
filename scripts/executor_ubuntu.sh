#!/bin/sh    
set -o pipefail 
MY_LOCATION=...
MY_DESTINATION=...
MY_SECOND_DESTINATION=...
MachineName=...
SHOUTRRR_URL="${SHOUTRRR_URL:-}"

send_notification() {
  if [ -n "$SHOUTRRR_URL" ]; then
    /usr/local/bin/shoutrrr send -u "${SHOUTRRR_URL}" -m "$1"
  fi
}

echo "#######################################"
echo "Starting backups for /local_${MY_LOCATION}/"
echo "#######################################"

cd /local_${MY_LOCATION}/

### BACKUP ###
echo "--- Backup Output ---"
tmp_backup_output=$(mktemp)
/bin/sh -c 'duplicacy backup -stats' 2>&1 | tee "$tmp_backup_output"
BACKUP_EXIT_CODE=$?
BACKUP_OUTPUT=$(cat "$tmp_backup_output")
rm "$tmp_backup_output"

if [ ${BACKUP_EXIT_CODE} -eq 0 ]; then
  MSG_BACKUP="✅ Backup completed successfully for ${MY_LOCATION}"
else
  MSG_BACKUP="🚨 Backup failed for ${MY_LOCATION}. Check logs for more info."
fi

### PRUNE ###
echo "--- Prune Output (storage ${MY_DESTINATION}) ---"
tmp_prune_output=$(mktemp)
/bin/sh -c 'duplicacy prune -keep 0:360 -keep 30:180 -keep 7:30 -keep 1:7' 2>&1 | tee "$tmp_prune_output"
PRUNE_EXIT_CODE=$?
PRUNE_OUTPUT=$(cat "$tmp_prune_output")
rm "$tmp_prune_output"

if [ ${PRUNE_EXIT_CODE} -eq 0 ]; then
  MSG_PRUNE="✅ Prune completed successfully for ${MY_DESTINATION}"
else
  MSG_PRUNE="🚨 Prune failed for ${MY_LOCATION}. Check logs for more info."
fi

### BACKUP COPY ###
echo "--- Copy Output (${MY_DESTINATION} to ${MY_SECOND_DESTINATION}) ---"
tmp_copy_output=$(mktemp)
/bin/sh -c "duplicacy copy -from ${MY_LOCATION}-${MY_DESTINATION} -to ${MY_LOCATION}-${MY_SECOND_DESTINATION}" 2>&1 | tee "$tmp_copy_output"
COPY_EXIT_CODE=$?
COPY_OUTPUT=$(cat "$tmp_copy_output")
rm "$tmp_copy_output"

if [ ${COPY_EXIT_CODE} -eq 0 ]; then
  MSG_COPY="✅ Copy completed successfully from ${MY_DESTINATION} to ${MY_SECOND_DESTINATION}"
else
  MSG_COPY="🚨 Copy failed from ${MY_DESTINATION} to ${MY_SECOND_DESTINATION}. Check logs for more info."
fi

### PRUNE AGAIN ###
echo "--- Second Prune Output (storage ${MY_SECOND_DESTINATION}) ---"
tmp_prune2_output=$(mktemp)
/bin/sh -c "duplicacy prune -storage ${MY_LOCATION}-${MY_SECOND_DESTINATION} -keep 0:360 -keep 30:180 -keep 7:30 -keep 1:7" 2>&1 | tee "$tmp_prune2_output"
PRUNE2_EXIT_CODE=$?
PRUNE2_OUTPUT=$(cat "$tmp_prune2_output")
rm "$tmp_prune2_output"

if [ ${PRUNE2_EXIT_CODE} -eq 0 ]; then
  MSG_PRUNE2="✅ Prune2 completed successfully for ${MY_SECOND_DESTINATION}"
else
  MSG_PRUNE2="🚨 Prune2 failed for ${MY_LOCATION}. Check logs for more info."
fi

### SEND MESSAGE ###
NOTIFY_MESSAGE=$(cat << EOF
🖥️ *${MachineName}* - _${MY_LOCATION}_
---------------------------------------------
${MSG_BACKUP}
${MSG_PRUNE}
${MSG_COPY}
${MSG_PRUNE2}
EOF
)

echo "--- Notification Sent ---"
echo -e "${NOTIFY_MESSAGE}"
send_notification "${NOTIFY_MESSAGE}"