# syntax=docker/dockerfile:1.4


################################################################################


# Setting "ARG"s before the first "FROM" allows for the values to be used in any "FROM" value below.
# ARG values can be overridden with command line arguments at build time.
#
# Default for dhis2 image.
ARG BASE_IMAGE=docker.io/library/tomcat:9-jre11-temurin-jammy


################################################################################


# gosu for easy step-down from root - https://github.com/tianon/gosu/releases
FROM docker.io/library/ubuntu:jammy-20230624 as gosu-builder
ARG GOSU_VERSION=1.16
WORKDIR /work
RUN <<EOF
#!/usr/bin/env bash
set -euxo pipefail
dpkgArch="$(dpkg --print-architecture | awk -F'-' '{print $NF}')"
apt update
apt install --yes curl gpg
curl --silent --location --output gosu "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-${dpkgArch}"
curl --silent --location --output gosu.asc "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-${dpkgArch}.asc"
gpg --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4
gpg --verify gosu.asc gosu
chmod --changes 0755 gosu
./gosu --version
./gosu nobody true
EOF


################################################################################


# Remco for building configuration files from templates - https://github.com/HeavyHorst/remco
# Using same verion of golang as shown in the output of `remco -version` from the released amd64 binary.
FROM docker.io/library/golang:1.20.5-bullseye as remco-builder
ARG REMCO_VERSION=0.12.4
WORKDIR /work
RUN <<EOF
#!/usr/bin/env bash
set -euxo pipefail
dpkgArch="$(dpkg --print-architecture | awk -F'-' '{print $NF}')"
if [ "$dpkgArch" = "amd64" ]; then
  apt-get update
  apt-get install --yes --no-install-recommends unzip
  wget --no-verbose --output-document=remco_linux.zip "https://github.com/HeavyHorst/remco/releases/download/v${REMCO_VERSION}/remco_${REMCO_VERSION}_linux_${dpkgArch}.zip"
  unzip remco_linux.zip
  mv --verbose remco_linux remco
  chmod --changes 0755 remco
else
  git clone https://github.com/HeavyHorst/remco.git source
  cd source
  git checkout "v${REMCO_VERSION}"
  make
  install --verbose --mode=0755 ./bin/remco ..
  cd ..
fi
./remco -version
EOF


################################################################################


# Tomcat with OpenJDK - https://hub.docker.com/_/tomcat (see "ARG BASE_IMAGE" above)
FROM $BASE_IMAGE as dhis2

