#!/bin/bash

set -e

# Enable shell aliases in this non-interactive script
shopt -s expand_aliases

# Check and set missing environment vars
: ${S3_BUCKET:?"S3_BUCKET env variable is required"}
: ${DATABASE_PATH:?"DATABASE_PATH env variable is required"}
if [[ -z ${S3_KEY_PREFIX} ]]; then
  export S3_KEY_PREFIX=""
else
  if [ "${S3_KEY_PREFIX: -1}" != "/" ]; then
    export S3_KEY_PREFIX="${S3_KEY_PREFIX}/"
  fi
fi
echo $S3_KEY_PREFIX

# Optional S3-compatible endpoint override for awscli
if [[ -n ${ENDPOINT_URL} ]]; then
  alias aws="aws --endpoint-url ${ENDPOINT_URL}"
fi

export BACKUP_PATH=${BACKUP_PATH:-${DATABASE_PATH}.bak}
export DATETIME=$(date "+%Y%m%d%H%M%S")
# Backup/restore busy timeout in milliseconds (SQLite expects ms)
export SQLITE_TIMEOUT_MS=${SQLITE_TIMEOUT_MS:-10000}
export ENCRYPTION_KEY=${ENCRYPTION_KEY:-}

# Detect if a file is OpenSSL salted (our encryption format)
is_encrypted_file() {
  local file="$1"
  if [ ! -f "$file" ]; then
    return 1
  fi
  # OpenSSL 'enc' with -salt writes a 'Salted__' header
  if LC_ALL=C head -c 8 "$file" 2>/dev/null | grep -q '^Salted__$'; then
    return 0
  fi
  return 1
}

# Add this script to the crontab and start crond
cron() {
  if [[ -z "${CRON_SCHEDULE}" ]]; then
    echo "CRON_SCHEDULE env variable is required for cron mode"
    exit 1
  fi
  echo "Starting backup cron job with frequency '${CRON_SCHEDULE}'"
  echo "${CRON_SCHEDULE} $0 backup" > /var/spool/cron/crontabs/root
  crond -f
}

# Dump the database to a file and push it to S3
backup() {
  # Dump database to file
  echo "Backing up $DATABASE_PATH to $BACKUP_PATH"
  # Use online backup API for hot backup while DB is running
  if sqlite3 "$DATABASE_PATH" <<SQL
.timeout ${SQLITE_TIMEOUT_MS}
.backup '$BACKUP_PATH'
SQL
  then
    :
  else
    echo "Failed to backup $DATABASE_PATH to $BACKUP_PATH"
    exit 1
  fi

  # Optionally encrypt the backup before upload
  UPLOAD_SOURCE="$BACKUP_PATH"
  if [[ -n "${ENCRYPTION_KEY}" ]]; then
    echo "Encrypting backup before upload"
    if openssl enc -aes-256-cbc -pbkdf2 -salt -iter 100000 -pass env:ENCRYPTION_KEY -in "$BACKUP_PATH" -out "${BACKUP_PATH}.enc"; then
      UPLOAD_SOURCE="${BACKUP_PATH}.enc"
      # Remove plaintext backup from disk to avoid leaving sensitive data around
      rm -f "$BACKUP_PATH"
    else
      echo "Encryption failed"
      # Ensure plaintext does not remain if encryption failed unexpectedly
      rm -f "${BACKUP_PATH}.enc"
      exit 1
    fi
  fi

  echo "Sending file to S3"
  # Push timestamped backup file to S3
  if aws s3 cp "$UPLOAD_SOURCE" s3://${S3_BUCKET}/${S3_KEY_PREFIX}${DATETIME}.bak; then
    echo "Backup file uploaded to s3://${S3_BUCKET}/${S3_KEY_PREFIX}${DATETIME}.bak"
  else
    echo "Backup file failed to upload"
    exit 1
  fi

  # Optionally trigger a webhook on successful backup
  if [[ -n "${POST_WEBHOOK_URL}" ]]; then
    echo "Triggering POST webhook: ${POST_WEBHOOK_URL}"
    if curl -fsSL -X POST "${POST_WEBHOOK_URL}" >/dev/null 2>&1; then
      echo "Webhook triggered successfully"
    else
      echo "Webhook trigger failed"
    fi
  fi

  echo "Done"
}

