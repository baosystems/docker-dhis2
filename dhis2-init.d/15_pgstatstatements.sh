#!/usr/bin/env bash

# SC2155: Declare and assign separately to avoid masking return values.
# shellcheck disable=SC2155

set -Eeo pipefail


################################################################################


SELF="$( basename "$0" )"

echo "[INFO] $SELF: started..."

# Exit immediately if any required scripts or programs are not found
ITEMS=(
  dirname
  grep
  mkdir
  psql
  rm
  tail
  tee
)
for ITEM in "${ITEMS[@]}"; do
  if ! command -V "$ITEM" &>/dev/null ; then
    echo "[ERROR] $SELF: Unable to find $ITEM, exiting..." >&2
    exit 1
  fi
done


################################################################################


if [[ -d /dhis2-init.progress/ ]]; then

  STATUS_FILE="/dhis2-init.progress/${SELF%.sh}_status.txt"

  # Ensure status file parent directory exists
  if [[ ! -d "$( dirname "$STATUS_FILE" )" ]]; then
    mkdir -p "$( dirname "$STATUS_FILE" )"
  fi

  if [[ "${DHIS2_INIT_FORCE:-0}" == "1" ]]; then
    echo "[DEBUG] $SELF: DHIS2_INIT_FORCE=1; delete \"$STATUS_FILE\"..." >&2
    rm -v -f "$STATUS_FILE"
  fi

  # Exit if this script has successfully completed previously and DHIS2_INIT_FORCE is not equal to "1"
  if [[ "${DHIS2_INIT_FORCE:-0}" != "1" ]] && { tail -1 "$STATUS_FILE" | grep -q 'COMPLETED$' ; } 2>/dev/null ; then
    echo "[INFO] $SELF: script was previously completed successfully, skipping..."
    exit 0
  fi

fi


################################################################################


# The section below may require the following environment variables to be set:
# - PGHOST
# - PGPORT
# - PGDATABASE
# - PGUSER
# - PGPASSWORD

# Check if pg_stat_statements is available to PostgreSQL
PGSTATSTATEMENTS_AVAILABLE="$( psql -At -c "SELECT 1 FROM pg_available_extensions WHERE name = 'pg_stat_statements';" )"

# If so, create the extension in the database
if [[ "${PGSTATSTATEMENTS_AVAILABLE:-0}" = "1" ]]; then
  psql --echo-all --echo-hidden -v ON_ERROR_STOP=1 <<- EOSQL
-- Create pg_stat_statements extension (may require additional configuration in postgresql.conf)
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
EOSQL
fi


################################################################################


if [[ -d /dhis2-init.progress/ ]]; then
  # Record script progess
  echo "$SELF: COMPLETED" | tee "$STATUS_FILE"
else
  echo "$SELF: COMPLETED"
fi
