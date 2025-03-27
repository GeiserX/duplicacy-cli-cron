#!/bin/sh     
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
BACKUP_OUTPUT=$(duplicacy backup -stats 2>&1)
BACKUP_EXIT_CODE=$?
if [ ${BACKUP_EXIT_CODE} -eq 0 ]; then
  MSG_BACKUP="✅ Backup completed successfully for ${MY_LOCATION}"
else
  MSG_BACKUP="🚨 Backup failed for ${MY_LOCATION}. Check logs for more info."
fi

### PRUNE ###
PRUNE_OUTPUT=$(duplicacy prune -keep 0:360 -keep 30:180 -keep 7:30 -keep 1:7 2>&1)
PRUNE_EXIT_CODE=$?
if [ ${PRUNE_EXIT_CODE} -eq 0 ]; then
  MSG_PRUNE="✅ Prune completed successfully for ${MY_DESTINATION}"
else
  MSG_PRUNE="🚨 Prune failed for ${MY_LOCATION}. Check logs for more info."
fi

### BACKUP COPY ###
COPY_OUTPUT=$(duplicacy copy -from ${MY_LOCATION}-${MY_DESTINATION} -to ${MY_LOCATION}-${MY_SECOND_DESTINATION} 2>&1)
COPY_EXIT_CODE=$?

if [ ${COPY_EXIT_CODE} -eq 0 ]; then
  MSG_COPY="✅ Copy completed successfully from ${MY_DESTINATION} to ${MY_SECOND_DESTINATION}"
else
  MSG_COPY="🚨 Copy failed from ${MY_DESTINATION} to ${MY_SECOND_DESTINATION}. Check logs for more info."
fi

### PRUNE AGAIN ###
PRUNE2_OUTPUT=$(duplicacy prune -storage ${MY_LOCATION}-${MY_SECOND_DESTINATION} -keep 0:360 -keep 30:180 -keep 7:30 -keep 1:7 2>&1)
PRUNE2_EXIT_CODE=$?
if [ ${PRUNE2_EXIT_CODE} -eq 0 ]; then
  MSG_PRUNE2="✅ Prune2 completed successfully for ${MY_SECOND_DESTINATION}"
else
  MSG_PRUNE2="🚨 Prune2 failed for ${MY_LOCATION}. Check logs for more info."
fi

### SEND MESSAGE ###
NOTIFY_MESSAGE=$(cat << EOF
${MachineName} - ${MY_LOCATION}
${MSG_BACKUP}
${MSG_PRUNE}
${MSG_COPY}
${MSG_PRUNE2}
EOF
)
echo -e "${NOTIFY_MESSAGE}"
send_notification "${NOTIFY_MESSAGE}"