# Pull down a timestamped backup from S3 and restore it to the database
restore() {
  # Resolve which object to restore 
  local input_ts="$1"
  local ts=""
  local object_key=""
  if [[ -z "${input_ts}" ]]; then
    echo "Error: restore requires a TIMESTAMP argument (YYYYMMDDHHMMSS)"
    exit 1
  fi
  ts="${input_ts}"
  object_key="${S3_KEY_PREFIX}${ts}.bak"

  # Remove old backup file
  if [ -e $BACKUP_PATH ]; then
    echo "Removing out of date backup"
    rm $BACKUP_PATH
  fi
  # Get backup file from S3
  echo "Downloading backup from s3://${S3_BUCKET}/${object_key}"
  if aws s3 cp s3://${S3_BUCKET}/${object_key} $BACKUP_PATH; then
    echo "Downloaded"
  else
    echo "Failed to download backup 's3://${S3_BUCKET}/${object_key}'"
    exit 1
  fi

  # If the downloaded file is encrypted, require ENCRYPTION_KEY and decrypt
  local RESTORE_SOURCE="$BACKUP_PATH"
  if is_encrypted_file "$BACKUP_PATH"; then
    echo "Downloaded backup appears to be encrypted"
    if [[ -z "${ENCRYPTION_KEY}" ]]; then
      echo "Error: Backup is encrypted but ENCRYPTION_KEY is not set. Cannot restore."
      exit 1
    fi
    local DECRYPTED_PATH="${BACKUP_PATH}.decrypted"
    if openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -pass env:ENCRYPTION_KEY -in "$BACKUP_PATH" -out "$DECRYPTED_PATH"; then
      RESTORE_SOURCE="$DECRYPTED_PATH"
    else
      echo "Error: Decryption failed. Check that ENCRYPTION_KEY is correct."
      exit 1
    fi
  fi

  # Restore database from backup file
  echo "Running restore"
  if [ -e $DATABASE_PATH ]; then
    echo "Moving out of date database aside"
    mv $DATABASE_PATH ${DATABASE_PATH}.old
  fi
  # Use restore via online backup API
  if sqlite3 "$DATABASE_PATH" <<SQL
.timeout ${SQLITE_TIMEOUT_MS}
.restore '$RESTORE_SOURCE'
SQL
  then
    echo "Successfully restored"
    if [ -e ${DATABASE_PATH}.old ]; then
      echo "Cleaning up out of date database"
      rm ${DATABASE_PATH}.old
    fi
    # Clean up temporary files
    if [ -e "${BACKUP_PATH}.decrypted" ]; then
      rm -f "${BACKUP_PATH}.decrypted"
    fi
  else
    echo "Restore failed"
    if [ -e ${DATABASE_PATH}.old ]; then
      echo "Moving out of date database back, hopefully it's better than nothing"
      mv ${DATABASE_PATH}.old $DATABASE_PATH
    fi
    # Clean up temporary files if present
    if [ -e "${BACKUP_PATH}.decrypted" ]; then
      rm -f "${BACKUP_PATH}.decrypted"
    fi
    exit 1
  fi
  echo "Done"

}

# Handle command line arguments
case "$1" in
  "cron")
    cron
    ;;
  "backup")
    backup
    ;;
  "restore")
    restore "$2"
    ;;
  *)
    echo "Invalid command '$@'"
    echo "Usage: $0 {backup|restore TIMESTAMP|cron}"
    echo "       cron requires CRON_SCHEDULE env var (e.g. \"0 1 * * *\")"
    echo "       restore requires a timestamp (YYYYMMDDHHMMSS)."
esac
