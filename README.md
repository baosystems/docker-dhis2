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
_[.env.example](https://github.com/baosystems/docker-dhis2/blob/main/.env.example)_ for an example.

See
[https://github.com/baosystems/docker-dhis2/pkgs/container/dhis2/versions](https://github.com/orgs/baosystems/packages/container/dhis2/versions?filters%5Bversion_type%5D=tagged)
for available versions of DHIS2.

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

# Initialize the new database
docker compose run --rm --env DHIS2_INIT_FORCE=1 dhis2_init dhis2-init.sh

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

* `10_dhis2-database.sh`: Create and initialize a PostgreSQL database with PostGIS. In addition to
  various `PG*` values being set for connecting to the database, the script requires the following
  environment variables set:

    * `DHIS2_DATABASE_NAME`
    * `DHIS2_DATABASE_USERNAME`
    * `DHIS2_DATABASE_PASSWORD`

* `15_pgstatstatements.sh`: Add the
  [pg_stat_statements](https://www.postgresql.org/docs/current/pgstatstatements.html) extension to
  the `PGDATABASE`. This module is included in the PostGIS container image. The various `PG*` values
  can be set as needed to connect to the database.

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

* `DHIS2_SERVER_BASE_URL`: Value of _server.base.url_.

* `DHIS2_SERVER_HTTPS`: Value of _server.https_. If this is not set and `DHIS2_SERVER_BASE_URL`
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
  `SYSTEM_IP`. **NOTE:** If running any version of DHIS2 2.37 and any `DEBEZIUM_*` option is set,
  this option should not be used.

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
alternative to the _cluster.*_ options shown above. Redis is still required, however.

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

Any option defined in
[ConfigurationKey.java](https://github.com/dhis2/dhis2-core/blob/master/dhis-2/dhis-support/dhis-support-external/src/main/java/org/hisp/dhis/external/conf/ConfigurationKey.java)
for the version fo DHIS2 can be set with an environment variable by transforming all letters to
uppercase and changing all special periods to underscores. For example, to set
_analytics.cache.expiration_ in dhis.conf, set value for `DHIS2_ANALYTICS_CACHE_EXPIRATION` in the
environment. Similarly, for _oidc.provider.google.client_secret_, set
`DHIS2_OIDC_PROVIDER_GOOGLE_CLIENT_SECRET`.


## Generating Tomcat server.xml

The following environment variables can be used to create Tomcat's _server.xml_ when using the
`remco` command.

* `TOMCAT_CONNECTOR_PROXYPORT`: For the primary Connector, value of _proxyPort_. If not provided and
  `DHIS2_SERVER_BASE_URL` is set, the value will be derived from the URL port in
  `DHIS2_SERVER_BASE_URL`.

* `TOMCAT_CONNECTOR_SCHEME`: For the primary Connector, value of _scheme_. If not provided and
  `DHIS2_SERVER_BASE_URL` begins with "https://", the value will be "https".

* `TOMCAT_CONNECTOR_SECURE`: For the primary Connector, value of _secure_. If not provided and
  `DHIS2_SERVER_HTTPS` is "on", the value will be "true".
