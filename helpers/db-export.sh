#!/usr/bin/env bash

# SC2155: Declare and assign separately to avoid masking return values.
# shellcheck disable=SC2155

set -Eeo pipefail


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


pg_dump \
  "$DHIS2_DATABASE_NAME" \
  --format='plain' \
  --no-owner \
  --no-privileges \
  --exclude-table='_*' \
  --exclude-table='aggregated*' \
  --exclude-table='analytics_*' \
  --exclude-table='completeness*' \
  --exclude-schema='postgis' \
  --exclude-table='geography_columns' \
  --exclude-table='geometry_columns' \
  --exclude-table='spatial_ref_sys' \
| sed \
    --regexp-extended \
    -e '/^-- Dumped by pg_dump/,/^-- Name: postgis/{/^-- Dumped by pg_dump/!{/^-- Name: postgis/!d}}' \
    -e '/^-- Name: postgis/i \\nSET check_function_bodies = false;\n\n--' \
    -e 's/(postgis|public)\.(geometry)/\2/g' \
    -e 's/( postgis) WITH SCHEMA (postgis|public);/\1;/'
