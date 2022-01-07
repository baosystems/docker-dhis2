# syntax=docker/dockerfile:1.3-labs

# Setting "ARG"s before the first "FROM" allows for the values to be used in any "FROM" value below.
# ARG values can be overridden with command line arguments.
#
# Default for dhis2 image if not provided at build time
ARG BASE_IMAGE="docker.io/library/tomcat:9-jre11-openjdk-slim-bullseye"


################################################################################


# gosu for easy step-down from root - https://github.com/tianon/gosu/releases
# NOTE: Using rust:bullseye instead of debian:bullseye for gpg, unzip, wget preinstalled
FROM docker.io/library/rust:1.57.0-bullseye as gosu-builder
ARG GOSU_VERSION=1.14
WORKDIR /work
RUN set -eux; \
  dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
  wget --quiet -O gosu "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-${dpkgArch}"; \
  wget --quiet -O gosu.asc "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-${dpkgArch}.asc"; \
  gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
  gpg --batch --verify gosu.asc gosu; \
  chmod --changes 0755 gosu; \
  ./gosu --version; \
  ./gosu nobody true


################################################################################


# remco for building template files and controlling Tomcat - https://github.com/HeavyHorst/remco
# Using same verion of golang as shown in the output of `remco -version` from the released 0.12.1 binary.
# The 0.12.1 git tag has a typo in the Makefile.
FROM docker.io/library/golang:1.15.2-buster as remco-builder
ARG REMCO_VERSION=0.12.1
WORKDIR /work
RUN set -eux; \
  dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
  if [ "$dpkgArch" = "amd64" ]; then \
    apt-get update; \
    apt-get install -y --no-install-recommends unzip; \
    rm -r -f /var/lib/apt/lists/*; \
    wget --quiet -O remco_linux.zip "https://github.com/HeavyHorst/remco/releases/download/v${REMCO_VERSION}/remco_${REMCO_VERSION}_linux_${dpkgArch}.zip"; \
    unzip remco_linux.zip; \
    mv --verbose remco_linux remco; \
    chmod --changes 0755 remco; \
  else \
    git clone https://github.com/HeavyHorst/remco.git source; \
    cd source; \
    git checkout "v${REMCO_VERSION}"; \
    if [ "$REMCO_VERSION" = "0.12.1" ]; \
    then \
      sed -e "/^VERSION/ s/0.12.0/0.12.1/" -i Makefile; \
    fi; \
    make; \
    install -v -m 0755 ./bin/remco ..; \
    cd ..; \
  fi; \
  ./remco -version


################################################################################


# wait pauses until remote hosts are available - https://github.com/ufoscout/docker-compose-wait
# Tests are excluded due to the time taken running in arm64 emulation; see https://github.com/ufoscout/docker-compose-wait/issues/54
FROM docker.io/library/rust:1.57.0-bullseye as wait-builder
ARG WAIT_VERSION=2.9.0
WORKDIR /work
RUN set -eux; \
  dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
  if [ "$dpkgArch" = "amd64" ]; then \
    wget "https://github.com/ufoscout/docker-compose-wait/releases/download/${WAIT_VERSION}/wait"; \
    chmod --changes 0755 wait; \
  else \
    git clone https://github.com/ufoscout/docker-compose-wait.git source; \
    cd source; \
    git checkout "$WAIT_VERSION"; \
    R_TARGET="$( rustup target list --installed | grep -- '-gnu' | tail -1 | awk '{print $1}'| sed 's/gnu/musl/' )"; \
    rustup target add "$R_TARGET"; \
    cargo build --release --target="$R_TARGET"; \
    strip ./target/"$R_TARGET"/release/wait; \
    install -v -m 0755 ./target/"$R_TARGET"/release/wait ..; \
    cd ..; \
  fi; \
  ./wait


################################################################################


# Tomcat with OpenJDK - https://hub.docker.com/_/tomcat
FROM "$BASE_IMAGE" as dhis2

# Install dependencies for dhis2-init.sh tasks, docker-entrypoint.sh, and general debugging
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends bind9-dnsutils curl gpg netcat-traditional unzip wget; \
  echo "deb http://apt.postgresql.org/pub/repos/apt $( awk -F'=' '/^VERSION_CODENAME/ {print $NF}' /etc/os-release )-pgdg main" > /etc/apt/sources.list.d/pgdg.list; \
  curl --silent https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg; \
  apt-get update; \
  apt-get install -y --no-install-recommends postgresql-client; \
  rm -r -f /var/lib/apt/lists/*

# Add tools from other build stages
COPY --chown=root:root --from=gosu-builder /work/gosu /usr/local/bin/
COPY --chown=root:root --from=remco-builder /work/remco /usr/local/bin/
COPY --chown=root:root --from=wait-builder /work/wait /usr/local/bin/

# Create and clean up tomcat system user, disable crons
RUN set -eux; \
  adduser --system --disabled-password --group tomcat; \
  echo 'tomcat' >> /etc/cron.deny; \
  echo 'tomcat' >> /etc/at.deny; \
  rm -r -f /etc/.pwd.lock '/etc/group-' '/etc/gshadow-' '/etc/passwd-' '/etc/shadow-'
  
# Set Tomcat permissions for tomcat user and group
RUN set -eux; \
  for TOMCAT_DIR in conf/Catalina logs temp work; \
  do \
    mkdir -p "/usr/local/tomcat/$TOMCAT_DIR"; \
    chmod 0750 "/usr/local/tomcat/$TOMCAT_DIR"; \
    chown -R tomcat:tomcat "/usr/local/tomcat/$TOMCAT_DIR"; \
  done; \
  rm -r -f /tmp/hsperfdata_root /usr/local/tomcat/temp/safeToDelete.tmp

# Tomcat Lifecycle Listener to shutdown catalina on startup failures (https://github.com/ascheman/tomcat-lifecyclelistener)
ADD https://repo.maven.apache.org/maven2/net/aschemann/tomcat/tomcat-lifecyclelistener/1.0.1/tomcat-lifecyclelistener-1.0.1.jar /usr/local/tomcat/lib/tomcat-lifecyclelistener.jar
RUN chmod --changes 0644 /usr/local/tomcat/lib/tomcat-lifecyclelistener.jar
COPY ./tomcat/context.xml /usr/local/tomcat/conf/
COPY ./tomcat/setenv.sh /usr/local/tomcat/bin/

# Tomcat server configuration
COPY ./tomcat/server.xml /usr/local/tomcat/conf/

# Create DHIS2_HOME and set ownership for tomcat user and group (DHIS2 throws an error if /opt/dhis2 is not writable)
RUN set -eux; \
  mkdir -v -p /opt/dhis2; \
  chown --changes tomcat:tomcat /opt/dhis2

# Add dhis2-init.sh and bundled scripts
COPY ./dhis2-init.sh /usr/local/bin/
COPY ./dhis2-init.d/* /usr/local/share/dhis2-init.d/

# Add image helper scripts
COPY ./helpers/* /usr/local/bin/

# remco configurations and templates, and initialize log file for the tomcat user
COPY ./remco/config.toml /etc/remco/config
COPY ./remco/onetime.toml /etc/remco/onetime.toml
COPY ./remco/templates/* /etc/remco/templates/
RUN install -v -o tomcat -g tomcat -m 0644 -T /dev/null /var/log/remco.log

# Add our own entrypoint for initialization
COPY docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]

# Default Tomcat listener (value is copied from the FROM image for verbosity)
EXPOSE 8080

# Mitigation for CVE-2021-44228 "Log4Shell"
ENV LOG4J_FORMAT_MSG_NO_LOOKUPS=true

# Value is copied from the FROM image. If not specified, the CMD in this image would be "null"
CMD ["catalina.sh", "run"]

# Extract the contents of a dhis.war file to webapps/ROOT/, and its build.properties to /opt/dhis2/
RUN --mount=type=bind,source=dhis.war,target=dhis.war <<EOF
set -eux
umask 0022
unzip -qq dhis.war -d /usr/local/tomcat/webapps/ROOT
find /usr/local/tomcat/webapps/ROOT/WEB-INF/lib/ -name 'dhis-service-core-2.*.jar' -exec unzip -p '{}' build.properties \; | tee /opt/dhis2/build.properties
EOF
