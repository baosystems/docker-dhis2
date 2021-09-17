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

# If PGHOST is empty or null, set it to DATABASE_HOST if provided
if [[ -z "${PGHOST:-}" ]] && [[ -n "${DATABASE_HOST:-}" ]]; then
  export PGHOST="${DATABASE_HOST:-}"
fi

# Set default values if not provided in the environment
if [[ -z "${DATABASE_DBNAME:-}" ]]; then
  export DATABASE_DBNAME='dhis2'
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

# Disable wait delay as this script is designed to be run interactively
export WAIT_BEFORE='0'


################################################################################


# Wait for hosts specified in the environment variable WAIT_HOSTS (noop if not set).
# If it times out before the targets are available, it will exit with a non-0 code,
# and this script will quit because of the bash option "set -e" above.
# https://github.com/ufoscout/docker-compose-wait
/usr/local/bin/wait


################################################################################


# The following section requires the following environment variables set:
# - DATABASE_DBNAME (default: "dhis2")
# - PGHOST or DATABASE_HOST (default: "localhost")
# - PGPORT (default: "5432")
# - PGUSER (default: "postgres", must be a PostgreSQL superuser)
# - PGPASSWORD or contents in PGPASSWORD_FILE (required for PGUSER in most PostgreSQL installations)


echo "[INFO] $SELF: Drop database \"${DATABASE_DBNAME}\":"
psql \
  --dbname='template1' \
  --echo-all \
  --echo-hidden \
  -v ON_ERROR_STOP=1 \
  --command="DROP DATABASE ${DATABASE_DBNAME};"

echo "[INFO] $SELF: Create empty database \"${DATABASE_DBNAME}\":"
psql \
  --dbname='template1' \
  --echo-all \
  --echo-hidden \
  -v ON_ERROR_STOP=1 \
  --command="CREATE DATABASE ${DATABASE_DBNAME};"

echo "[INFO] $SELF: Add PostGIS to database \"${DATABASE_DBNAME}\":"
psql \
  --dbname="$DATABASE_DBNAME" \
  --echo-all \
  --echo-hidden \
  -v ON_ERROR_STOP=1 \
  --command="CREATE EXTENSION IF NOT EXISTS postgis;"


################################################################################


# Output script progess
echo "$SELF: COMPLETED"
