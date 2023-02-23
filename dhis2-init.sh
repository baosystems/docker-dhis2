#!/usr/bin/env bash

# SC2155: Declare and assign separately to avoid masking return values.
# shellcheck disable=SC2155

set -Eeo pipefail


################################################################################


SELF="$( basename "$0" )"

echo "[INFO] $SELF: started..."

# Exit immediately if any required scripts or programs are not found
ITEMS=(
  basename
  dirname
  flock
  head
  mkdir
  rm
  seq
  shuf
  sleep
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

  LOCK_FILE="/dhis2-init.progress/${SELF%.sh}.lock"

  # Random sleep from 0.01 to 5 seconds to prevent possible race condition with acquiring the file lock
  sleep "$( seq 0 .01 5 | shuf | head -n1 )s"

  # Ensure lock file parent directory exists
  if [[ ! -d "$( dirname "$LOCK_FILE" )" ]]; then
    mkdir -p "$( dirname "$LOCK_FILE" )"
  fi

  # Acquire lock as named file
  # NOTE: the named file descriptor cannot be set with a variable and it cannot contain a hyphen
  # http://mywiki.wooledge.org/BashFAQ/045 via http://stackoverflow.com/a/17515965/534275
  # https://github.com/pkrumins/bash-redirections-cheat-sheet/blob/92dac40/bash-redirections-cheat-sheet.txt#L118-L121
  exec {dhis2init}> "$LOCK_FILE"

  # Wait until lock is available before proceeding, exit with error if timeout is reached
  if ! timeout 3600s bash -c "until flock -n ${dhis2init} ; do echo \"[INFO] $SELF: Waiting 10s for lock $LOCK_FILE to be released...\"; sleep 10s; done" ; then
    echo "[WARNING] $SELF: script lock was not released in time, exiting..." >&2
    exit 1
  fi

fi


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


# If PGPASSWORD is empty or null, set it to the contents of PGPASSWORD_FILE
if [[ -z "${PGPASSWORD:-}" ]] && [[ -r "${PGPASSWORD_FILE:-}" ]]; then
  export PGPASSWORD="$(<"${PGPASSWORD_FILE}")"
fi

# If PGHOST is empty or null, set it to DHIS2_DATABASE_HOST
if [[ -z "${PGHOST:-}" ]] && [[ -n "${DHIS2_DATABASE_HOST:-}" ]]; then
  export PGHOST="${DHIS2_DATABASE_HOST:-}"
fi

# If PGPORT is empty or null, set it to DHIS2_DATABASE_PORT
if [[ -z "${PGPORT:-}" ]] && [[ -n "${DHIS2_DATABASE_PORT:-}" ]]; then
  export PGPORT="${DHIS2_DATABASE_PORT:-}"
fi

# Set default values if not provided in the environment
if [[ -z "${PGUSER:-}" ]]; then
  export PGUSER='postgres'
fi
if [[ -z "${PGDATABASE:-}" ]]; then
  export PGDATABASE='postgres'
fi


################################################################################


# Inspired by: https://github.com/docker-library/postgres/blob/ba30220/13/docker-entrypoint.sh
# NOTE: This is to be used as a CMD, not an ENTRYPOINT.


# check to see if this file is being run or sourced from another script
_is_sourced() {
  # https://unix.stackexchange.com/a/215279
  [ "${#FUNCNAME[@]}" -ge 2 ] \
    && [ "${FUNCNAME[0]}" = '_is_sourced' ] \
    && [ "${FUNCNAME[1]}" = 'source' ]
}

# Source: https://github.com/docker-library/postgres/blob/ba30220/13/docker-entrypoint.sh#L144-L173
# usage: dhis2_process_init_files [file [file [...]]]
#    ie: dhis2_process_init_files /usr/local/share/dhis2-init.d/*
# process initializer files, based on file extensions and permissions
dhis2_process_init_files() {
  echo
  local f
  for f; do
    # if the basename of the script is in the environ $DHIS_INIT_SKIP (a list separated by commas), then skip it
    if [[ "${DHIS2_INIT_SKIP:-}" =~ (^|,)$(basename "${f}")(,|$) ]]; then
      echo "[INFO] $SELF: Skipping \"$f\" because \"$(basename "${f}")\" is in DHIS2_INIT_SKIP..."
      echo
      continue
    fi
    case "$f" in
      *.sh)
        # If .sh file is executable, run it
        if [ -x "$f" ]; then
          echo "[INFO] $SELF: running $f"
          "$f"
        # If .sh file is not executable, source it
        else
          echo "[INFO] $SELF: sourcing $f"
          # shellcheck disable=SC1090
          source "$f"
        fi
        ;;
      *)
        echo "[INFO] $SELF: ignoring $f"
        ;;
    esac
    echo
  done
}

_main() {
  # Execute the files in the "/usr/local/share/dhis2-init.d" directory.
  # Ensure files ending in ".sh" have the execute bit or else they will be sourced.
  dhis2_process_init_files /usr/local/share/dhis2-init.d/*


  ################################################################################


  if [[ -d /dhis2-init.progress/ ]]; then
    # Record script progess
    echo "$SELF: COMPLETED" | tee "$STATUS_FILE"
  else
    echo "$SELF: COMPLETED"
  fi

}

if ! _is_sourced; then
  _main "$@"
fi
