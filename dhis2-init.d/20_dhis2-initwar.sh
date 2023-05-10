#!/usr/bin/env bash

# SC2155: Declare and assign separately to avoid masking return values.
# shellcheck disable=SC2155

set -Eeo pipefail


################################################################################


SELF="$( basename "$0" )"

echo "[INFO] $SELF: started..."

# Exit immediately if any required scripts or programs are not found
ITEMS=(
  awk
  catalina.sh
  curl
  dirname
  docker-entrypoint.sh
  env
  gosu
  grep
  mkdir
  remco
  rm
  sleep
  tail
  tee
  timeout
  unzip
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

fi


################################################################################


if [[ -d /dhis2-init.progress/ ]]; then

  # Set path for history file
  HISTORY_FILE="/dhis2-init.progress/${SELF%.sh}_history.csv"

  # Ensure history file parent directory exists
  if [[ ! -d "$( dirname "$HISTORY_FILE" )" ]]; then
    mkdir -p "$( dirname "$HISTORY_FILE" )"
  fi

  # Initialize history file
  if [[ ! -f "$HISTORY_FILE" ]]; then
    echo "build.version,build.revision,build.time,status,datelog" > "$HISTORY_FILE"
  fi

  # Set DHIS2 build information (logic also used in docker-entrypoint.sh)
  DHIS2_BUILD_PROPERTIES="$( unzip -q -p "$( find /usr/local/tomcat/webapps/ROOT/WEB-INF/lib -maxdepth 1 -type f -name 'dhis-service-core-[0-9]*.jar' )" build.properties )"
  DHIS2_BUILD_VERSION="$( awk -F'=' '/^build\.version/ {gsub(/ /, "", $NF); print $NF}' <<< "$DHIS2_BUILD_PROPERTIES" )"
  DHIS2_BUILD_REVISION="$( awk -F'=' '/^build\.revision/ {gsub(/ /, "", $NF); print $NF}' <<< "$DHIS2_BUILD_PROPERTIES" )"
  DHIS2_BUILD_TIME="$( awk -F'=' '/^build\.time/ {sub(/ /, "", $NF); print $NF}' <<< "$DHIS2_BUILD_PROPERTIES" )"

  # Skip if history file contains status message written at the end and DHIS2_INIT_FORCE is not equal to "1"
  if [[ "${DHIS2_INIT_FORCE:-0}" != "1" ]] && { tail -1 "$HISTORY_FILE" | grep -q "${DHIS2_BUILD_VERSION},${DHIS2_BUILD_REVISION},${DHIS2_BUILD_TIME},success" ; } ; then
    echo "[INFO] $SELF: script has already run for ${DHIS2_BUILD_VERSION},${DHIS2_BUILD_REVISION}, skipping..."
    exit 0
  fi

fi


################################################################################


# Set CATALINA_PID to improve chances of a clean shutdown
export CATALINA_PID="${CATALINA_HOME:-/usr/local/tomcat}/temp/catalina.pid"

# Use remco to generate configuration file
echo "[INFO] $SELF: Generate dhis.conf from template"
if [ "$(id -u)" = '0' ]; then
  gosu tomcat \
    remco -config /etc/remco/dhis2-onetime.toml
else
  remco -config /etc/remco/dhis2-onetime.toml
fi

# Start Tomcat in the background as the tomcat user
echo "[INFO] $SELF: Start Tomcat in the background: CATALINA_PID=$CATALINA_PID catalina.sh start"
if [ "$(id -u)" = '0' ]; then
  gosu tomcat \
    catalina.sh start
else
  catalina.sh start
fi

# Give Tomcat time to start up
sleep 3

# Assume DHIS2 is ready when the login page renders
if timeout --signal=SIGINT 900s bash -c "until curl --output /dev/null --silent --max-time 3 --fail http://localhost:8080/dhis-web-commons/security/login.action ; do echo [INFO] $SELF: Waiting for DHIS2 login screen... ; sleep 3 ; done"
then
  echo "[INFO] $SELF: DHIS2 login screen accessed"
else
  echo "[ERROR] $SELF: Unable to access DHIS2 login screen, exiting..." >&2

  if [[ -d /dhis2-init.progress/ ]]; then
    echo "${DHIS2_BUILD_VERSION},${DHIS2_BUILD_REVISION},${DHIS2_BUILD_TIME},failed,$(date '+%F %T')" >> "$HISTORY_FILE"
  fi

  exit 1
fi

# Stop the background Tomcat process
echo "[INFO] $SELF: Stop Tomcat: CATALINA_PID=$CATALINA_PID catalina.sh stop -force"
if [ "$(id -u)" = '0' ]; then
  gosu tomcat \
    catalina.sh stop 90 -force
else
  catalina.sh stop 90 -force
fi


################################################################################


if [[ -d /dhis2-init.progress/ ]]; then
  # Record script progess
  echo "$SELF: COMPLETED" | tee "$STATUS_FILE"

  echo "[INFO] $SELF: Add to history file ${HISTORY_FILE}:"
  echo "${DHIS2_BUILD_VERSION},${DHIS2_BUILD_REVISION},${DHIS2_BUILD_TIME},success,$(date '+%F %T')" | tee -a "$HISTORY_FILE"

else
  echo "$SELF: COMPLETED"
fi
