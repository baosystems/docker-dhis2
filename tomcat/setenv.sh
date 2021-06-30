#!/usr/bin/env bash

# check to see if this file is being run or sourced from another script
_is_sourced() {
  # https://unix.stackexchange.com/a/215279
  [ "${#FUNCNAME[@]}" -ge 2 ] \
    && [ "${FUNCNAME[0]}" = '_is_sourced' ] \
    && [ "${FUNCNAME[1]}" = 'source' ]
}

_main() {
  # Tomcat Lifecycle Listener to shutdown catalina on startup failures (https://github.com/ascheman/tomcat-lifecyclelistener)
  # See also /usr/local/tomcat/lib/tomcat-lifecyclelistener.jar and /usr/local/tomcat/conf/context.xml
  export CATALINA_OPTS="$CATALINA_OPTS -Dorg.apache.catalina.startup.EXIT_ON_INIT_FAILURE=true"
}

if _is_sourced; then
  _main "$@"
fi
