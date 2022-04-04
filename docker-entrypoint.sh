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
  # Example: "remco" for a full command of "docker-entrypoint.sh remco -config /etc/remco/config"
  if [ "$1" = 'remco' ]; then

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

    # Set SYSTEM_FQDN as hostname
    if [ -z "${SYSTEM_FQDN:-}" ]; then
      export SYSTEM_FQDN="$(hostname --fqdn)"
      echo "[DEBUG] $SELF: set SYSTEM_FQDN=$SYSTEM_FQDN" >&2
    fi

    # Set SYSTEM_IP to the internal IP address
    if [ -z "${SYSTEM_IP:-}" ]; then
      export SYSTEM_IP="$(hostname --ip-address)"
      echo "[DEBUG] $SELF: set SYSTEM_IP=$SYSTEM_IP" >&2
    fi

    # Set DHIS2_SERVER_HTTPS to "on" if not set and DHIS2_SERVER_BASEURL begins with "https://"
    if [ -z "${DHIS2_SERVER_HTTPS:-}" ] && [[ "${DHIS2_SERVER_BASEURL:-}" =~ ^https:// ]]; then
      export DHIS2_SERVER_HTTPS="on"
      echo "[DEBUG] $SELF: set DHIS2_SERVER_HTTPS=$DHIS2_SERVER_HTTPS" >&2
    fi

    # Set TOMCAT_CONNECTOR_PROXYPORT if not set to value dervied from DHIS2_SERVER_BASEURL if set
    if [ -z "${TOMCAT_CONNECTOR_PROXYPORT:-}" ] && [ -n "${DHIS2_SERVER_BASEURL:-}" ]; then
      export TOMCAT_CONNECTOR_PROXYPORT="$( port-from-url.py "$DHIS2_SERVER_BASEURL" )"
      echo "[DEBUG] $SELF: set TOMCAT_CONNECTOR_PROXYPORT=$TOMCAT_CONNECTOR_PROXYPORT" >&2
    fi

    # Set TOMCAT_CONNECTOR_SCHEME to "https" if not set and DHIS2_SERVER_BASEURL begins with "https://"
    if [ -z "${TOMCAT_CONNECTOR_SCHEME:-}" ] && [[ "${DHIS2_SERVER_BASEURL:-}" =~ ^https:// ]]; then
      export TOMCAT_CONNECTOR_SCHEME="https"
      echo "[DEBUG] $SELF: set TOMCAT_CONNECTOR_SCHEME=$TOMCAT_CONNECTOR_SCHEME" >&2
    fi

    # Set TOMCAT_CONNECTOR_SECURE to "true" if not set and DHIS2_SERVER_HTTPS is "on"
    if [ -z "${TOMCAT_CONNECTOR_SECURE:-}" ] && [ "${DHIS2_SERVER_HTTPS:-}" = "on" ]; then
      export TOMCAT_CONNECTOR_SECURE="true"
      echo "[DEBUG] $SELF: set TOMCAT_CONNECTOR_SECURE=$TOMCAT_CONNECTOR_SECURE" >&2
    fi

    # Set DHIS2 build information (logic also used in 20_dhis2-initwar.sh)
    DHIS2_BUILD_PROPERTIES="$( unzip -q -p "$( find /usr/local/tomcat/webapps/ROOT/WEB-INF/lib -maxdepth 1 -type f -name "dhis-service-core-2.*.jar" )" build.properties )"
    export DHIS2_BUILD_VERSION="$( awk -F'=' '/^build\.version/ {gsub(/ /, "", $NF); print $NF}' <<< "$DHIS2_BUILD_PROPERTIES" )"
    export DHIS2_BUILD_MAJOR="$( cut -c1-4 <<< "$DHIS2_BUILD_VERSION" )"
    export DHIS2_BUILD_REVISION="$( awk -F'=' '/^build\.revision/ {gsub(/ /, "", $NF); print $NF}' <<< "$DHIS2_BUILD_PROPERTIES" )"
    export DHIS2_BUILD_TIME="$( awk -F'=' '/^build\.time/ {sub(/ /, "", $NF); print $NF}' <<< "$DHIS2_BUILD_PROPERTIES" )"
    export DHIS2_BUILD_DATE="$( grep --only-matching --extended-regexp '20[0-9]{2}-[0-9]{2}-[0-9]{2}' <<< "$DHIS2_BUILD_TIME" )"

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

  # Again, match first argument to this script.
  # Example: "remco" for a full command of "docker-entrypoint.sh remco -config /etc/remco/config",
  # or "catalina.sh" for a full command of "docker-entrypoint.sh catalina.sh run -security"
  if [ "$1" = 'remco' ] || [ "$1" = 'catalina.sh' ]; then

    # Print some environment variables for debugging purposes if values are set
    VARS=(
      DHIS2_BUILD_MAJOR
      DHIS2_BUILD_VERSION
      DHIS2_BUILD_REVISION
      DHIS2_BUILD_DATE
      DHIS2_BUILD_TIME
      FORCE_HEALTHCHECK_WAIT
      WAIT_BEFORE
      WAIT_HOSTS
      WAIT_PATHS
      WAIT_TIMEOUT
      JAVA_MAJOR
      JAVA_VERSION
      JAVA_OPTS
      TOMCAT_MAJOR
      TOMCAT_VERSION
      CATALINA_OPTS
    )
    for VAR in "${VARS[@]}"; do
      if [ -n "${!VAR:-}" ]; then
        echo "[DEBUG] $SELF: environment $VAR=${!VAR}" >&2
      fi
    done
    unset VARS

    ########

    # Ensure there are no trailing commas for WAIT_HOSTS or WAIT_PATHS if provided.
    if [ -n "${WAIT_HOSTS:-}" ]; then
      export WAIT_HOSTS="${WAIT_HOSTS%,}"
      echo "[DEBUG] $SELF: environment WAIT_HOSTS=$WAIT_HOSTS" >&2
    fi
    if [ -n "${WAIT_PATHS:-}" ]; then
      export WAIT_PATHS="${WAIT_PATHS%,}"
      echo "[DEBUG] $SELF: environment WAIT_PATHS=$WAIT_PATHS" >&2

      # Increase the timeout from 30 seconds to allow for dhis2_init to complete.
      if [ -z "${WAIT_TIMEOUT:-}" ]; then
        export WAIT_TIMEOUT='300'
        echo "[DEBUG] $SELF: environment WAIT_TIMEOUT=$WAIT_TIMEOUT" >&2
      fi
    fi

    # Wait for hosts specified in the environment variable WAIT_HOSTS and/or paths in WAIT_PATHS.
    # If it times out before the hostss and/or paths are available, it will exit with a non-0
    # signal, and this script will exit because of the bash options set at the top.
    if [ -n "${WAIT_HOSTS:-}" ] || [ -n "${WAIT_PATHS:-}" ]; then
      echo "[DEBUG] $SELF: running /usr/local/bin/wait" >&2
      /usr/local/bin/wait 2> >( sed -r -e 's/^\[(DEBUG|INFO)\s+(wait)\]/[\1] \2:/g' >&2 )
    fi

    ########

    # If environment variable FORCE_HEALTHCHECK_WAIT=1, run netcat as a webserver
    # before proceeding (nc will stop listening after a single request is received).
    if [ "${FORCE_HEALTHCHECK_WAIT:-}" = '1' ]; then
      echo "[DEBUG] $SELF: match FORCE_HEALTHCHECK_WAIT=1" >&2
      echo -n -e "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nContent-Type: text/plain\r\n\r\n" | nc -l -q 1 -p 8080
      echo "[DEBUG] $SELF: health check received, continuing" >&2
    fi

    ########

    # Steps to perform if the running user is root:
    if [ "$(id -u)" = '0' ]; then

      # The paths below might be mounts, so ensure that tomcat is the owner and can write
      for dir in /opt/dhis2/files /opt/dhis2/logs /usr/local/tomcat/logs ; do
        if [ -d "$dir" ]; then
          echo "[DEBUG] $SELF: setting $dir ownership and permissions" >&2
          chmod --changes u=rwX "$dir"
          chown --changes tomcat "$dir"
        fi
      done

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
