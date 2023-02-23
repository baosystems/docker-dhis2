# dhis2 image

This container image contains an entry-point script, bundled applications, and templates to generate
configuration files for DHIS2 and Tomcat to streamline using DHIS2. The sample _docker-compose.yml_
file allows for a "no-config" path to running DHIS2, as other bundled scripts can initialize the
PostgreSQL database for you.

It also supports low-config clustering for running multiple Tomcat instances for a scalable,
highly-available setup of DHIS2.

The container image default command is `remco` to generate the _/opt/dhis2/dhis.conf_ and
_/usr/local/tomcat/conf/server.xml_ files from environment variables and then run `catalina.sh run`.

The container image and the sample Docker Compose file will work on amd64 and arm64 architectures,
including support for Apple Silicon (M1/M2).


# Example: Docker Compose

The included
[docker-compose.yml](https://github.com/baosystems/docker-dhis2/blob/main/docker-compose.yml) file
provides a single-node experience with DHIS2 on Tomcat and PostgreSQL with PostGIS. Platform
architectures amd64 and arm64 are supported.

The version of DHIS2 can be set in the _.env_ file; see
[.env.example](https://github.com/baosystems/docker-dhis2/blob/main/.env.example) for an example.
See [https://github.com/baosystems/docker-dhis2/pkgs/container/dhis2/versions](https://github.com/orgs/baosystems/packages/container/dhis2/versions?filters%5Bversion_type%5D=tagged) for available versions.

## Quick

### Start

```bash
docker compose pull

docker compose up --detach
```

You can access the site through http://localhost:8080/

### Watch logs

View existing logs and watch for new lines:

```bash
docker compose logs --follow
```

Press _Ctrl+c_ to exit logs

### Stop & Start

Stop the entire stack:

```bash
docker compose stop
```

Resume later with:

```bash
docker compose start
```

### Delete All

Delete containers and data storage volumes:

```bash
docker compose down --volumes
```

## Passwords

In this example, passwords are generated for the PostgreSQL database superuser (postgres) and the
DHIS2 database user (dhis). The passwords should not be needed for common operations, but they can
be accessed later via:

```bash
docker compose run --rm pass_init sh -c 'for i in pg_dhis pg_postgres ; do echo -n "pass_${i}.txt: "; cat "/pass_${i}/pass_${i}.txt"; echo; done'
```

## Advanced

### Recreate the database

You'll want an empty database for starting a new DHIS2 installation. Perform the steps below to
remove existing data and re-initialize the database.

```bash
# Stop Tomcat
docker compose stop dhis2

# Drop and re-create the database using a helper script in the container image
docker compose run --rm dhis2_init db-empty.sh

# Start Tomcat
docker compose start dhis2

# Watch Tomcat logs (press Ctrl+c to exit logs)
docker compose logs --follow --tail='10' dhis2
```

### Load a backup file from DHIS2

Sample database files from databases.dhis2.org contain the entire database and require superuser
permissions on the database to import. The following will use an empty database and "convert" it to
match the least-privilege approach used in this setup.

```bash
# Download database file to your system
wget -nc -O dhis2-db-sierra-leone.sql.gz https://databases.dhis2.org/sierra-leone/2.39/dhis2-db-sierra-leone.sql.gz

# Stop Tomcat
docker compose stop dhis2

# Drop and re-create the database using the db-empty.sh helper script
docker compose run --rm dhis2_init db-empty.sh

# Import the database backup into the empty database
gunzip -c dhis2-db-sierra-leone.sql.gz | docker compose exec -T database psql -q -v 'ON_ERROR_STOP=1' --username='postgres' --dbname='dhis2'

# Start Tomcat
docker compose start dhis2
```

### Export the database to a file on your system

An included helper script will run `pg_dump` without generated tables and some other changes to
increase import compatibility with other systems.

```bash
# Stop Tomcat
docker compose stop dhis2

# Export the database using the db-export.sh helper script and compress with gzip
docker compose run --rm dhis2_init db-export.sh | gzip > export.sql.gz

# Start Tomcat
docker compose start dhis2
```

### Upgrade DHIS2 version

If the container tag changes in an updated copy of the Compose file, or if the .env file is changed,
run `docker compose up` again to remove the containers with old images in favor of the new ones.
Because two versions of DHIS2 should not be running at the same time, stop the dhis2 containers
first.

```bash
# Let's say you started with 2.38.2:

cat > .env <<'EOF'
DHIS2_TAG=2.38.2
EOF

docker compose up --detach

# Later, upgrade to 2.39.1.1:

cat > .env <<'EOF'
DHIS2_TAG=2.39.1.1
EOF

docker compose rm --force --stop dhis2 dhis2_init

docker compose pull

docker compose up --detach --remove-orphans
```


# Features

## Entry point

The following occur when using _docker-entrypoint.sh_ as the entry point and the command starts with
_remco_, which are the defaults:

* If `DHIS2_DATABASE_PASSWORD` is empty or not set, the contents of `DHIS2_DATABASE_PASSWORD_FILE`
  will be set as `DHIS2_DATABASE_PASSWORD`.

* If `DHIS2_REDIS_PASSWORD` is empty or not set, the contents of `DHIS2_REDIS_PASSWORD_FILE` will be
  set as `DHIS2_REDIS_PASSWORD`.

* If `SYSTEM_IP` is empty or not set, it will be exported as the output of `hostname --ip-address`.

The following occur when using _docker-entrypoint.sh_ as the entry point (the image default) and the
command starts with _remco_ (the image default) or _catalina.sh_:

* Use `WAIT_HOSTS`, `WAIT_PATHS`, and [others as
  documented to wait](https://github.com/ufoscout/docker-compose-wait#additional-configuration-options)
  for other hosts or file paths before proceeding. If none are provided, `wait` will exit with code 0
  immediately and the container will proceed.

* If the detected user is the *root* user, paths _/opt/dhis2/files_, _/opt/dhis2/logs_, and
  _/usr/local/tomcat/logs_ will be owned by *tomcat* and the user will be given write access. This
  is to ensure the *tomcat* user always has the ability to write, even if those paths are volume
  mounts.

* If the detected user is the *root* user, the full command will be run as the *tomcat* user via
  `gosu`.

If the command does not start with _remco_ (the image default) or _catalina.sh_, then it will be run
with `exec` so it can proceed as pid 1.

## Remco

The default command is `remco`, NOT `catalina.sh run`. [Remco](https://github.com/HeavyHorst/remco)
is used to create _dhis.conf_ and start Tomcat. It will periodically check to see if _dhis.conf_
needs updated (primarily to support [Ehcache
clusters](https://github.com/baosystems/docker-dhis2#ehcache-clustering)), and if so, restart
Tomcat.

## dhis2-init

When the container command is set to `dhis2_init.sh`, each script in
_/usr/local/share/dhis2-init.d/_ will be run. If _/dhis2-init.progress/_ is shared with other
instances of dhis2-init, only one instance of a script will be performed at a time. Environment
variable `DHIS2_INIT_SKIP` can be set as a comma-seperated value for files in
_/usr/local/share/dhis2-init.d/_ to skip. See _docker-compose.yml_ in this repository for example
use.

**NOTE:** If `dhis2_init.sh` is not run, it is the responsibility of the operator to ensure the
database is initiated and ready prior to being used by DHIS2.

The following environment variables are set in `dhis2_init.sh` but can be changed as necessary:

  * `DHIS2_DATABASE_NAME` (default: "dhis2")
  * `DHIS2_DATABASE_USERNAME` (default: "dhis")
  * `DHIS2_DATABASE_PASSWORD` (optional, but strongly recommended) or contents in
    `DHIS2_DATABASE_PASSWORD_FILE`
  * `PGHOST`, or `DHIS2_DATABASE_HOST` (default: "localhost")
  * `PGPORT`, or `DHIS2_DATABASE_PORT` (default: "5432")
  * `PGDATABASE` (default: "postgres")
  * `PGUSER` (default: "postgres", must be a PostgreSQL superuser)
  * `PGPASSWORD` (optional, but strongly recommended, may be required for `PGUSER` in most
    PostgreSQL installations) or contents in `PGPASSWORD_FILE`

### dhis2-init.d scripts

* `10_dhis2-database.sh`: Create and initialize a PostgreSQL database with PostGIS. If `WAIT_HOSTS`
  or `WAIT_PATHS` are provided, it will wait for hosts or file paths before proceeding. In
  addition to various `PG*` values being set for connecting to the database, the script
  requires the following environment variables set:

    * `DHIS2_DATABASE_NAME`
    * `DHIS2_DATABASE_USERNAME`
    * `DHIS2_DATABASE_PASSWORD`

* `15_pgstatstatements.sh`: Add the
  [pg_stat_statements](https://www.postgresql.org/docs/current/pgstatstatements.html) extension to
  the `PGDATABASE`. This module is included in the PostGIS container image. If `WAIT_HOSTS` or
  `WAIT_PATHS` are provided, it will wait for hosts or file paths before proceeding. The various
  `PG*` values can be set as needed to connect to the database.

* `20_dhis2-initwar.sh`: If the last line in _/dhis2-init.progress/20_dhis2-initwar_history.csv_
  does not contain a line stating that the current DHIS2 version and build revision started
  successfully during a previous run of `20_dhis2-initwar.sh`, this script will start and stop
  Tomcat and record its progress. It will use `docker-entrypoint.sh` and `remco` to create
  _dhis.conf_ before starting Tomcat, so read other sections of this README for any values to set
  (for most cases, if the `DATABASE_*` values are set above for `10_dhis2-database.sh`, this script
  will function as expected).


# Settings

The following **OPTIONAL** environment variables are used in `docker-entrypoint.sh` and container
command begins with _remco_ (the image default):

* `DHIS2_DATABASE_PASSWORD_FILE`: if `DHIS2_DATABASE_PASSWORD` is empty or not set, the contents of
  `DHIS2_DATABASE_PASSWORD_FILE` will be set in `DHIS2_DATABASE_PASSWORD`.

* `DHIS2_REDIS_PASSWORD_FILE`: if `DHIS2_REDIS_PASSWORD` is empty or not set, the contents of
  `DHIS2_REDIS_PASSWORD_FILE` will be set in `DHIS2_REDIS_PASSWORD`.

* `DISABLE_TOMCAT_TEMPLATES`: If set to "1", the templates for Tomcat configuration files will not
  be generated.

## Generating dhis.conf with Remco

The following environment variables can be used to create _dhis.conf_ when using the `remco`
command (the image default).

See the [DHIS2
documentation](https://docs.dhis2.org/en/manage/performing-system-administration/dhis-core-version-239/installation.html)
and
[source](https://github.com/dhis2/dhis2-core/blob/master/dhis-2/dhis-support/dhis-support-external/src/main/java/org/hisp/dhis/external/conf/ConfigurationKey.java)
for valid values in _dhis.conf_. _Unless otherwise mentioned, no default value is provided by the
container image,_ however, DHIS2 will often provide a default as specified in the previous link:

### Database

* `DHIS2_DATABASE_HOST`: Database hostname used to set the jdbc value in _connection.url_. If not
  provided, _connection.url_ will be set to _jdbc:postgresql:${DHIS2_DATABASE_NAME:-dhis2}_.
  **NOTE:** If `DHIS2_CONNECTION_URL` is provided, this option will be ignored.

* `DHIS2_DATABASE_PORT`: If this and `DHIS2_DATABASE_HOST` are provided, this is used to set the
  jdbc value in _connection.url_; default is "5432". **NOTE:** If `DHIS2_CONNECTION_URL` is
  provided, this option will be ignored.

* `DHIS2_DATABASE_NAME`: Database name used to set the jdbc value in _connection.url_; default is
  "dhis2". **NOTE:** If `DHIS2_CONNECTION_URL` is provided, this option will be ignored.

* `DHIS2_DATABASE_USERNAME`: Value of _connection.username_; default is "dhis". **NOTE:** If
  `DHIS2_CONNECTION_USERNAME` is provided, this option will be ignored.

* `DHIS2_DATABASE_PASSWORD`: Value of _connection.password_. **NOTE:** If
  `DHIS2_CONNECTION_PASSWORD` is provided, this option will be ignored.

* `DHIS2_DATABASE_PASSWORD_FILE`: Value of _connection.password_ will be set as the content of the
  path provided. **NOTE:** If `DHIS2_CONNECTION_PASSWORD` or `DHIS2_DATABASE_PASSWORD` provided,
  this option will be ignored.

* `DHIS2_CONNECTION_DIALECT`: Value of _connection.dialect_; default is set to
  "org.hibernate.dialect.PostgreSQLDialect" if not provided.

* `DHIS2_CONNECTION_DRIVER_CLASS`: Value of _connection.driver_class_; default is set to
  "org.postgresql.Driver" if not provided.

* `DHIS2_CONNECTION_SCHEMA`: Value of _connection.schema_; default is set to "update" if not
  provided.

#### Read replicas

DHIS2 supports up to 5 [read-replica database
servers](https://docs.dhis2.org/en/full/manage/dhis-core-version-235/system-administration-guide.html#install_read_replica_configuration).
The following values are supported in this container image.

* `DHIS2_READ1_CONNECTION_URL`: Value of _read1.connection.url_. If not provided,
  `DHIS2_READ1_DATABASE_HOST`, `DHIS2_READ1_DATABASE_PORT`, and/or `DHIS2_READ1_DATABASE_NAME` can
  be used similarly to the primary database as explained above.

* `DHIS2_READ1_CONNECTION_USERNAME`: Value of _read1.connection.username_. If not provided,
  `DHIS2_READ1_DATABASE_USERNAME` can be used similarly
  to the primary database as explained above.

* `DHIS2_READ1_CONNECTION_PASSWORD`: Value of _read1.connection.password_. If not provided,
  `DHIS2_READ1_DATABASE_PASSWORD` and/or `DHIS2_READ1_DATABASE_PASSWORD_FILE` can be used similarly
  to the primary database as explained above.

For additional read-replicas, repeat the values above replacing "1" with "2" through "5" as
required.

### Server

* `DHIS2_SERVER_BASEURL`: Value of _server.base.url_.

* `DHIS2_SERVER_HTTPS`: Value of _server.https_. If this is not set and `DHIS2_SERVER_BASEURL`
  begins with "https://", this will be set to "on".

### Redis

Redis alone can be used with clusters of multiple Tomcat instances. It is required for all methods
of clustering DHIS2.

* `DHIS2_REDIS_ENABLED`: Value of _redis.enabled_.

* `DHIS2_REDIS_HOST`: Value of _redis.host_.

* `DHIS2_REDIS_PORT`: Value of _redis.port_.

* `DHIS2_REDIS_PASSWORD`: Value of _redis.password_.

* `DHIS2_REDIS_USE_SSL`: Value of _redis.use.ssl_.

* `DHIS2_LEADER_TIME_TO_LIVE_MINUTES`: Value of _leader.time.to.live.minutes_.

* `DHIS2_REDIS_CACHE_INVALIDATION_ENABLED`: Value of _redis.cache.invalidation.enabled_. Added in
  2.38.2 and 2.39.0. Setting this to "true" is the recommended way to configure a cluster of Tomcat
  instances.

### Ehcache clustering

All versions 2.35.0 and higher support clustering by specifying other Tomcat instances directly in
_dhis.conf_. This works by having each Tomcat node notify each other of changes in Ehcache. If
this method is used, ensure that the Tomcat instances are able to communicate with each other over
the specified ports. Redis is still required, however.

Versions 2.38.2, 2.39.0 and higher now support improved clustering exclusively with
Redis and this method should no longer be used. See _redis.cache.invalidation.enabled_ above.

* `DHIS2_CLUSTER_HOSTNAME`: Value of _cluster.hostname_. If not provided and both `SERVICE_NAME` and
  `SYSTEM_IP` are provided by the entry point, _cluster.hostname_ will be set as the value of
  `SYSTEM_IP`. **NOTE:** If running DHIS2 2.37 or higher and any `DEBEZIUM_*` option is set, this
  option will be ignored.

* `DHIS2_CLUSTER_CACHE_PORT`: Value of _cluster.cache.port_. **NOTE:** If running any version of
  DHIS2 2.37 and any `DEBEZIUM_*` option is set, this option should not be used.

* `DHIS2_CLUSTER_CACHE_REMOTE_OBJECT_PORT`: Value of _cluster.cache.remote.object.port_; default is
  "5001" if unset and `DHIS2_CLUSTER_HOSTNAME` is set, or if unset and `SERVICE_NAME` and
  `SYSTEM_IP` are both provided by the entry point. **NOTE:** If running any version of DHIS2 2.37
  and any `DEBEZIUM_*` option is set, this option should not be used.

* `DHIS2_CLUSTER_MEMBERS`: Value of _cluster.members_. If not provided and both `SERVICE_NAME` and
  `SYSTEM_IP` are provided, _cluster.members_ will be set as a list of the IP addresses from a DNS
  query of `SERVICE_NAME` with `SYSTEM_ID` removed and _cluster.cache.port_ added. **NOTE:** If
  running any version of DHIS2 2.37 and any `DEBEZIUM_*` option is set, this option should not be
  used.

* `SERVICE_NAME`: DNS hostname used to generate the value of _cluster.members_ if
  `DHIS2_CLUSTER_MEMBERS` is not provided. `SYSTEM_IP` must also be set as it is removed from the
  DNS query result to build _cluster.members_. **NOTE:** If running any version of DHIS2 2.37 and
  any `DEBEZIUM_*` option is set, this option should not be used.

* `DHIS2_NODE_ID`: Value of _node.id_. If not provided, _node.id_ is set to the value of `hostname
  --fqdn` in the entry point.

### Debezium clustering

Debezium was introduced in 2.37.0 for use with clusters of multiple Tomcat instances as an
alternative to the _cluster._ options shown above. Redis is still required, however.

Versions 2.38.2, 2.39.0 and higher now support improved clustering exclusively with
Redis and this method should no longer be used. See _redis.cache.invalidation.enabled_ above.

* `DHIS2_DEBEZIUM_ENABLED`: Value of _debezium.enabled_; default is 'off'.

* `DHIS2_DEBEZIUM_DB_HOSTNAME`: Value of _debezium.db.hostname_. If `DHIS2_DEBEZIUM_ENABLED` is set
  to "on" and this value is not set, the value of `DHIS2_DATABASE_HOST` will be used.

* `DHIS2_DEBEZIUM_DB_PORT`: Value of _debezium.db.port_. If `DHIS2_DEBEZIUM_ENABLED` is set to "on"
  and this value is not set, the value of `DHIS2_DATABASE_PORT` will be used.

* `DHIS2_DEBEZIUM_DB_NAME`: Value of _debezium.db.name_. If `DHIS2_DEBEZIUM_ENABLED` is set to "on"
  and this value is not set, the value of `DHIS2_DATABASE_NAME` will be used.

* `DHIS2_DEBEZIUM_CONNECTION_USERNAME`: Value of _debezium.connection.username_. If
  `DHIS2_DEBEZIUM_ENABLED` is set to "on" and this value is not set, the value of
  `DHIS2_DATABASE_USERNAME` will be used.

* `DHIS2_DEBEZIUM_CONNECTION_PASSWORD`: Value of _debezium.connection.password_. If
  `DHIS2_DEBEZIUM_ENABLED` is set to "on" and this value is not set, the value of
  `DHIS2_DATABASE_PASSWORD` will be used.

* `DHIS2_DEBEZIUM_SLOT_NAME`: Value of _debezium.slot.name_.

* `DHIS2_DEBEZIUM_EXCLUDE_LIST`: Value of _debezium.exclude.list_.

* `DHIS2_DEBEZIUM_SHUTDOWN_ON_CONNECTOR_STOP`: Value of _debezium.shutdown_on.connector_stop_;
  default is 'off'.

### Azure OIDC

DHIS2 supports up to 10 Azure AD providers for OIDC. The following environment values can be used in
configuring _dhis.conf_:

* `DHIS_OIDC_PROVIDER_AZURE_0_TENANT`: Value of _oidc.provider.azure.0.tenant_.

* `DHIS_OIDC_PROVIDER_AZURE_0_CLIENT_ID`: Value of _oidc.provider.azure.0.client_id_.

* `DHIS_OIDC_PROVIDER_AZURE_0_CLIENT_SECRET`: Value of _oidc.provider.azure.0.client_secret_.

* `DHIS_OIDC_PROVIDER_AZURE_0_DISPLAY_ALIAS`: Value of _oidc.provider.azure.0.display_alias_.

* `DHIS_OIDC_PROVIDER_AZURE_0_MAPPING_CLAIM`: Value of _oidc.provider.azure.0.mapping_claim_.

* `DHIS_OIDC_PROVIDER_AZURE_0_REDIRECT_URL`: Value of _oidc.provider.azure.0.redirect_url_.

For additional Azure AD providers, repeat the values above replacing "0" with "1" through "9" as
required.

### All configuration options

All supported environment values for setting configuration options in _dhis.conf_ are below.
Values are common to 2.35.0 and up (this list does not include [up to five
read-replicas](#read-replicas) or [up to 10 Azure AD OIDC
providers](#azure-oidc)):

* `DHIS2_ANALYTICS_CACHE_EXPIRATION`: Value of _analytics.cache.expiration_.

* `DHIS2_APPHUB_API_URL`: Value of _apphub.api.url_.

* `DHIS2_APPHUB_BASE_URL`: Value of _apphub.base.url_.

* `DHIS2_ARTEMIS_EMBEDDED_PERSISTENCE`: Value of _artemis.embedded.persistence_.

* `DHIS2_ARTEMIS_EMBEDDED_SECURITY`: Value of _artemis.embedded.security_.

* `DHIS2_ARTEMIS_HOST`: Value of _artemis.host_.

* `DHIS2_ARTEMIS_MODE`: Value of _artemis.mode_.

* `DHIS2_ARTEMIS_PASSWORD`: Value of _artemis.password_.

* `DHIS2_ARTEMIS_PORT`: Value of _artemis.port_.

* `DHIS2_ARTEMIS_USERNAME`: Value of _artemis.username_.

* `DHIS2_AUDIT_AGGREGATE`: Value of _audit.aggregate_.

* `DHIS2_AUDIT_DATABASE`: Value of _audit.database_.

* `DHIS2_AUDIT_LOGGER`: Value of _audit.logger_.

* `DHIS2_AUDIT_METADATA`: Value of _audit.metadata_.

* `DHIS2_AUDIT_TRACKER`: Value of _audit.tracker_.

* `DHIS2_CHANGELOG_AGGREGATE`: Value of _changelog.aggregate_.

* `DHIS2_CHANGELOG_TRACKER`: Value of _changelog.tracker_.

* `DHIS2_CLUSTER_CACHE_PORT`: Value of _cluster.cache.port_.

* `DHIS2_CLUSTER_CACHE_REMOTE_OBJECT_PORT`: Value of _cluster.cache.remote.object.port_.

* `DHIS2_CLUSTER_HOSTNAME`: Value of _cluster.hostname_.

* `DHIS2_CLUSTER_MEMBERS`: Value of _cluster.members_.

* `DHIS2_CONNECTION_DIALECT`: Value of _connection.dialect_.

* `DHIS2_CONNECTION_DRIVER_CLASS`: Value of _connection.driver_class_.

* `DHIS2_CONNECTION_PASSWORD`: Value of _connection.password_.

* `DHIS2_CONNECTION_POOL_ACQUIRE_INCR`: Value of _connection.pool.acquire_incr_.

* `DHIS2_CONNECTION_POOL_IDLE_CON_TEST_PERIOD`: Value of _connection.pool.idle.con.test.period_.

* `DHIS2_CONNECTION_POOL_INITIAL_SIZE`: Value of _connection.pool.initial_size_.

* `DHIS2_CONNECTION_POOL_MAX_IDLE_TIME`: Value of _connection.pool.max_idle_time_.

* `DHIS2_CONNECTION_POOL_MAX_IDLE_TIME_EXCESS_CON`: Value of
  _connection.pool.max_idle_time_excess_con_.

* `DHIS2_CONNECTION_POOL_MAX_SIZE`: Value of _connection.pool.max_size_.

* `DHIS2_CONNECTION_POOL_MIN_SIZE`: Value of _connection.pool.min_size_.

* `DHIS2_CONNECTION_POOL_TEST_ON_CHECKIN`: Value of _connection.pool.test.on.checkin_.

* `DHIS2_CONNECTION_POOL_TEST_ON_CHECKOUT`: Value of _connection.pool.test.on.checkout_.

* `DHIS2_CONNECTION_SCHEMA`: Value of _connection.schema_.

* `DHIS2_CONNECTION_URL`: Value of _connection.url_.

* `DHIS2_CONNECTION_USERNAME`: Value of _connection.username_.

* `DHIS2_ENCRYPTION_PASSWORD`: Value of _encryption.password_.

* `DHIS2_FILESTORE_CONTAINER`: Value of _filestore.container_.

* `DHIS2_FILESTORE_IDENTITY`: Value of _filestore.identity_.

* `DHIS2_FILESTORE_LOCATION`: Value of _filestore.location_.

* `DHIS2_FILESTORE_PROVIDER`: Value of _filestore.provider_.

* `DHIS2_FILESTORE_SECRET`: Value of _filestore.secret_.

* `DHIS2_FLYWAY_MIGRATE_OUT_OF_ORDER`: Value of _flyway.migrate_out_of_order_.

* `DHIS2_GOOGLE_SERVICE_ACCOUNT_CLIENT_ID`: Value of _google.service.account.client.id_.

* `DHIS2_LDAP_MANAGER_DN`: Value of _ldap.manager.dn_.

* `DHIS2_LDAP_MANAGER_PASSWORD`: Value of _ldap.manager.password_.

* `DHIS2_LDAP_SEARCH_BASE`: Value of _ldap.search.base_.

* `DHIS2_LDAP_SEARCH_FILTER`: Value of _ldap.search.filter_.

* `DHIS2_LDAP_URL`: Value of _ldap.url_.

* `DHIS2_LEADER_TIME_TO_LIVE_MINUTES`: Value of _leader.time.to.live.minutes_.

* `DHIS2_LOGGING_FILE_MAX_ARCHIVES`: Value of _logging.file.max_archives_.

* `DHIS2_LOGGING_FILE_MAX_SIZE`: Value of _logging.file.max_size_.

* `DHIS2_METADATA_SYNC_RETRY`: Value of _metadata.sync.retry_.

* `DHIS2_METADATA_SYNC_RETRY_TIME_FREQUENCY_MILLISEC`: Value of
  _metadata.sync.retry.time.frequency.millisec_.

* `DHIS2_MONITORING_API_ENABLED`: Value of _monitoring.api.enabled_.

* `DHIS2_MONITORING_CPU_ENABLED`: Value of _monitoring.cpu.enabled_.

* `DHIS2_MONITORING_DBPOOL_ENABLED`: Value of _monitoring.dbpool.enabled_.

* `DHIS2_MONITORING_HIBERNATE_ENABLED`: Value of _monitoring.hibernate.enabled_.

* `DHIS2_MONITORING_JVM_ENABLED`: Value of _monitoring.jvm.enabled_.

* `DHIS2_MONITORING_UPTIME_ENABLED`: Value of _monitoring.uptime.enabled_.

* `DHIS2_NODE_ID`: Value of _node.id_.

* `DHIS2_OIDC_OAUTH2_LOGIN_ENABLED`: Value of _oidc.oauth2.login.enabled_.

* `DHIS2_OIDC_PROVIDER_GOOGLE_CLIENT_ID`: Value of _oidc.provider.google.client_id_.

* `DHIS2_OIDC_PROVIDER_GOOGLE_CLIENT_SECRET`: Value of _oidc.provider.google.client_secret_.

* `DHIS2_OIDC_PROVIDER_GOOGLE_MAPPING_CLAIM`: Value of _oidc.provider.google.mapping_claim_.

* `DHIS2_REDIS_ENABLED`: Value of _redis.enabled_.

* `DHIS2_REDIS_HOST`: Value of _redis.host_.

* `DHIS2_REDIS_PASSWORD`: Value of _redis.password_.

* `DHIS2_REDIS_PORT`: Value of _redis.port_.

* `DHIS2_REDIS_USE_SSL`: Value of _redis.use.ssl_.

* `DHIS2_SERVER_BASE_URL`: Value of _server.base.url_.

* `DHIS2_SERVER_HTTPS`: Value of _server.https_.

* `DHIS2_SYSTEM_MONITORING_PASSWORD`: Value of _system.monitoring.password_.

* `DHIS2_SYSTEM_MONITORING_URL`: Value of _system.monitoring.url_.

* `DHIS2_SYSTEM_MONITORING_USERNAME`: Value of _system.monitoring.username_.

* `DHIS2_SYSTEM_READ_ONLY_MODE`: Value of _system.read_only_mode_.

* `DHIS2_SYSTEM_SESSION_TIMEOUT`: Value of _system.session.timeout_.

* `DHIS2_SYSTEM_SQL_VIEW_TABLE_PROTECTION`: Value of _system.sql_view_table_protection_.

* `DHIS2_TRACKER_TEMPORARY_OWNERSHIP_TIMEOUT`: Value of _tracker.temporary.ownership.timeout_.


### Added options

Added in 2.35.1, 2.36.0:

* `DHIS2_OIDC_LOGOUT_REDIRECT_URL`: Value of _oidc.logout.redirect_url_.

* `DHIS2_OIDC_PROVIDER_WSO2_CLIENT_ID`: Value of _oidc.provider.wso2.client_id_.

* `DHIS2_OIDC_PROVIDER_WSO2_CLIENT_SECRET`: Value of _oidc.provider.wso2.client_secret_.

* `DHIS2_OIDC_PROVIDER_WSO2_DISPLAY_ALIAS`: Value of _oidc.provider.wso2.display_alias_.

* `DHIS2_OIDC_PROVIDER_WSO2_ENABLE_LOGOUT`: Value of _oidc.provider.wso2.enable_logout_.

* `DHIS2_OIDC_PROVIDER_WSO2_MAPPING_CLAIM`: Value of _oidc.provider.wso2.mapping_claim_.

* `DHIS2_OIDC_PROVIDER_WSO2_SERVER_URL`: Value of _oidc.provider.wso2.server_url_.

Added in 2.35.2, 2.36.0:

* `DHIS2_FLYWAY_REPAIR_BEFORE_MIGRATION`: Value of _flyway.repair_before_migration_.

* `DHIS2_SYSTEM_PROGRAM_RULE_SERVER_EXECUTION`: Value of _system.program_rule.server_execution_.

Added in 2.35.4, 2.36.0:

* `DHIS2_ARTEMIS_EMBEDDED_THREADS`: Value of _artemis.embedded.threads_.

* `DHIS2_AUDIT_IN_MEMORY_QUEUE_ENABLED`: Value of _audit.in_memory_queue.enabled_; Removed in
  2.38.0.

Added in 2.35.7, 2.36.4, 2.37.0:

* `DHIS2_CONNECTION_POOL_NUM_HELPER_THREADS`: Value of _connection.pool.num.helper.threads_.

* `DHIS2_CONNECTION_POOL_PREFERRED_TEST_QUERY`: Value of _connection.pool.preferred.test.query_.

Added in 2.35.8, 2.36.7, 2.37.0:

* `DHIS2_LOGGING_REQUEST_ID_ENABLED`: Value of _logging.request_id.enabled_.

* `DHIS2_LOGGING_REQUEST_ID_HASH`: Value of _logging.request_id.hash_; Removed in 2.38.0.

* `DHIS2_LOGGING_REQUEST_ID_MAX_SIZE`: Value of _logging.request_id.max_size_; Removed in 2.38.0.

Added in 2.35.14, 2.36.11, 2.37.7:

* `DHIS2_AUDIT_LOGGER_FILE_MAX_SIZE`: Value of _audit.logger.file.max_size_.

Added in 2.36.0:

* `DHIS2_ACTIVE_READ_REPLICAS`: Value of _active.read.replicas_.

* `DHIS2_CONNECTION_POOL_TIMEOUT`: Value of _connection.pool.timeout_.

* `DHIS2_CONNECTION_POOL_VALIDATION_TIMEOUT`: Value of _connection.pool.validation_timeout_.

* `DHIS2_DB_POOL_TYPE`: Value of _db.pool.type_.

* `DHIS2_ELAPSED_TIME_QUERY_LOGGING_ENABLED`: Value of _elapsed.time.query.logging.enabled_.

* `DHIS2_ENABLE_QUERY_LOGGING`: Value of _enable.query.logging_.

* `DHIS2_METHOD_QUERY_LOGGING_ENABLED`: Value of _method.query.logging.enabled_.

* `DHIS2_OIDC_PROVIDER_GOOGLE_REDIRECT_URL`: Value of _oidc.provider.google.redirect_url_.

* `DHIS2_OIDC_PROVIDER_WSO2_REDIRECT_URL`: Value of _oidc.provider.wso2.redirect_url_.

* `DHIS2_SLOW_QUERY_LOGGING_THRESHOLD_TIME`: Value of _slow.query.logging.threshold.time_.

* `DHIS2_SYSTEM_AUDIT_ENABLED`: Value of _system.audit.enabled_.

* `DHIS2_SYSTEM_CACHE_MAX_SIZE_FACTOR`: Value of _system.cache.max_size.factor_.

* `DHIS2_TRACKER_IMPORT_PREHEAT_CACHE_ENABLED`: Value of _tracker.import.preheat.cache.enabled_;
  Removed in 2.38.0.

Added in 2.36.3, 2.37.0:

* `DHIS2_OAUTH2_AUTHORIZATION_SERVER_ENABLED`: Value of _oauth2.authorization.server.enabled_.

* `DHIS2_OIDC_JWT_TOKEN_AUTHENTICATION_ENABLED`: Value of _oidc.jwt.token.authentication.enabled_.

Added in 2.36.12.1, 2.37.8.1, 2.38.2.1:

* `DHIS2_CSP_ENABLED`: Value of _csp.enabled_.

* `DHIS2_CSP_HEADER_VALUE`: Value of _csp.header.value_.

* `DHIS2_CSP_UPGRADE_INSECURE_ENABLED`: Value of _csp.upgrade.insecure.enabled_.

Added in 2.37.0:

* `DHIS2_DEBEZIUM_CONNECTION_PASSWORD`: Value of _debezium.connection.password_.

* `DHIS2_DEBEZIUM_CONNECTION_USERNAME`: Value of _debezium.connection.username_.

* `DHIS2_DEBEZIUM_DB_HOSTNAME`: Value of _debezium.db.hostname_.

* `DHIS2_DEBEZIUM_DB_NAME`: Value of _debezium.db.name_.

* `DHIS2_DEBEZIUM_DB_PORT`: Value of _debezium.db.port_.

* `DHIS2_DEBEZIUM_ENABLED`: Value of _debezium.enabled_.

* `DHIS2_DEBEZIUM_EXCLUDE_LIST`: Value of _debezium.exclude.list_.

* `DHIS2_DEBEZIUM_SHUTDOWN_ON_CONNECTOR_STOP`: Value of _debezium.shutdown_on.connector_stop_.

* `DHIS2_DEBEZIUM_SLOT_NAME`: Value of _debezium.slot.name_.

* `DHIS2_ENABLE_API_TOKEN_AUTHENTICATION`: Value of _enable.api_token.authentication_.

* `DHIS2_SYSTEM_CACHE_CAP_PERCENTAGE`: Value of _system.cache.cap.percentage_.

Added in 2.38.0:

* `DHIS2_AUDIT_IN_MEMORY-QUEUE_ENABLED`: Value of _audit.in_memory-queue.enabled_.

* `DHIS2_MAX_SESSIONS_PER_USER`: Value of _max.sessions.per_user_.

* `DHIS2_SYSTEM_UPDATE_NOTIFICATIONS_ENABLED`: Value of _system.update_notifications_enabled_.

Added in 2.38.2, 2.39.0:

* `DHIS2_HIBERNATE_CACHE_USE_QUERY_CACHE`: Value of _hibernate.cache.use_query_cache_.

* `DHIS2_HIBERNATE_CACHE_USE_SECOND_LEVEL_CACHE`: Value of _hibernate.cache.use_second_level_cache_.

* `DHIS2_REDIS_CACHE_INVALIDATION_ENABLED`: Value of _redis.cache.invalidation.enabled_.


### Removed options

Removed in 2.35.1, 2.36.0:

* `DHIS2_OIDC_PROVIDER_GOOGLE_REDIRECT_BASEURL`: Value of _oidc.provider.google.redirect_baseurl_.
  Introduced in 2.35.0 or earlier.

Removed in 2.35.8, 2.36.7, 2.37.0:

* `DHIS2_MONITORING_REQUESTIDLOG_ENABLED`: Value of _monitoring.requestidlog.enabled_. Introduced in
  2.35.0 or earlier.

* `DHIS2_MONITORING_REQUESTIDLOG_HASH`: Value of _monitoring.requestidlog.hash_. Introduced in
  2.35.0 or earlier.

* `DHIS2_MONITORING_REQUESTIDLOG_MAXSIZE`: Value of _monitoring.requestidlog.maxsize_. Introduced in
  2.35.0 or earlier.

Removed in 2.36.0:

* `DHIS2_SYSTEM_INTERNAL_SERVICE_API`: Value of _system.internal_service_api_. Introduced in 2.35.0
  or earlier.

Removed in 2.38.0:

* `DHIS2_AUDIT_IN_MEMORY_QUEUE_ENABLED`: Value of _audit.in_memory_queue.enabled_. Introduced in
  2.35.4, 2.36.0.

* `DHIS2_AUDIT_INMEMORY-QUEUE_ENABLED`: Value of _audit.inmemory-queue.enabled_. Introduced in
  2.35.0 or earlier.

* `DHIS2_LOGGING_REQUEST_ID_HASH`: Value of _logging.request_id.hash_. Introduced in 2.35.8, 2.36.7,
  2.37.0.

* `DHIS2_LOGGING_REQUEST_ID_MAX_SIZE`: Value of _logging.request_id.max_size_. Introduced in 2.35.8,
  2.36.7, 2.37.0.

* `DHIS2_MONITORING_PROVIDER`: Value of _monitoring.provider_. Introduced in 2.35.0 or earlier.

* `DHIS2_TRACKER_IMPORT_PREHEAT_CACHE_ENABLED`: Value of _tracker.import.preheat.cache.enabled_.
  Introduced in 2.36.0.


## Generating Tomcat server.xml

The following environment variables can be used to create Tomcat's _server.xml_ when using the
`remco` command.

* `TOMCAT_CONNECTOR_PROXYPORT`: For the primary Connector, value of _proxyPort_. If not provided and
  `DHIS2_SERVER_BASEURL` is set, the value will be derived from the URL port in
  `DHIS2_SERVER_BASEURL`.

* `TOMCAT_CONNECTOR_SCHEME`: For the primary Connector, value of _scheme_. If not provided and
  `DHIS2_SERVER_BASEURL` begins with "https://", the value will be "https".

* `TOMCAT_CONNECTOR_SECURE`: For the primary Connector, value of _secure_. If not provided and
  `DHIS2_SERVER_HTTPS` is "on", the value will be "true".
