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
  /usr/local/bin/wait
)
for ITEM in "${ITEMS[@]}"; do
  if ! command -V "$ITEM" &>/dev/null ; then
    echo "[ERROR] $SELF: Unable to find $ITEM, exiting..." >&2
    exit 1
  fi
done


################################################################################


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


################################################################################


# If PGPASSWORD is empty or null, set it to the contents of PGPASSWORD_FILE
if [[ -z "${PGPASSWORD:-}" ]] && [[ -r "${PGPASSWORD_FILE:-}" ]]; then
  export PGPASSWORD="$(<"${PGPASSWORD_FILE}")"
fi

# If PGHOST is empty or null, set it to DHIS2_DATABASE_HOST if provided
if [[ -z "${PGHOST:-}" ]] && [[ -n "${DHIS2_DATABASE_HOST:-}" ]]; then
  export PGHOST="${DHIS2_DATABASE_HOST:-}"
fi

# Set default values if not provided in the environment
if [[ -z "${PGDATABASE:-}" ]]; then
  export PGDATABASE='postgres'
fi
if [[ -z "${PGHOST:-}" ]]; then
  export PGHOST='localhost'
fi
if [[ -z "${PGPORT:-}" ]]; then
  export PGPORT='5432'
fi
if [[ -z "${PGUSER:-}" ]]; then
  export PGUSER='postgres'
fi

# If WAIT_HOSTS is empty or null, set to PGHOST:PGPORT
if [[ -z "${WAIT_HOSTS:-}" ]]; then
  export WAIT_HOSTS="${PGHOST}:${PGPORT}"
fi


################################################################################


# Wait for hosts specified in the environment variable WAIT_HOSTS (noop if not set).
# If it times out before the targets are available, it will exit with a non-0 code,
# and this script will quit because of the bash option "set -e" above.
# https://github.com/ufoscout/docker-compose-wait
/usr/local/bin/wait 2> >( sed -r -e 's/^\[(DEBUG|INFO)\s+(wait)\]/[\1] \2:/g' >&2 )


################################################################################


# The following section requires the following environment variables set:
# - PGDATABASE
# - PGHOST
# - PGPORT
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


# Record script progess
echo "$SELF: COMPLETED" | tee "$STATUS_FILE"
