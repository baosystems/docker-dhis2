#
# Note: This is a multi-stage build
#

# Setting "ARG"s before the first "FROM" allows for the values to be used in any "FROM" value below.
# ARG values can be overridden with command line arguments.
#
# Ensure docker-compose.yml:services.dhis2.image matches the value of DHIS2_VERSION.

ARG DHIS2_MAJOR=2.36
ARG DHIS2_VERSION=2.36.4

ARG JAVA_MAJOR=11

ARG TOMCAT_MAJOR=9.0
ARG TOMCAT_VERSION=9.0.54

ARG GOSU_VERSION=1.14
ARG REMCO_VERSION=0.12.1
ARG WAIT_VERSION=2.9.0


################################################################################


# DHIS2 downloaded as a separate stage to improve build caches
FROM docker.io/debian:bullseye-20210927 as dhis2-downloader
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends ca-certificates libarchive-tools wget unzip; \
  rm -r -f /var/lib/apt/lists/*
ARG DHIS2_MAJOR
ARG DHIS2_VERSION
WORKDIR /work
RUN set -eux; \
  if [ "$DHIS2_MAJOR" = "dev" ] || [ "$DHIS2_VERSION" = "dev" ]; then \
    wget --quiet -O dhis.war "https://releases.dhis2.org/dev/dhis.war"; \
  elif [ "$DHIS2_VERSION" = "2.34.7" ] \
    || [ "$DHIS2_VERSION" = "2.35.7" ] \
    || [ "$DHIS2_VERSION" = "2.35.8" ] \
    || [ "$DHIS2_VERSION" = "2.36.4" ]; then \
    wget --quiet -O dhis.war "https://releases.dhis2.org/${DHIS2_MAJOR}/dhis2-stable-${DHIS2_VERSION}-EMBARGOED.war"; \
  else \
    wget --quiet -O dhis.war "https://releases.dhis2.org/${DHIS2_MAJOR}/dhis2-stable-${DHIS2_VERSION}.war"; \
  fi; \
  unzip -qq dhis.war -d ROOT; \
  rm -v -f dhis.war; \
  bsdtar -x -f "$( find ROOT -regextype posix-egrep -regex '.*/dhis-service-core-2\.[0-9]+(-(EMBARGOED|SNAPSHOT))?.*\.jar$' )" build.properties; \
  cat build.properties


################################################################################


# gosu for easy step-down from root - https://github.com/tianon/gosu/releases
FROM docker.io/debian:bullseye-20210927 as gosu-downloader
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends ca-certificates gnupg wget; \
  rm -r -f /var/lib/apt/lists/*
ARG GOSU_VERSION
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
FROM docker.io/golang:1.15.2-buster as remco-builder
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends unzip; \
  rm -r -f /var/lib/apt/lists/*
ARG REMCO_VERSION
WORKDIR /work
RUN set -eux; \
  dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
  if [ "$dpkgArch" = "amd64" ]; then \
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
# Tests are excluded due to the time taken building arm64 images in emulation; see https://github.com/ufoscout/docker-compose-wait/issues/54
FROM docker.io/rust:1.55.0-bullseye as wait-builder
ARG WAIT_VERSION
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
FROM "docker.io/tomcat:${TOMCAT_VERSION}-jre${JAVA_MAJOR}-openjdk-slim-bullseye" as dhis2

# Add Java major version to the environment (JAVA_VERSION is provided by the FROM image)
ARG JAVA_MAJOR
ENV JAVA_MAJOR=$JAVA_MAJOR

# Install dig and netcat for use in docker-entrypoint.sh and debugging
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends bind9-dnsutils netcat-traditional; \
  rm -r -f /var/lib/apt/lists/*

# Install unzip and wget for dhis2-init.sh tasks (not included in bullseye-slim)
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends unzip wget; \
  rm -r -f /var/lib/apt/lists/*

# Install latest PostgreSQL client from PGDG for dhis2-init.sh
# Also, install curl and gpg to add the PDGD repository (not included in bullseye-slim)
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends curl gpg; \
  echo "deb http://apt.postgresql.org/pub/repos/apt $( awk -F'=' '/^VERSION_CODENAME/ {print $NF}' /etc/os-release )-pgdg main" > /etc/apt/sources.list.d/pgdg.list; \
  curl --silent https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor > /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg; \
  apt-get update; \
  apt-get install -y --no-install-recommends postgresql-client; \
  rm -r -f /var/lib/apt/lists/*

# Add tools from other build stages and add versions to the environment
COPY --chown=root:root --from=gosu-downloader /work/gosu /usr/local/bin/
ARG GOSU_VERSION
ENV GOSU_VERSION=$GOSU_VERSION
COPY --chown=root:root --from=remco-builder /work/remco /usr/local/bin/
ARG REMCO_VERSION
ENV REMCO_VERSION=$REMCO_VERSION
COPY --chown=root:root --from=wait-builder /work/wait /usr/local/bin/
ARG WAIT_VERSION
ENV WAIT_VERSION=$WAIT_VERSION

# Create tomcat system user, disable crons, and clean up
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
ADD https://repo1.maven.org/maven2/net/aschemann/tomcat/tomcat-lifecyclelistener/1.0.1/tomcat-lifecyclelistener-1.0.1.jar /usr/local/tomcat/lib/tomcat-lifecyclelistener.jar
RUN chmod --changes 0644 /usr/local/tomcat/lib/tomcat-lifecyclelistener.jar
COPY ./tomcat/context.xml /usr/local/tomcat/conf/
COPY ./tomcat/setenv.sh /usr/local/tomcat/bin/

# Tomcat server configuration
COPY ./tomcat/server.xml /usr/local/tomcat/conf/

# Create DHIS2_HOME and set ownership for tomcat user and group (DHIS2 throws an error if /opt/dhis2 is not writable)
RUN set -eux; \
  mkdir -v -p /opt/dhis2; \
  chown --changes tomcat:tomcat /opt/dhis2

# Add contents of the extracted dhis.war
COPY --chown=root:root --from=dhis2-downloader /work/ROOT/ /usr/local/tomcat/webapps/ROOT/

# Add extracted build.properties to DHIS2_HOME
COPY --chown=root:root --from=dhis2-downloader /work/build.properties /opt/dhis2/build.properties

# Add DHIS2 version to the environment
ARG DHIS2_MAJOR
ENV DHIS2_MAJOR=$DHIS2_MAJOR
ARG DHIS2_VERSION
ENV DHIS2_VERSION=$DHIS2_VERSION

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

# Value is copied from the FROM image. If not specified, the CMD in this image would be "null"
CMD ["catalina.sh", "run"]

# Link to repository
LABEL org.opencontainers.image.source=https://github.com/baosystems/docker-dhis2
