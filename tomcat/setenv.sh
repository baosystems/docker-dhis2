# Set environment variables for Tomcat

# Tomcat Lifecycle Listener to shutdown catalina on startup failures (https://github.com/ascheman/tomcat-lifecyclelistener)
# See also /usr/local/tomcat/lib/tomcat-lifecyclelistener.jar and /usr/local/tomcat/conf/context.xml
CATALINA_OPTS="$CATALINA_OPTS -Dorg.apache.catalina.startup.EXIT_ON_INIT_FAILURE=true"
