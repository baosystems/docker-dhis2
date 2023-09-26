#!/usr/bin/env bash

# SC2155: Declare and assign separately to avoid masking return values.
# shellcheck disable=SC2155

set -Eeo pipefail


################################################################################


SELF="$( basename "$0" )"

echo "[INFO] $SELF: started..."


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
if [[ -z "${DHIS2_DATABASE_NAME:-}" ]]; then
  export DHIS2_DATABASE_NAME='dhis2'
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


################################################################################


# The following section requires the following environment variables set:
# - DHIS2_DATABASE_NAME
# - PGHOST
# - PGPORT
# - PGUSER
# - PGPASSWORD


echo "[INFO] $SELF: Drop database \"${DHIS2_DATABASE_NAME}\":"
psql \
  --dbname='template1' \
  --echo-all \
  --echo-hidden \
  -v ON_ERROR_STOP=1 \
  --command="DROP DATABASE IF EXISTS ${DHIS2_DATABASE_NAME};"

echo "[INFO] $SELF: Create empty database \"${DHIS2_DATABASE_NAME}\":"
psql \
  --dbname='template1' \
  --echo-all \
  --echo-hidden \
  -v ON_ERROR_STOP=1 \
  --command="CREATE DATABASE ${DHIS2_DATABASE_NAME};"

echo "[INFO] $SELF: Add PostGIS to database \"${DHIS2_DATABASE_NAME}\":"
psql \
  --dbname="$DHIS2_DATABASE_NAME" \
  --echo-all \
  --echo-hidden \
  -v ON_ERROR_STOP=1 \
  --command="CREATE EXTENSION IF NOT EXISTS postgis;"

if [[ -f '/dhis2-init.progress/10_dhis2-database_status.txt' ]]; then
  echo "[INFO] $SELF: Delete the '10_dhis2-database_status.txt' progress file so that the database gets re-initialized:"
  rm --verbose --force '/dhis2-init.progress/10_dhis2-database_status.txt'
fi


################################################################################


# Output script progess
echo "$SELF: COMPLETED"