# Update all packages, and install dependencies for dhis2-init.sh tasks, docker-entrypoint.sh, and other commands in this file
RUN <<EOF
#!/usr/bin/env bash
set -euxo pipefail
apt update
env DEBIAN_FRONTEND="noninteractive" LANG="C.UTF-8" apt upgrade --yes
env DEBIAN_FRONTEND="noninteractive" LANG="C.UTF-8" apt install --yes --no-install-recommends ca-certificates curl postgresql-client python3 unzip zip
rm --recursive --force /var/lib/apt/lists/*
EOF

# Add tools from other build stages
COPY --chmod=755 --chown=root:root --from=gosu-builder /work/gosu /usr/local/bin/
COPY --chmod=755 --chown=root:root --from=remco-builder /work/remco /usr/local/bin/

# Create tomcat system user, disable crons, and clean up
RUN <<EOF
#!/usr/bin/env bash
set -euxo pipefail
addgroup \
  --gid 91 \
  tomcat
adduser \
  --system \
  --disabled-password \
  --no-create-home \
  --home /usr/local/tomcat \
  --ingroup tomcat \
  --uid 91 \
  tomcat
echo 'tomcat' >> /etc/cron.deny
echo 'tomcat' >> /etc/at.deny
rm --verbose --force '/etc/group-' '/etc/gshadow-' '/etc/passwd-' '/etc/shadow-'
EOF

# Set Tomcat permissions for tomcat user and group and clean up
RUN <<EOF
#!/usr/bin/env bash
set -euxo pipefail
for TOMCAT_DIR in 'conf/Catalina' 'logs' 'temp' 'work'; do
  mkdir --verbose --parents "/usr/local/tomcat/$TOMCAT_DIR"
  chmod --changes 0750 "/usr/local/tomcat/$TOMCAT_DIR"
  chown --recursive tomcat:tomcat "/usr/local/tomcat/$TOMCAT_DIR"
done
rm --verbose --recursive --force /tmp/hsperfdata_root /usr/local/tomcat/temp/safeToDelete.tmp
EOF

# Tomcat server configuration
COPY --chmod=644 --chown=root:root ./tomcat/server.xml /usr/local/tomcat/conf/

# Create DHIS2_HOME and set ownership for tomcat user and group (DHIS2 throws an error if /opt/dhis2 is not writable)
RUN <<EOF
#!/usr/bin/env bash
set -euxo pipefail
mkdir --verbose --parents /opt/dhis2/files /opt/dhis2/logs
chown --changes tomcat:tomcat /opt/dhis2 /opt/dhis2/files /opt/dhis2/logs
EOF

# Add dhis2-init.sh and bundled scripts
COPY --chmod=755 --chown=root:root ./dhis2-init.sh /usr/local/bin/
COPY --chmod=755 --chown=root:root ./dhis2-init.d/10_dhis2-database.sh /usr/local/share/dhis2-init.d/
COPY --chmod=755 --chown=root:root ./dhis2-init.d/15_pgstatstatements.sh /usr/local/share/dhis2-init.d/
COPY --chmod=755 --chown=root:root ./dhis2-init.d/20_dhis2-initwar.sh /usr/local/share/dhis2-init.d/

# Add image helper scripts
COPY --chmod=755 --chown=root:root ./helpers/db-empty.sh /usr/local/bin/
COPY --chmod=755 --chown=root:root ./helpers/db-export.sh /usr/local/bin/
COPY --chmod=755 --chown=root:root ./helpers/port-from-url.py /usr/local/bin/

# Remco configurations and templates
COPY --chmod=644 --chown=root:root ./remco/config.toml /etc/remco/config
COPY --chmod=644 --chown=root:root ./remco/dhis2-onetime.toml /etc/remco/
COPY --chmod=644 --chown=root:root ./remco/tomcat.toml /etc/remco/
COPY --chmod=644 --chown=root:root ./remco/templates/dhis2/dhis-azureoidc.conf.tmpl /etc/remco/templates/dhis2/
COPY --chmod=644 --chown=root:root ./remco/templates/dhis2/dhis-cluster.conf.tmpl /etc/remco/templates/dhis2/
COPY --chmod=644 --chown=root:root ./remco/templates/dhis2/dhis-rr.conf.tmpl /etc/remco/templates/dhis2/
COPY --chmod=644 --chown=root:root ./remco/templates/dhis2/dhis.conf.tmpl /etc/remco/templates/dhis2/
COPY --chmod=644 --chown=root:root ./remco/templates/tomcat/server.xml.tmpl /etc/remco/templates/tomcat/
# Initialize empty Remco log file for the tomcat user (the "EOF" on the next line is not a typo)
COPY --chmod=644 --chown=tomcat:tomcat <<EOF /var/log/remco.log
EOF

# Add our own entrypoint for initialization
COPY --chmod=755 --chown=root:root docker-entrypoint.sh /usr/local/bin/
ENTRYPOINT ["docker-entrypoint.sh"]

# Remco will create configuration files and start Tomcat
CMD ["remco"]

# Extract the dhis.war file alongside this Dockerfile, and mitigate Log4Shell on old versions
RUN --mount=type=bind,source=dhis.war,target=dhis.war <<EOF
#!/usr/bin/env bash
set -euxo pipefail
# Extract the contents of dhis.war to webapps/ROOT/
unzip -qq dhis.war -d /usr/local/tomcat/webapps/ROOT
# Extract build.properties to /
find /usr/local/tomcat/webapps/ROOT/WEB-INF/lib/ -name 'dhis-service-core-[0-9]*.jar' -exec unzip -p '{}' build.properties \; | tee /build.properties
# Remove vulnerable JndiLookup.class to mitigate Log4Shell
for JAR in /usr/local/tomcat/webapps/ROOT/WEB-INF/lib/log4j-core-2.*.jar ; do
  JAR_LOG4J_VERSION="$( unzip -p "$JAR" 'META-INF/maven/org.apache.logging.log4j/log4j-core/pom.properties' | awk -F'=' '/^version=/ {print $NF}' )"
  if [ "2.16.0" != "$( echo -e "2.16.0\n$JAR_LOG4J_VERSION" | sort --version-sort | head --lines='1' )" ]; then
    set +o pipefail
    if unzip -l "$JAR" | grep --quiet 'JndiLookup.class' ; then
      zip --delete "$JAR" 'org/apache/logging/log4j/core/lookup/JndiLookup.class' | grep --invert-match 'zip warning'
    fi
    set -o pipefail
  fi
done
EOF

# Create Remco template for dhis.conf based on the ConfigurationKey.java file in GitHub for the build version
RUN <<EOF
#!/usr/bin/env bash
set -euo pipefail
# WAR version without suffix like "-SNAPSHOT" or "-rc1"
DHIS2_VERSION_NOSUFFIX="$( awk -F'=' '/^build\.version/ {gsub(/ /, "", $NF); print $NF}' /build.properties | grep --only-matching --extended-regexp '^2\.[0-9\.]+' )"
# Determine major version, like "2.37" from "2.37.9"
DHIS2_MAJOR="$( cut -c1-4 <<< "$DHIS2_VERSION_NOSUFFIX" )"
# Attempt to find file from GitHub tag, then find the GitHub branch, and fallback to the master branch URL
DHIS2_CONFIGKEY_URL="https://github.com/dhis2/dhis2-core/raw/${DHIS2_VERSION_NOSUFFIX}/dhis-2/dhis-support/dhis-support-external/src/main/java/org/hisp/dhis/external/conf/ConfigurationKey.java"
if ! curl -o /dev/null -fsSL "$DHIS2_CONFIGKEY_URL" ; then
  DHIS2_CONFIGKEY_URL="https://github.com/dhis2/dhis2-core/raw/${DHIS2_MAJOR}/dhis-2/dhis-support/dhis-support-external/src/main/java/org/hisp/dhis/external/conf/ConfigurationKey.java"
  if ! curl -o /dev/null -fsSL "$DHIS2_CONFIGKEY_URL" ; then
    DHIS2_CONFIGKEY_URL="https://github.com/dhis2/dhis2-core/raw/master/dhis-2/dhis-support/dhis-support-external/src/main/java/org/hisp/dhis/external/conf/ConfigurationKey.java"
  fi
fi
# Grab file on GitHub, sanitize, and create Remco template with default values and comments
curl -fsSL "$DHIS2_CONFIGKEY_URL" \
| grep -E '^\s+[[:upper:]][[:upper:]]+[^\(]+\(' `# limit to lines beginning with whitespace, two or more uppercase letters, parameter name ending with (` \
| sed -r 's/^\s+//g' `# remove leading spaces` \
| sed  `# convert to strings` \
  -e 's/Constants\.OFF/off/g' \
  -e 's/Constants\.ON/on/g' \
  -e 's/Constants\.FALSE/false/g' \
  -e 's/Constants\.TRUE/true/g' \
  -e "s/CspUtils\.DEFAULT_HEADER_VALUE/script-src 'none';/g" \
  -e 's/String\.valueOf( SECONDS.toMillis( \([0-9]\+\) ) )/\1000/g' \
| awk -F'[ ,]' '{print $2","$4}' `# using [[:space:]] and comma as field separators, print fields separated commas for csv rows` \
| sed \
  -r \
  -e 's/"([^"]+)"/\1/g' `# remove quotation marks from non-empty quoted values` \
  -e 's/""$//g' `# drop empty quoted values` \
| sed \
  -e '/^cluster\.\(cache\.\(\|remote\.object\.\)port\|hostname\|members\)/d'  `# remove options that will be added with dhis-cluster.conf.tmpl` \
  -e '/^active\.read\.replicas/d'  `# remove option not intended to be set` \
| sort \
| while IFS= read -r LINE ; do
  CONFIG_OPTION="$( awk -F',' '{print $1}' <<<"$LINE" )"
  CONFIG_DEFAULT="$( awk -F',' '{print $2}' <<<"$LINE" )"
  TEMPLATE_OPTION="$( sed -e 's,^,/dhis2/,' <<<"$CONFIG_OPTION" | tr '._' '/' )"
  cat >> /tmp/.dhis.conf.tmpl <<EOS
{% if exists("${TEMPLATE_OPTION}") %}
${CONFIG_OPTION} = {{ getv("${TEMPLATE_OPTION}") }}
{% else %}
#${CONFIG_OPTION} = ${CONFIG_DEFAULT}
{% endif %}
EOS
done
# Add clustering settings (keep template logic in Remco for DNS lookups of SERVICE_NAME)
if curl -fsSL "$DHIS2_CONFIGKEY_URL" | grep -q 'CLUSTER_HOSTNAME( "cluster\.hostname",' ; then
  cat /etc/remco/templates/dhis2/dhis-cluster.conf.tmpl >> /tmp/.dhis.conf.tmpl
fi
# Add read-replica settings
cat /etc/remco/templates/dhis2/dhis-rr.conf.tmpl >> /tmp/.dhis.conf.tmpl
# Add Azure OIDC settings
cat /etc/remco/templates/dhis2/dhis-azureoidc.conf.tmpl >> /tmp/.dhis.conf.tmpl
# Add comment at the top about how the file was generated
sed -e "1i##\n## Template generated from $DHIS2_CONFIGKEY_URL\n##\n" -i /tmp/.dhis.conf.tmpl
# Add template section at the end for unspecified values
echo -e '{% if exists("/dhis2/unspecified") %}\n\n##\n## Unspecified settings\n##\n\n{{ getv("/dhis2/unspecified") }}\n{% endif %}' >> /tmp/.dhis.conf.tmpl
# Move generated template into place
mv --force /tmp/.dhis.conf.tmpl /etc/remco/templates/dhis2/dhis.conf.tmpl
EOF
