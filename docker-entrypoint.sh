#!/usr/bin/env bash

# SC2155: Declare and assign separately to avoid masking return values.
# shellcheck disable=SC2155

set -Eeo pipefail

# Inspired by: https://github.com/docker-library/postgres/blob/ba30220/13/docker-entrypoint.sh

########

# check to see if this file is being run or sourced from another script
_is_sourced() {
  # https://unix.stackexchange.com/a/215279
  [ "${#FUNCNAME[@]}" -ge 2 ] \
    && [ "${FUNCNAME[0]}" = '_is_sourced' ] \
    && [ "${FUNCNAME[1]}" = 'source' ]
}

_main() {

  SELF="$( basename "$0" )"

  ########

  # Match first argument to this script.
  # Example: "remco" for a full command like "docker-entrypoint.sh remco -config /etc/remco/config",
  # or "catalina.sh" for a full command of "docker-entrypoint.sh dhis2-init.sh"
  if [ "$1" = 'remco' ] || [ "$1" = 'dhis2-init.sh' ]; then

    # Set DHIS2 build information (logic also used in 20_dhis2-initwar.sh):

    DHIS2_BUILD_PROPERTIES="$( unzip -q -p "$( find /usr/local/tomcat/webapps/ROOT/WEB-INF/lib -maxdepth 1 -type f -name 'dhis-service-core-[0-9]*.jar' )" build.properties )"
    export DHIS2_BUILD_VERSION="$( awk -F'=' '/^build\.version/ {gsub(/ /, "", $NF); print $NF}' <<< "$DHIS2_BUILD_PROPERTIES" )"
    export DHIS2_BUILD_MAJOR="$( cut -c1-4 <<< "$DHIS2_BUILD_VERSION" )"
    export DHIS2_BUILD_REVISION="$( awk -F'=' '/^build\.revision/ {gsub(/ /, "", $NF); print $NF}' <<< "$DHIS2_BUILD_PROPERTIES" )"
    export DHIS2_BUILD_TIME="$( awk -F'=' '/^build\.time/ {sub(/ /, "", $NF); print $NF}' <<< "$DHIS2_BUILD_PROPERTIES" )"
    export DHIS2_BUILD_DATE="$( grep --only-matching --extended-regexp '20[0-9]{2}-[0-9]{2}-[0-9]{2}' <<< "$DHIS2_BUILD_TIME" )"

    # Set environment variables for using remco to generate dhis.conf:

    # Set contents of DHIS2_DATABASE_PASSWORD_FILE to DHIS2_DATABASE_PASSWORD
    if [ -z "${DHIS2_DATABASE_PASSWORD:-}" ] && [ -r "${DHIS2_DATABASE_PASSWORD_FILE:-}" ]; then
      export DHIS2_DATABASE_PASSWORD="$(<"${DHIS2_DATABASE_PASSWORD_FILE}")"
      echo "[DEBUG] $SELF: set DHIS2_DATABASE_PASSWORD from DHIS2_DATABASE_PASSWORD_FILE" >&2
    fi

    # Set contents of DHIS2_REDIS_PASSWORD_FILE to DHIS2_REDIS_PASSWORD
    if [ -z "${DHIS2_REDIS_PASSWORD:-}" ] && [ -r "${DHIS2_REDIS_PASSWORD_FILE:-}" ]; then
      export DHIS2_REDIS_PASSWORD="$(<"${DHIS2_REDIS_PASSWORD_FILE}")"
      echo "[DEBUG] $SELF: set DHIS2_REDIS_PASSWORD from DHIS2_REDIS_PASSWORD_FILE" >&2
    fi

    # Set SYSTEM_IP to the internal IP address
    if [ -z "${SYSTEM_IP:-}" ]; then
      export SYSTEM_IP="$(hostname --ip-address)"
      echo "[DEBUG] $SELF: set SYSTEM_IP=$SYSTEM_IP" >&2
    fi

    # Set DHIS2_SERVER_BASE_URL if not set to value of DHIS2_SERVER_BASEURL if set
    # NOTE: DHIS2_SERVER_BASEURL and this block will be removed later
    if [ -z "${DHIS2_SERVER_BASE_URL:-}" ] && [ -n "${DHIS2_SERVER_BASEURL:-}" ]; then
      export DHIS2_SERVER_BASE_URL="$DHIS2_SERVER_BASEURL"
      echo "[DEBUG] $SELF: set DHIS2_SERVER_BASE_URL=$DHIS2_SERVER_BASE_URL" >&2
    fi

    # Set DHIS2_SERVER_HTTPS to "on" if not set and DHIS2_SERVER_BASE_URL begins with "https://"
    if [ -z "${DHIS2_SERVER_HTTPS:-}" ] && [[ "${DHIS2_SERVER_BASE_URL:-}" =~ ^https:// ]]; then
      export DHIS2_SERVER_HTTPS="on"
      echo "[DEBUG] $SELF: set DHIS2_SERVER_HTTPS=$DHIS2_SERVER_HTTPS" >&2
    fi

    # Set TOMCAT_CONNECTOR_PROXYPORT if not set to value dervied from DHIS2_SERVER_BASE_URL if set
    if [ -z "${TOMCAT_CONNECTOR_PROXYPORT:-}" ] && [ -n "${DHIS2_SERVER_BASE_URL:-}" ]; then
      export TOMCAT_CONNECTOR_PROXYPORT="$( port-from-url.py "$DHIS2_SERVER_BASE_URL" )"
      echo "[DEBUG] $SELF: set TOMCAT_CONNECTOR_PROXYPORT=$TOMCAT_CONNECTOR_PROXYPORT" >&2
    fi

    # Set TOMCAT_CONNECTOR_SCHEME to "https" if not set and DHIS2_SERVER_BASE_URL begins with "https://"
    if [ -z "${TOMCAT_CONNECTOR_SCHEME:-}" ] && [[ "${DHIS2_SERVER_BASE_URL:-}" =~ ^https:// ]]; then
      export TOMCAT_CONNECTOR_SCHEME="https"
      echo "[DEBUG] $SELF: set TOMCAT_CONNECTOR_SCHEME=$TOMCAT_CONNECTOR_SCHEME" >&2
    fi

    # Set TOMCAT_CONNECTOR_SECURE to "true" if not set and DHIS2_SERVER_HTTPS is "on"
    if [ -z "${TOMCAT_CONNECTOR_SECURE:-}" ] && [ "${DHIS2_SERVER_HTTPS:-}" = "on" ]; then
      export TOMCAT_CONNECTOR_SECURE="true"
      echo "[DEBUG] $SELF: set TOMCAT_CONNECTOR_SECURE=$TOMCAT_CONNECTOR_SECURE" >&2
    fi

    # Set DHIS2_DATABASE_USERNAME if not provided
    if [ -z "${DHIS2_DATABASE_USERNAME:-}" ]; then
      export DHIS2_DATABASE_USERNAME="dhis"
      echo "[DEBUG] $SELF: set DHIS2_DATABASE_USERNAME=$DHIS2_DATABASE_USERNAME" >&2
    fi

    # Set DHIS2_CONNECTION_USERNAME if not provided
    if [ -z "${DHIS2_CONNECTION_USERNAME:-}" ]; then
      export DHIS2_CONNECTION_USERNAME="$DHIS2_DATABASE_USERNAME"
      echo "[DEBUG] $SELF: set DHIS2_CONNECTION_USERNAME=$DHIS2_CONNECTION_USERNAME" >&2
    fi

    # Set DHIS2_CONNECTION_PASSWORD if not provided and DHIS2_DATABASE_PASSWORD is provided
    if [ -z "${DHIS2_CONNECTION_PASSWORD:-}" ] && [ -n "${DHIS2_DATABASE_PASSWORD:-}" ]; then
      export DHIS2_CONNECTION_PASSWORD="$DHIS2_DATABASE_PASSWORD"
      echo "[DEBUG] $SELF: set DHIS2_CONNECTION_PASSWORD to the value of DHIS2_DATABASE_PASSWORD" >&2
    fi

    # Set DHIS2_CONNECTION_URL from DHIS2_DATABASE_* values
    if [ -z "${DHIS2_CONNECTION_URL:-}" ]; then

      # Set DHIS2_DATABASE_NAME if not provided
      if [ -z "${DHIS2_DATABASE_NAME:-}" ]; then
        export DHIS2_DATABASE_NAME="dhis2"
        echo "[DEBUG] $SELF: set DHIS2_DATABASE_NAME=$DHIS2_DATABASE_NAME" >&2
      fi

      # Set DHIS2_CONNECTION_URL as a remote URL if DHIS2_DATABASE_HOST is provided
      if [ -n "${DHIS2_DATABASE_HOST:-}" ]; then

        # Set DHIS2_DATABASE_PORT if not provided
        if [ -z "${DHIS2_DATABASE_PORT:-}" ]; then
          export DHIS2_DATABASE_PORT="5432"
          echo "[DEBUG] $SELF: set DHIS2_DATABASE_PORT=$DHIS2_DATABASE_PORT" >&2
        fi

        export DHIS2_CONNECTION_URL="jdbc:postgresql://$DHIS2_DATABASE_HOST:$DHIS2_DATABASE_PORT/$DHIS2_DATABASE_NAME"
        echo "[DEBUG] $SELF: set DHIS2_CONNECTION_URL=$DHIS2_CONNECTION_URL" >&2

      # Otherwise, use a local connection
      else
        export DHIS2_CONNECTION_URL="jdbc:postgresql:$DHIS2_DATABASE_NAME"
        echo "[DEBUG] $SELF: set DHIS2_CONNECTION_URL=$DHIS2_CONNECTION_URL" >&2

      fi
    fi

    # Set DHIS2_CONNECTION_DIALECT if not provided
    if [ -z "${DHIS2_CONNECTION_DIALECT:-}" ]; then
      export DHIS2_CONNECTION_DIALECT="org.hibernate.dialect.PostgreSQLDialect"
      echo "[DEBUG] $SELF: set DHIS2_CONNECTION_DIALECT=$DHIS2_CONNECTION_DIALECT" >&2
    fi

    # Set DHIS2_CONNECTION_DRIVER_CLASS if not provided for DHIS2 2.38 and below
    if [ -z "${DHIS2_CONNECTION_DRIVER_CLASS:-}" ] && [ "${DHIS2_BUILD_MAJOR//.}" -le "238" ]; then
      export DHIS2_CONNECTION_DRIVER_CLASS="org.postgresql.Driver"
      echo "[DEBUG] $SELF: set DHIS2_CONNECTION_DRIVER_CLASS=$DHIS2_CONNECTION_DRIVER_CLASS" >&2
    fi

    # Set DHIS2_CONNECTION_SCHEMA if not provided for DHIS2 2.37 and below
    if [ -z "${DHIS2_CONNECTION_SCHEMA:-}" ] && [ "${DHIS2_BUILD_MAJOR//.}" -le "237" ]; then
      export DHIS2_CONNECTION_SCHEMA="update"
      echo "[DEBUG] $SELF: set DHIS2_CONNECTION_SCHEMA=$DHIS2_CONNECTION_SCHEMA" >&2
    fi

    # Set DHIS2_NODE_ID as hostname
    if [ -z "${DHIS2_NODE_ID:-}" ]; then
      export DHIS2_NODE_ID="$(hostname --fqdn)"
      echo "[DEBUG] $SELF: set DHIS2_NODE_ID=$DHIS2_NODE_ID" >&2
    fi

    # Set SYSTEM_FQDN [DEPRECATED] as DHIS2_NODE_ID
    if [ -z "${SYSTEM_FQDN:-}" ]; then
      export SYSTEM_FQDN="$DHIS2_NODE_ID"
      echo "[DEBUG] $SELF: set SYSTEM_FQDN=$SYSTEM_FQDN [DEPRECATED]" >&2
    fi

    # DHIS2 can support up to 5 read replicas.
    # Read replica 1
    if [ -z "${DHIS2_READ1_CONNECTION_URL:-}" ] \
    && { [ -n "${DHIS2_READ1_DATABASE_HOST:-}" ] || [ -n "${DHIS2_READ1_DATABASE_NAME:-}" ]; } ; then

      # Set DHIS2_READ1_DATABASE_NAME if not provided
      if [ -z "${DHIS2_READ1_DATABASE_NAME:-}" ]; then
        export DHIS2_READ1_DATABASE_NAME="$DHIS2_DATABASE_NAME"
        echo "[DEBUG] $SELF: set DHIS2_READ1_DATABASE_NAME=$DHIS2_READ1_DATABASE_NAME" >&2
      fi

      # Set DHIS2_READ1_CONNECTION_URL as a remote URL if DHIS2_READ1_DATABASE_HOST is provided
      if [ -n "${DHIS2_READ1_DATABASE_HOST:-}" ]; then

        # Set DHIS2_READ1_DATABASE_PORT if not provided
        if [ -z "${DHIS2_READ1_DATABASE_PORT:-}" ]; then
          export DHIS2_READ1_DATABASE_PORT="$DHIS2_DATABASE_PORT"
          echo "[DEBUG] $SELF: set DHIS2_READ1_DATABASE_PORT=$DHIS2_READ1_DATABASE_PORT" >&2
        fi

        export DHIS2_READ1_CONNECTION_URL="jdbc:postgresql://$DHIS2_READ1_DATABASE_HOST:$DHIS2_READ1_DATABASE_PORT/$DHIS2_READ1_DATABASE_NAME"
        echo "[DEBUG] $SELF: set DHIS2_READ1_CONNECTION_URL=$DHIS2_READ1_CONNECTION_URL" >&2

      # Otherwise, use a local connection
      else
        export DHIS2_READ1_CONNECTION_URL="jdbc:postgresql:$DHIS2_READ1_DATABASE_NAME"
        echo "[DEBUG] $SELF: set DHIS2_READ1_CONNECTION_URL=$DHIS2_READ1_CONNECTION_URL" >&2

      fi

      # Set contents of DHIS2_READ1_DATABASE_PASSWORD_FILE to DHIS2_READ1_DATABASE_PASSWORD
      if [ -z "${DHIS2_READ1_DATABASE_PASSWORD:-}" ] && [ -r "${DHIS2_READ1_DATABASE_PASSWORD_FILE:-}" ]; then
        export DHIS2_READ1_DATABASE_PASSWORD="$(<"${DHIS2_READ1_DATABASE_PASSWORD_FILE}")"
        echo "[DEBUG] $SELF: set DHIS2_READ1_DATABASE_PASSWORD from DHIS2_READ1_DATABASE_PASSWORD_FILE" >&2
      fi

      # Set DHIS2_READ1_CONNECTION_PASSWORD if not provided and DHIS2_READ1_DATABASE_PASSWORD is provided
      if [ -z "${DHIS2_READ1_CONNECTION_PASSWORD:-}" ] && [ -n "${DHIS2_READ1_DATABASE_PASSWORD:-}" ]; then
        export DHIS2_READ1_CONNECTION_PASSWORD="$DHIS2_READ1_DATABASE_PASSWORD"
        echo "[DEBUG] $SELF: set DHIS2_READ1_CONNECTION_PASSWORD to the value of DHIS2_READ1_DATABASE_PASSWORD" >&2
      fi

      # Set DHIS2_READ1_CONNECTION_USERNAME to DHIS2_READ1_DATABASE_USERNAME if not provided
      if [ -z "${DHIS2_READ1_CONNECTION_USERNAME:-}" ] && [ -n "${DHIS2_READ1_DATABASE_USERNAME:-}" ]; then
        export DHIS2_READ1_CONNECTION_USERNAME="$DHIS2_READ1_DATABASE_USERNAME"
        echo "[DEBUG] $SELF: set DHIS2_READ1_CONNECTION_USERNAME=$DHIS2_READ1_CONNECTION_USERNAME" >&2
      fi

    fi

    # Read replica 2
    if [ -z "${DHIS2_READ2_CONNECTION_URL:-}" ] \
    && { [ -n "${DHIS2_READ2_DATABASE_HOST:-}" ] || [ -n "${DHIS2_READ2_DATABASE_NAME:-}" ]; } ; then

      # Set DHIS2_READ2_DATABASE_NAME if not provided
      if [ -z "${DHIS2_READ2_DATABASE_NAME:-}" ]; then
        export DHIS2_READ2_DATABASE_NAME="$DHIS2_DATABASE_NAME"
        echo "[DEBUG] $SELF: set DHIS2_READ2_DATABASE_NAME=$DHIS2_READ2_DATABASE_NAME" >&2
      fi

      # Set DHIS2_READ2_CONNECTION_URL as a remote URL if DHIS2_READ2_DATABASE_HOST is provided
      if [ -n "${DHIS2_READ2_DATABASE_HOST:-}" ]; then

        # Set DHIS2_READ2_DATABASE_PORT if not provided
        if [ -z "${DHIS2_READ2_DATABASE_PORT:-}" ]; then
          export DHIS2_READ2_DATABASE_PORT="$DHIS2_DATABASE_PORT"
          echo "[DEBUG] $SELF: set DHIS2_READ2_DATABASE_PORT=$DHIS2_READ2_DATABASE_PORT" >&2
        fi

        export DHIS2_READ2_CONNECTION_URL="jdbc:postgresql://$DHIS2_READ2_DATABASE_HOST:$DHIS2_READ2_DATABASE_PORT/$DHIS2_READ2_DATABASE_NAME"
        echo "[DEBUG] $SELF: set DHIS2_READ2_CONNECTION_URL=$DHIS2_READ2_CONNECTION_URL" >&2

      # Otherwise, use a local connection
      else
        export DHIS2_READ2_CONNECTION_URL="jdbc:postgresql:$DHIS2_READ2_DATABASE_NAME"
        echo "[DEBUG] $SELF: set DHIS2_READ2_CONNECTION_URL=$DHIS2_READ2_CONNECTION_URL" >&2

      fi

      # Set contents of DHIS2_READ2_DATABASE_PASSWORD_FILE to DHIS2_READ2_DATABASE_PASSWORD
      if [ -z "${DHIS2_READ2_DATABASE_PASSWORD:-}" ] && [ -r "${DHIS2_READ2_DATABASE_PASSWORD_FILE:-}" ]; then
        export DHIS2_READ2_DATABASE_PASSWORD="$(<"${DHIS2_READ2_DATABASE_PASSWORD_FILE}")"
        echo "[DEBUG] $SELF: set DHIS2_READ2_DATABASE_PASSWORD from DHIS2_READ2_DATABASE_PASSWORD_FILE" >&2
      fi

      # Set DHIS2_READ2_CONNECTION_PASSWORD if not provided and DHIS2_READ2_DATABASE_PASSWORD is provided
      if [ -z "${DHIS2_READ2_CONNECTION_PASSWORD:-}" ] && [ -n "${DHIS2_READ2_DATABASE_PASSWORD:-}" ]; then
        export DHIS2_READ2_CONNECTION_PASSWORD="$DHIS2_READ2_DATABASE_PASSWORD"
        echo "[DEBUG] $SELF: set DHIS2_READ2_CONNECTION_PASSWORD to the value of DHIS2_READ2_DATABASE_PASSWORD" >&2
      fi

      # Set DHIS2_READ2_CONNECTION_USERNAME to DHIS2_READ2_DATABASE_USERNAME if not provided
      if [ -z "${DHIS2_READ2_CONNECTION_USERNAME:-}" ] && [ -n "${DHIS2_READ2_DATABASE_USERNAME:-}" ]; then
        export DHIS2_READ2_CONNECTION_USERNAME="$DHIS2_READ2_DATABASE_USERNAME"
        echo "[DEBUG] $SELF: set DHIS2_READ2_CONNECTION_USERNAME=$DHIS2_READ2_CONNECTION_USERNAME" >&2
      fi

    fi

    # Read replica 3
    if [ -z "${DHIS2_READ3_CONNECTION_URL:-}" ] \
    && { [ -n "${DHIS2_READ3_DATABASE_HOST:-}" ] || [ -n "${DHIS2_READ3_DATABASE_NAME:-}" ]; } ; then

      # Set DHIS2_READ3_DATABASE_NAME if not provided
      if [ -z "${DHIS2_READ3_DATABASE_NAME:-}" ]; then
        export DHIS2_READ3_DATABASE_NAME="$DHIS2_DATABASE_NAME"
        echo "[DEBUG] $SELF: set DHIS2_READ3_DATABASE_NAME=$DHIS2_READ3_DATABASE_NAME" >&2
      fi

      # Set DHIS2_READ3_CONNECTION_URL as a remote URL if DHIS2_READ3_DATABASE_HOST is provided
      if [ -n "${DHIS2_READ3_DATABASE_HOST:-}" ]; then

        # Set DHIS2_READ3_DATABASE_PORT if not provided
        if [ -z "${DHIS2_READ3_DATABASE_PORT:-}" ]; then
          export DHIS2_READ3_DATABASE_PORT="$DHIS2_DATABASE_PORT"
          echo "[DEBUG] $SELF: set DHIS2_READ3_DATABASE_PORT=$DHIS2_READ3_DATABASE_PORT" >&2
        fi

        export DHIS2_READ3_CONNECTION_URL="jdbc:postgresql://$DHIS2_READ3_DATABASE_HOST:$DHIS2_READ3_DATABASE_PORT/$DHIS2_READ3_DATABASE_NAME"
        echo "[DEBUG] $SELF: set DHIS2_READ3_CONNECTION_URL=$DHIS2_READ3_CONNECTION_URL" >&2

      # Otherwise, use a local connection
      else
        export DHIS2_READ3_CONNECTION_URL="jdbc:postgresql:$DHIS2_READ3_DATABASE_NAME"
        echo "[DEBUG] $SELF: set DHIS2_READ3_CONNECTION_URL=$DHIS2_READ3_CONNECTION_URL" >&2

      fi

      # Set contents of DHIS2_READ3_DATABASE_PASSWORD_FILE to DHIS2_READ3_DATABASE_PASSWORD
      if [ -z "${DHIS2_READ3_DATABASE_PASSWORD:-}" ] && [ -r "${DHIS2_READ3_DATABASE_PASSWORD_FILE:-}" ]; then
        export DHIS2_READ3_DATABASE_PASSWORD="$(<"${DHIS2_READ3_DATABASE_PASSWORD_FILE}")"
        echo "[DEBUG] $SELF: set DHIS2_READ3_DATABASE_PASSWORD from DHIS2_READ3_DATABASE_PASSWORD_FILE" >&2
      fi

      # Set DHIS2_READ3_CONNECTION_PASSWORD if not provided and DHIS2_READ3_DATABASE_PASSWORD is provided
      if [ -z "${DHIS2_READ3_CONNECTION_PASSWORD:-}" ] && [ -n "${DHIS2_READ3_DATABASE_PASSWORD:-}" ]; then
        export DHIS2_READ3_CONNECTION_PASSWORD="$DHIS2_READ3_DATABASE_PASSWORD"
        echo "[DEBUG] $SELF: set DHIS2_READ3_CONNECTION_PASSWORD to the value of DHIS2_READ3_DATABASE_PASSWORD" >&2
      fi

      # Set DHIS2_READ3_CONNECTION_USERNAME to DHIS2_READ3_DATABASE_USERNAME if not provided
      if [ -z "${DHIS2_READ3_CONNECTION_USERNAME:-}" ] && [ -n "${DHIS2_READ3_DATABASE_USERNAME:-}" ]; then
        export DHIS2_READ3_CONNECTION_USERNAME="$DHIS2_READ3_DATABASE_USERNAME"
        echo "[DEBUG] $SELF: set DHIS2_READ3_CONNECTION_USERNAME=$DHIS2_READ3_CONNECTION_USERNAME" >&2
      fi

    fi

    # Read replica 4
    if [ -z "${DHIS2_READ4_CONNECTION_URL:-}" ] \
    && { [ -n "${DHIS2_READ4_DATABASE_HOST:-}" ] || [ -n "${DHIS2_READ4_DATABASE_NAME:-}" ]; } ; then

      # Set DHIS2_READ4_DATABASE_NAME if not provided
      if [ -z "${DHIS2_READ4_DATABASE_NAME:-}" ]; then
        export DHIS2_READ4_DATABASE_NAME="$DHIS2_DATABASE_NAME"
        echo "[DEBUG] $SELF: set DHIS2_READ4_DATABASE_NAME=$DHIS2_READ4_DATABASE_NAME" >&2
      fi

      # Set DHIS2_READ4_CONNECTION_URL as a remote URL if DHIS2_READ4_DATABASE_HOST is provided
      if [ -n "${DHIS2_READ4_DATABASE_HOST:-}" ]; then

        # Set DHIS2_READ4_DATABASE_PORT if not provided
        if [ -z "${DHIS2_READ4_DATABASE_PORT:-}" ]; then
          export DHIS2_READ4_DATABASE_PORT="$DHIS2_DATABASE_PORT"
          echo "[DEBUG] $SELF: set DHIS2_READ4_DATABASE_PORT=$DHIS2_READ4_DATABASE_PORT" >&2
        fi

        export DHIS2_READ4_CONNECTION_URL="jdbc:postgresql://$DHIS2_READ4_DATABASE_HOST:$DHIS2_READ4_DATABASE_PORT/$DHIS2_READ4_DATABASE_NAME"
        echo "[DEBUG] $SELF: set DHIS2_READ4_CONNECTION_URL=$DHIS2_READ4_CONNECTION_URL" >&2

      # Otherwise, use a local connection
      else
        export DHIS2_READ4_CONNECTION_URL="jdbc:postgresql:$DHIS2_READ4_DATABASE_NAME"
        echo "[DEBUG] $SELF: set DHIS2_READ4_CONNECTION_URL=$DHIS2_READ4_CONNECTION_URL" >&2

      fi

      # Set contents of DHIS2_READ4_DATABASE_PASSWORD_FILE to DHIS2_READ4_DATABASE_PASSWORD
      if [ -z "${DHIS2_READ4_DATABASE_PASSWORD:-}" ] && [ -r "${DHIS2_READ4_DATABASE_PASSWORD_FILE:-}" ]; then
        export DHIS2_READ4_DATABASE_PASSWORD="$(<"${DHIS2_READ4_DATABASE_PASSWORD_FILE}")"
        echo "[DEBUG] $SELF: set DHIS2_READ4_DATABASE_PASSWORD from DHIS2_READ4_DATABASE_PASSWORD_FILE" >&2
      fi

      # Set DHIS2_READ4_CONNECTION_PASSWORD if not provided and DHIS2_READ4_DATABASE_PASSWORD is provided
      if [ -z "${DHIS2_READ4_CONNECTION_PASSWORD:-}" ] && [ -n "${DHIS2_READ4_DATABASE_PASSWORD:-}" ]; then
        export DHIS2_READ4_CONNECTION_PASSWORD="$DHIS2_READ4_DATABASE_PASSWORD"
        echo "[DEBUG] $SELF: set DHIS2_READ4_CONNECTION_PASSWORD to the value of DHIS2_READ4_DATABASE_PASSWORD" >&2
      fi

      # Set DHIS2_READ4_CONNECTION_USERNAME to DHIS2_READ4_DATABASE_USERNAME if not provided
      if [ -z "${DHIS2_READ4_CONNECTION_USERNAME:-}" ] && [ -n "${DHIS2_READ4_DATABASE_USERNAME:-}" ]; then
        export DHIS2_READ4_CONNECTION_USERNAME="$DHIS2_READ4_DATABASE_USERNAME"
        echo "[DEBUG] $SELF: set DHIS2_READ4_CONNECTION_USERNAME=$DHIS2_READ4_CONNECTION_USERNAME" >&2
      fi

    fi

    # Read replica 5
    if [ -z "${DHIS2_READ5_CONNECTION_URL:-}" ] \
    && { [ -n "${DHIS2_READ5_DATABASE_HOST:-}" ] || [ -n "${DHIS2_READ5_DATABASE_NAME:-}" ]; } ; then

      # Set DHIS2_READ5_DATABASE_NAME if not provided
      if [ -z "${DHIS2_READ5_DATABASE_NAME:-}" ]; then
        export DHIS2_READ5_DATABASE_NAME="$DHIS2_DATABASE_NAME"
        echo "[DEBUG] $SELF: set DHIS2_READ5_DATABASE_NAME=$DHIS2_READ5_DATABASE_NAME" >&2
      fi

      # Set DHIS2_READ5_CONNECTION_URL as a remote URL if DHIS2_READ5_DATABASE_HOST is provided
      if [ -n "${DHIS2_READ5_DATABASE_HOST:-}" ]; then

        # Set DHIS2_READ5_DATABASE_PORT if not provided
        if [ -z "${DHIS2_READ5_DATABASE_PORT:-}" ]; then
          export DHIS2_READ5_DATABASE_PORT="$DHIS2_DATABASE_PORT"
          echo "[DEBUG] $SELF: set DHIS2_READ5_DATABASE_PORT=$DHIS2_READ5_DATABASE_PORT" >&2
        fi

        export DHIS2_READ5_CONNECTION_URL="jdbc:postgresql://$DHIS2_READ5_DATABASE_HOST:$DHIS2_READ5_DATABASE_PORT/$DHIS2_READ5_DATABASE_NAME"
        echo "[DEBUG] $SELF: set DHIS2_READ5_CONNECTION_URL=$DHIS2_READ5_CONNECTION_URL" >&2

      # Otherwise, use a local connection
      else
        export DHIS2_READ5_CONNECTION_URL="jdbc:postgresql:$DHIS2_READ5_DATABASE_NAME"
        echo "[DEBUG] $SELF: set DHIS2_READ5_CONNECTION_URL=$DHIS2_READ5_CONNECTION_URL" >&2

      fi

      # Set contents of DHIS2_READ5_DATABASE_PASSWORD_FILE to DHIS2_READ5_DATABASE_PASSWORD
      if [ -z "${DHIS2_READ5_DATABASE_PASSWORD:-}" ] && [ -r "${DHIS2_READ5_DATABASE_PASSWORD_FILE:-}" ]; then
        export DHIS2_READ5_DATABASE_PASSWORD="$(<"${DHIS2_READ5_DATABASE_PASSWORD_FILE}")"
        echo "[DEBUG] $SELF: set DHIS2_READ5_DATABASE_PASSWORD from DHIS2_READ5_DATABASE_PASSWORD_FILE" >&2
      fi

      # Set DHIS2_READ5_CONNECTION_PASSWORD if not provided and DHIS2_READ5_DATABASE_PASSWORD is provided
      if [ -z "${DHIS2_READ5_CONNECTION_PASSWORD:-}" ] && [ -n "${DHIS2_READ5_DATABASE_PASSWORD:-}" ]; then
        export DHIS2_READ5_CONNECTION_PASSWORD="$DHIS2_READ5_DATABASE_PASSWORD"
        echo "[DEBUG] $SELF: set DHIS2_READ5_CONNECTION_PASSWORD to the value of DHIS2_READ5_DATABASE_PASSWORD" >&2
      fi

      # Set DHIS2_READ5_CONNECTION_USERNAME to DHIS2_READ5_DATABASE_USERNAME if not provided
      if [ -z "${DHIS2_READ5_CONNECTION_USERNAME:-}" ] && [ -n "${DHIS2_READ5_DATABASE_USERNAME:-}" ]; then
        export DHIS2_READ5_CONNECTION_USERNAME="$DHIS2_READ5_DATABASE_USERNAME"
        echo "[DEBUG] $SELF: set DHIS2_READ5_CONNECTION_USERNAME=$DHIS2_READ5_CONNECTION_USERNAME" >&2
      fi

    fi

    ########

    # Steps to perform if the running user is root:
    if [ "$(id -u)" = '0' ]; then

      if [ "${DISABLE_TOMCAT_TEMPLATES:-}" != '1' ]; then

        # Configure tomcat server.xml as root as a "onetime" remco action.
        remco -config /etc/remco/tomcat.toml

      fi

    fi

  fi

  ########

  # Match first argument to this script.
  # Example: "remco" for a full command of "docker-entrypoint.sh remco -config /etc/remco/config",
  # or "catalina.sh" for a full command of "docker-entrypoint.sh dhis2-init.sh",
  # or "catalina.sh" for a full command of "docker-entrypoint.sh catalina.sh run -security"
  if [ "$1" = 'remco' ] || [ "$1" = 'dhis2-init.sh' ] || [ "$1" = 'catalina.sh' ]; then

    # Steps to perform if the running user is root:
    if [ "$(id -u)" = '0' ]; then

      # Ensure the tomcat user can write to Tomcat and DHIS2 directories
      for TOMCAT_DIR in /usr/local/tomcat/{conf/Catalina,logs,temp,work} /opt/dhis2/{files,logs} ; do
        if [ -d "$TOMCAT_DIR" ]; then
          echo "[DEBUG] $SELF: test if \"tomcat\" user can write to \"$TOMCAT_DIR\"" >&2
          if ! gosu tomcat touch "$TOMCAT_DIR/.writable" ; then
            echo "[DEBUG] $SELF: setting ownership and permissions on \"$TOMCAT_DIR\"" >&2
            chmod --changes u=rwX "$TOMCAT_DIR"
            chown --changes tomcat "$TOMCAT_DIR"
            if ! gosu tomcat touch "$TOMCAT_DIR/.writable" ; then
              echo "[ERROR] $SELF: user \"tomcat\" unable to write to \"$TOMCAT_DIR\", exiting..." >&2
              exit 1
            fi
          fi
          rm --interactive=never "$TOMCAT_DIR/.writable"
        fi
      done

    fi

  fi

  ########

  # Match first argument to this script.
  # Example: "remco" for a full command of "docker-entrypoint.sh remco -config /etc/remco/config",
  # or "catalina.sh" for a full command of "docker-entrypoint.sh catalina.sh run -security"
  if [ "$1" = 'remco' ] || [ "$1" = 'catalina.sh' ]; then

    # Steps to perform if the running user is root:
    if [ "$(id -u)" = '0' ]; then

      # Run the arguments of this script as a command as the tomcat user.
      # NOTE: The script will not continue beyond this point.
      exec gosu tomcat "$@"

    fi

  fi

  # Run the arguments of this script as a command.
  # NOTE: The script will not continue beyond this point.
  exec "$@"

}

if ! _is_sourced; then
  _main "$@"
fi
