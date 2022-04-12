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


# The section below requires the following environment variables set:
# - DHIS2_DATABASE_NAME
# - DHIS2_DATABASE_USERNAME
# - DHIS2_DATABASE_PASSWORD (optional, but strongly recommended)

# The following are optional but may be required to proceed:
# - PGHOST
# - PGPORT
# - PGUSER
# - PGPASSWORD

psql --echo-all --echo-hidden -v ON_ERROR_STOP=1 <<- EOSQL
-- Create role if not exists (https://stackoverflow.com/a/8099557)
DO
\$do$
BEGIN
  IF NOT EXISTS ( SELECT
                  FROM pg_roles
                  WHERE rolname = '$DHIS2_DATABASE_USERNAME') THEN
    CREATE ROLE $DHIS2_DATABASE_USERNAME ;
  END IF;
END
\$do$;

-- Create database if not exists (https://stackoverflow.com/a/18389184)
SELECT 'CREATE DATABASE $DHIS2_DATABASE_NAME' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DHIS2_DATABASE_NAME')\gexec

-- Set database owner
ALTER DATABASE "$DHIS2_DATABASE_NAME" OWNER TO $DHIS2_DATABASE_USERNAME;

-- Grant all to specified role
GRANT ALL PRIVILEGES ON DATABASE $DHIS2_DATABASE_NAME TO $DHIS2_DATABASE_USERNAME;

-- Connect to database $DHIS2_DATABASE_NAME
\c $DHIS2_DATABASE_NAME

-- public schema permissions
ALTER SCHEMA public OWNER TO $DHIS2_DATABASE_USERNAME;
REVOKE ALL ON SCHEMA public FROM public;

-- public schema existing object ownership, excluding PostGIS objects
DO \$\$DECLARE r record;
BEGIN
  FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename != 'spatial_ref_sys'
  LOOP
    EXECUTE 'ALTER TABLE '|| r.tablename ||' OWNER TO $DHIS2_DATABASE_USERNAME;';
  END LOOP;
END\$\$;
DO \$\$DECLARE r record;
BEGIN
  FOR r IN SELECT sequence_name FROM information_schema.sequences WHERE sequence_schema = 'public'
  LOOP
    EXECUTE 'ALTER SEQUENCE '|| r.sequence_name ||' OWNER TO $DHIS2_DATABASE_USERNAME;';
  END LOOP;
END\$\$;
DO \$\$DECLARE r record;
BEGIN
  FOR r IN SELECT table_name FROM information_schema.views WHERE table_schema = 'public' AND table_name != 'geography_columns' AND table_name != 'geometry_columns'
  LOOP
    EXECUTE 'ALTER VIEW '|| r.table_name ||' OWNER TO $DHIS2_DATABASE_USERNAME;';
  END LOOP;
END\$\$;

-- postgis schema owned by $PGUSER
CREATE SCHEMA IF NOT EXISTS postgis AUTHORIZATION $PGUSER;
ALTER SCHEMA postgis OWNER TO $PGUSER;

-- Set database search_path to include the postgis schema
ALTER DATABASE "$DHIS2_DATABASE_NAME" SET search_path TO public,postgis;
EOSQL

# Check if PostGIS is installed to the database
POSTGIS_EXISTS="$( psql --dbname "$DHIS2_DATABASE_NAME" -At -c "SELECT 1 FROM pg_extension WHERE extname='postgis';" )"
# If so, move it to its own schema
if [[ "${POSTGIS_EXISTS:-0}" = "1" ]]; then
  # Capture the version of PostGIS available to the PostgreSQL host
  POSTGIS_VERSION="$( psql --dbname 'template1' -At -c "SELECT default_version FROM pg_available_extensions WHERE name = 'postgis' ORDER BY default_version DESC LIMIT 1;" )"

  # Check if running in Amazon RDS
  IS_RDS="$( psql --dbname 'template1' -At -c "SELECT 1 FROM pg_stat_activity WHERE usename = 'rdsadmin' LIMIT 1;" )"
  if [[ "${IS_RDS:-0}" != "1" ]]; then
    psql --dbname "$DHIS2_DATABASE_NAME" --echo-all --echo-hidden -v ON_ERROR_STOP=1 <<- EOSQL
-- If the postgis extension is installed, ensure it is in the postgis schema
-- (These statements do not work in Amazon RDS)
UPDATE pg_extension SET extrelocatable = TRUE WHERE extname = 'postgis';
ALTER EXTENSION postgis SET SCHEMA postgis;
EOSQL
  fi

  psql --dbname "$DHIS2_DATABASE_NAME" --echo-all --echo-hidden -v ON_ERROR_STOP=1 <<- EOSQL
-- Update PostGIS to the latest version available
ALTER EXTENSION postgis UPDATE TO '${POSTGIS_VERSION}next';
ALTER EXTENSION postgis UPDATE TO '${POSTGIS_VERSION}';
EOSQL
fi

# Resume database setup
psql --dbname "$DHIS2_DATABASE_NAME" --echo-all --echo-hidden -v ON_ERROR_STOP=1 <<- EOSQL
-- postgis schema default privileges for user "$DHIS2_DATABASE_USERNAME" to use
ALTER DEFAULT PRIVILEGES IN SCHEMA postgis GRANT SELECT ON TABLES TO $DHIS2_DATABASE_USERNAME;
ALTER DEFAULT PRIVILEGES IN SCHEMA postgis GRANT SELECT,USAGE ON SEQUENCES TO $DHIS2_DATABASE_USERNAME;
ALTER DEFAULT PRIVILEGES IN SCHEMA postgis GRANT EXECUTE ON FUNCTIONS TO $DHIS2_DATABASE_USERNAME;

-- Create postgis extension in the postgis schema
CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA postgis;
ALTER EXTENSION postgis UPDATE;

-- PostGIS 3.x migration action
DROP EXTENSION IF EXISTS postgis_raster;

-- PostGIS extensions may cause DHIS2 startup problems
DROP EXTENSION IF EXISTS postgis_tiger_geocoder;
DROP EXTENSION IF EXISTS postgis_topology;

-- postgis schema effective privileges for user "$DHIS2_DATABASE_USERNAME" to use
GRANT USAGE ON SCHEMA postgis TO $DHIS2_DATABASE_USERNAME;
GRANT SELECT ON ALL TABLES IN SCHEMA postgis TO $DHIS2_DATABASE_USERNAME;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA postgis TO $DHIS2_DATABASE_USERNAME;
EOSQL

# If DHIS2_DATABASE_PASSWORD is provided, set LOGIN capability and a password for DHIS2_DATABASE_USERNAME
if [[ -n "${DHIS2_DATABASE_PASSWORD:-}" ]]; then
  psql --echo-all --echo-hidden -v ON_ERROR_STOP=1 <<- EOSQL
-- Set role password and grant login
EOSQL

  psql -v ON_ERROR_STOP=1 <<- EOSQL
ALTER ROLE $DHIS2_DATABASE_USERNAME WITH LOGIN PASSWORD '$DHIS2_DATABASE_PASSWORD';
EOSQL
fi


################################################################################


if [[ -d /dhis2-init.progress/ ]]; then
  # Record script progess
  echo "$SELF: COMPLETED" | tee "$STATUS_FILE"
else
  echo "$SELF: COMPLETED"
fi
