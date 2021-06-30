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
  flock
  grep
  head
  mkdir
  rm
  seq
  shuf
  sleep
  tail
  tee
  timeout
  unzip
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
  echo "[DEBUG] $SELF: DHIS2_INIT_FORCE=1; delete \"$STATUS_FILE\"..."
  rm -v -f "$STATUS_FILE"
fi


################################################################################


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

# Lookup information about the deployed version of DHIS2
export BUILD_PROPERTIES="$( unzip -q -p "$( find /usr/local/tomcat/webapps/ROOT/WEB-INF/lib -maxdepth 1 -type f -name "dhis-service-core-2.*.jar" )" build.properties )"
export BUILD_REVISION="$( echo "$BUILD_PROPERTIES" | awk -F'=' '/^build\.revision/ {gsub(/ /, "", $NF); print $NF}' )"
export BUILD_VERSION="$( echo "$BUILD_PROPERTIES" | awk -F'=' '/^build\.version/ {gsub(/ /, "", $NF); print $NF}' )"
export BUILD_TIME="$( echo "$BUILD_PROPERTIES" | awk -F'=' '/^build\.time/ {sub(/ /, "", $NF); print $NF}' )"

# Skip if history file contains status message written at the end and DHIS2_INIT_FORCE is not equal to "1"
if [[ "${DHIS2_INIT_FORCE:-0}" != "1" ]] && { tail -1 "$HISTORY_FILE" | grep -q "${BUILD_VERSION},${BUILD_REVISION},${BUILD_TIME},success" ; } ; then
  echo "[INFO] $SELF: script has already run for ${BUILD_VERSION},${BUILD_REVISION}, skipping..."
  exit 0
fi


################################################################################


# Set CATALINA_PID to improve chances of a clean shutdown
export CATALINA_PID="${CATALINA_HOME:-/usr/local/tomcat}/temp/catalina.pid"

# Use remco to generate dhis.conf
# Entrypoint will wait for the database server to be available and run remco as the tomcat user
docker-entrypoint.sh \
  remco -config /etc/remco/onetime.toml

# Start Tomcat in the background as the tomcat user
echo "[INFO] $SELF: Start Tomcat in the background: CATALINA_PID=$CATALINA_PID catalina.sh start"
gosu tomcat \
  catalina.sh start

echo "[INFO] $SELF: Wait for Tomcat to listen on localhost:8080"
env \
  WAIT_BEFORE=3 \
  WAIT_HOSTS=localhost:8080 \
  WAIT_TIMEOUT=300 \
  /usr/local/bin/wait

# Assume DHIS2 is ready when the login page renders
if timeout --signal=SIGINT 900s bash -c "until curl --output /dev/null --silent --max-time 3 --fail http://localhost:8080/dhis-web-commons/security/login.action ; do echo [INFO] $SELF: Waiting for DHIS2 login screen... ; sleep 3 ; done"
then
  echo "[INFO] $SELF: DHIS2 login screen accessed"
else
  echo "$SELF: [ERROR] Unable to access DHIS2 login screen, exiting..." >&2
  echo "${BUILD_VERSION},${BUILD_REVISION},${BUILD_TIME},failed,$(date '+%F %T')" >> "$HISTORY_FILE"
  exit 1
fi

# Stop the background Tomcat process
echo "[INFO] $SELF: Stop Tomcat: CATALINA_PID=$CATALINA_PID catalina.sh stop 90 -force"
gosu tomcat \
  catalina.sh stop 90 -force


################################################################################


# Record script progess
echo "[INFO] $SELF: Add to history file ${HISTORY_FILE}:"
echo "${BUILD_VERSION},${BUILD_REVISION},${BUILD_TIME},success,$(date '+%F %T')" | tee -a "$HISTORY_FILE"
echo "$SELF: COMPLETED" | tee "$STATUS_FILE"
