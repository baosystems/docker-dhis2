# dhis2 image

DHIS2 run by Tomcat.

The default command is `catalina.sh run` like the Tomcat container that it is based on.
Alternatively, the command can be set to `remco` to generate a _dhis.conf_ file from environment
variables and then run `catalina.sh run`.

# Features

## Entry point

The following occur when using _docker-entrypoint.sh_ as the entry point and the command starts with
_remco_:

* If `DATABASE_PASSWORD` is empty or not set, the contents of `DATABASE_PASSWORD_FILE` will be set
  in `DATABASE_PASSWORD`.

* If `DHIS2_REDIS_PASSWORD` is empty or not set, the contents of `DHIS2_REDIS_PASSWORD_FILE` will be set in
  `DHIS2_REDIS_PASSWORD`.

* If `SYSTEM_FQDN` is empty or not set, it will be exported as the output of `hostname --fqdn`.

* If `SYSTEM_IP` is empty or not set, it will be exported as the output of `hostname --ip-address`.

The following occur when using _docker-entrypoint.sh_ as the entry point and the command starts with
_remco_ or _catalina.sh_:

* Use `WAIT_HOSTS`, `WAIT_PATHS`, and [others as
  documented](https://github.com/ufoscout/docker-compose-wait#additional-configuration-options) to
  wait for other hosts or file paths before proceeding. If none are provided, `wait` will exit with
  code 0 immediately and the container will proceed. If `WAIT_HOSTS` is not set and `DATABASE_HOST`
  is provided, `WAIT_HOSTS` will be set as `WAIT_HOSTS=${DATABASE_HOST}:${DATABASE_PORT:-5432}`.
  Similarly, if Redis is enabled, the host and port will be added to `WAIT_HOSTS`.

* If `FORCE_HEALTHCHECK_WAIT` is set to `1`, netcat will listen on port 8080 and respond to a single
  http request with "200 OK" and an empty body. This is to allow a new container to be marked as
  healthy before proceeding to start Tomcat, to which subsequent health checks will actually hit
  DHIS2.

* If the detected user is the root user, paths _/opt/dhis2/files_, _/opt/dhis2/logs_, and
  _/usr/local/tomcat/logs_ will be owned by *tomcat* and the user will be given write access. This
  is to ensure the *tomcat* user always has the ability to write, even if those paths are volume
  mounts.

* If the detected user is the root user, the full command will be run as the *tomcat* user via
  `gosu`.

If the command does not start with _remco_ or _catalina.sh_, then it will be run with `exec` so it
can proceed as pid 1.

## Remco

The default command is `catalina.sh run`, but you can use `remco` instead.
[Remco](https://github.com/HeavyHorst/remco) is used to create _dhis.conf_ and start Tomcat. It will
periodically check to see if _dhis.conf_ needs updated, and if so, restart Tomcat.

## dhis2-init

If the container command is set to `dhis2_init.sh`, each script in _dhis2-init.d_ will be run.
Unless specified to not be used, the _docker-entrypoint.sh_ script will perform the actions listed
above as it pertains to other commands. If _/dhis2-init.progress/_ is shared with other instances of
dhis2-init, only one instance of a script will be performed at a time. Environment variable
`DHIS2_INIT_SKIP` can be set as a comma-seperated value for files in _dhis2-init.d_ to skip. If
`dhis2_init.sh` is not run, it is the responsibility of the operator to ensure the database is
initiated and ready to be used by DHIS2.

* `10_dhis2-database.sh`: Create and initialize a PostgreSQL database with PostGIS. If `WAIT_HOSTS`
  is empty or null, it will be set to `PGHOST`/`DATABASE_HOST`:`PGPORT`/"5432" and the script will
  proceed once the database service is ready. The script requires the following environment
  variables set:

    * `DATABASE_DBNAME` (default: "dhis2")
    * `DATABASE_USERNAME` (default: "dhis")
    * `DATABASE_PASSWORD` or contents in `DATABASE_PASSWORD_FILE` (optional, but strongly
      recommended)
    * `PGHOST` or `DATABASE_HOST` (default: "localhost")
    * `PGPORT` (default: "5432")
    * `PGUSER` (default: "postgres", must be a PostgreSQL superuser)
    * `PGPASSWORD` or contents in `PGPASSWORD_FILE` (required for `PGUSER` in most PostgreSQL
      installations)

* `15_pgstatstatements.sh`: Add the
  [pg_stat_statements](https://www.postgresql.org/docs/current/pgstatstatements.html) extension to
  the `PGDATABASE`. This module is included in the PostGIS container image. If `WAIT_HOSTS` is empty
  or null, it will be set to `PGHOST`/`DATABASE_HOST`:`PGPORT`/"5432" and the script will proceed
  once the database service is ready. The script requires the following environment variables set:

    * `PGDATABASE` (default: "postgres")
    * `PGHOST` or `DATABASE_HOST` (default: "localhost")
    * `PGPORT` (default: "5432")
    * `PGUSER` (default: "postgres", must be a PostgreSQL superuser)
    * `PGPASSWORD` or contents in `PGPASSWORD_FILE` (required for `PGUSER` in most PostgreSQL
      installations)

* `20_dhis2-initwar.sh`: If the last line in _/dhis2-init.progress/20_dhis2-initwar_history.csv_
  does not contain a line stating that the current DHIS2 version and build revision started
  successfully during a previous run of `20_dhis2-initwar.sh`, this script will start and stop
  Tomcat and record its progress. It will use `docker-entrypoint.sh` and `remco` to create
  _dhis.conf_ before starting Tomcat, so read other sections of this README for any values to set
  (for most cases, if the `DATABASE_*` values are set above for `10_dhis2-database.sh`, this script
  will function as expected).

# Settings

The following **OPTIONAL** environment variables are used in `docker-entrypoint.sh` and the first
argument is _remco_:

* `DATABASE_PASSWORD_FILE`: if `DATABASE_PASSWORD` is empty or not set, the contents of
  `DATABASE_PASSWORD_FILE` will be set in `DATABASE_PASSWORD`.

* `DHIS2_REDIS_PASSWORD_FILE`: if `DHIS2_REDIS_PASSWORD` is empty or not set, the contents of
  `DHIS2_REDIS_PASSWORD_FILE` will be set in `DHIS2_REDIS_PASSWORD`.

* `DISABLE_TOMCAT_TEMPLATES`: If set to **1**, the templates for Tomcat configuration files will not
  be generated.

The following **OPTIONAL** environment variables are used in `docker-entrypoint.sh` and the first
argument is _remco_ or _catalina.sh_:

* `FORCE_HEALTHCHECK_WAIT`: if set to **1**, netcat will listen on port 8080 and respond to a single
  http request with "200 OK" to initialize an external health check before proceeding.

## Generating dhis.conf with Remco

The following environment variables can be used to create _dhis.conf_ when using the `remco`
command.

See the [DHIS2
documentation](https://docs.dhis2.org/en/manage/performing-system-administration/dhis-core-version-236/installation.html)
for valid values in _dhis.conf_. _Unless otherwise mentioned, no default value is provided:_

* `DATABASE_HOST`: Database hostname used to set the jdbc value in _connection.url_. If not
  provided, _connection.url_ will be set to _jdbc:postgresql:${DATABASE_DBNAME:-dhis2}_. **NOTE:**
  If `DHIS2_CONNECTION_URL` is provided, it will take precedent.

* `DATABASE_PORT`: If this and `DATABASE_HOST` are provided, used to set the jdbc value in
  _connection.url_; default is "5432". **NOTE:** If `DHIS2_CONNECTION_URL` is provided, it will take
  precedent.

* `DATABASE_DBNAME`: Database name used to set the jdbc value in _connection.url_; default is
  "dhis2". **NOTE:** If `DHIS2_CONNECTION_URL` is provided, it will take precedent.

* `DATABASE_USERNAME`: Value of _connection.username_; default is "dhis". **NOTE:** If
  `DHIS2_CONNECTION_USERNAME` is provided, it will take precedent.

* `DATABASE_PASSWORD`: Value of _connection.password_. **NOTE:** If `DHIS2_CONNECTION_PASSWORD` is
  provided, it will take precedent.

* `DHIS2_SERVER_BASEURL`: Value of _server.base.url_.

* `DHIS2_SERVER_HTTPS`: Value of _server.https_. If this is not set and `DHIS2_SERVER_BASEURL`
  begins with "https://", this will be set to "on".

* `DHIS2_REDIS_ENABLED`: Value of _redis.enabled_.

* `DHIS2_REDIS_HOST`: Value of _redis.host_.

    * `REDIS_HOST` **[DEPRECATED]**: Same as `DHIS2_REDIS_HOST`.

* `DHIS2_REDIS_PORT`: Value of _redis.port_.

    * `REDIS_PORT` **[DEPRECATED]**: Same as `DHIS2_REDIS_PORT`.

* `DHIS2_REDIS_PASSWORD`: Value of _redis.password_.

    * `REDIS_PASSWORD` **[DEPRECATED]**: Same as `DHIS2_REDIS_PASSWORD`.

* `DHIS2_REDIS_USE_SSL`: Value of _redis.use.ssl_.

    * `REDIS_USESSL` **[DEPRECATED]**: If set and any value is provided, the value of
      _redis.use.ssl_ will be set to "true".

* `DHIS2_LEADER_TIME_TO_LIVE_MINUTES`: Value of _leader.time.to.live.minutes_.

    * `REDIS_LEADERTTL` **[DEPRECATED]**: Same as `DHIS2_LEADER_TIME_TO_LIVE_MINUTES`.

* `DHIS2_CLUSTER_HOSTNAME`: Value of _cluster.hostname_. If not provided and both `SERVICE_NAME` and
  `SYSTEM_IP` are provided by the entry point, _cluster.hostname_ will be set as the value of
  `SYSTEM_IP`. **NOTE:** If running DHIS2 2.37 or higher and any `DEBEZIUM_*` option is set, this
  option will be ignored.

* `DHIS2_CLUSTER_CACHE_PORT`: Value of _cluster.cache.port_. **NOTE:** If running DHIS2 2.37 or
  higher and any `DEBEZIUM_*` option is set, this option will be ignored.

* `DHIS2_CLUSTER_CACHE_REMOTE_OBJECT_PORT`: Value of _cluster.cache.remote.object.port_; default is
  "5001" if unset and `DHIS2_CLUSTER_HOSTNAME` is set, or if unset and `SERVICE_NAME` and
  `SYSTEM_IP` are both provided by the entry point. **NOTE:** If running DHIS2 2.37 or higher and
  any `DEBEZIUM_*` option is set, this option will be ignored.

* `DHIS2_CLUSTER_MEMBERS`: Value of _cluster.members_. If not provided and both `SERVICE_NAME` and
  `SYSTEM_IP` are provided, _cluster.members_ will be set as a list of the IP addresses from a DNS
  query of `SERVICE_NAME` with `SYSTEM_ID` removed and _cluster.cache.port_ added. **NOTE:** If
  running DHIS2 2.37 or higher and any `DEBEZIUM_*` option is set, this option will be ignored.

* `SERVICE_NAME`: DNS hostname used to generate the value of _cluster.members_ if
  `DHIS2_CLUSTER_MEMBERS` is not provided. `SYSTEM_IP` must also be set as it is removed from the
  DNS query result to build _cluster.members_. **NOTE:** If running DHIS2 2.37 or higher and any
  `DEBEZIUM_*` option is set, this option will be ignored.

* `DHIS2_NODE_ID`: Value of _node.id_. If not provided, _node.id_ is set by `SYSTEM_FQDN`, which is
  provided by the entry point.

* `DHIS2_LOGGING_FILE_MAXSIZE`: Value of _logging.file.max_size_.

* `DHIS2_LOGGING_FILE_MAXARCHIVES`: Value of _logging.file.max_archives_.

* `DHIS2_MONITORING_API_ENABLED`: Value of _monitoring.api.enabled_.

* `DHIS2_MONITORING_JVM_ENABLED`: Value of _monitoring.jvm.enabled_.

* `DHIS2_MONITORING_DBPOOL_ENABLED`: Value of _monitoring.dbpool.enabled_.

* `DHIS2_MONITORING_HIBERNATE_ENABLED`: Value of _monitoring.hibernate.enabled_.

* `DHIS2_MONITORING_UPTIME_ENABLED`: Value of _monitoring.uptime.enabled_.

* `DHIS2_MONITORING_CPU_ENABLED`: Value of _monitoring.cpu.enabled_.

* `DHIS2_SYSTEM_MONITORING_URL`: Value of _system.monitoring.url_.

* `DHIS2_SYSTEM_MONITORING_USERNAME`: Value of _system.monitoring.username_.

* `DHIS2_SYSTEM_MONITORING_PASSWORD`: Value of _system.monitoring.password_.

* `DHIS2_SYSTEM_READ_ONLY_MODE`: Value of _system.read_only_mode_.

* `DHIS2_SYSTEM_SESSION_TIMEOUT`: Value of _system.session.timeout_.

* `DHIS2_CHANGELOG_AGGREGATE`: Value of _changelog.aggregate_.

* `DHIS2_CHANGELOG_TRACKER`: Value of _changelog.tracker_.

* `DHIS2_AUDIT_LOGGER`: Value of _audit.logger_.

* `DHIS2_AUDIT_DATABASE`: Value of _audit.database_.

* `DHIS2_AUDIT_METADATA`: Value of _audit.metadata_.

* `DHIS2_AUDIT_TRACKER`: Value of _audit.tracker_.

* `DHIS2_AUDIT_AGGREGATE`: Value of _audit.aggregate_.

* `DHIS2_CONNECTION_DIALECT`: Value of _connection.dialect_; default is
  "org.hibernate.dialect.PostgreSQLDialect".

* `DHIS2_CONNECTION_DRIVERCLASS`: Value of _connection.driver_class_; default is
  "org.postgresql.Driver".

* `DHIS2_CONNECTION_SCHEMA`: Value of _connection.schema_; default is "update".

* `DHIS2_CONNECTION_POOL_MAXSIZE`: Value of _connection.pool.max_size_.

* `DHIS2_ENCRYPTION_PASSWORD`: Value of _encryption.password_.

* `DHIS2_FILESTORE_PROVIDER`: Value of _filestore.provider_.

* `DHIS2_FILESTORE_CONTAINER`: Value of _filestore.container_.

* `DHIS2_FILESTORE_LOCATION`: Value of _filestore.location_.

* `DHIS2_FILESTORE_IDENTITY`: Value of _filestore.identity_.

* `DHIS2_FILESTORE_SECRET`: Value of _filestore.secret_.

### 2.36 and up

* `DHIS2_SYSTEM_AUDIT_ENABLED`: Value of _system.audit.enabled_.

### 2.37 and up

* `DHIS2_DEBEZIUM_ENABLED`: Value of _debezium.enabled_; default is 'off'.

* `DHIS2_DEBEZIUM_DB_HOSTNAME`: Value of _debezium.db.hostname_. If `DHIS2_DEBEZIUM_ENABLED` is set
  to "on" and this value is not set, the value of `DATABASE_HOST` will be used.

* `DHIS2_DEBEZIUM_DB_PORT`: Value of _debezium.db.port_. If `DHIS2_DEBEZIUM_ENABLED` is set to "on"
  and this value is not set, the value of `DATABASE_PORT` will be used.

* `DHIS2_DEBEZIUM_DB_NAME`: Value of _debezium.db.name_. If `DHIS2_DEBEZIUM_ENABLED` is set to "on"
  and this value is not set, the value of `DATABASE_DBNAME` will be used.

* `DHIS2_DEBEZIUM_CONNECTION_USERNAME`: Value of _debezium.connection.username_. If
  `DHIS2_DEBEZIUM_ENABLED` is set to "on" and this value is not set, the value of
  `DATABASE_USERNAME` will be used.

* `DHIS2_DEBEZIUM_CONNECTION_PASSWORD`: Value of _debezium.connection.password_. If
  `DHIS2_DEBEZIUM_ENABLED` is set to "on" and this value is not set, the value of
  `DATABASE_PASSWORD` will be used.

* `DHIS2_DEBEZIUM_SLOT_NAME`: Value of _debezium.slot.name_.

* `DHIS2_DEBEZIUM_EXCLUDE_LIST`: Value of _debezium.exclude.list_.

* `DHIS2_DEBEZIUM_SHUTDOWN_ON_CONNECTOR_STOP`: Value of _debezium.shutdown_on.connector_stop_;
  default is 'off'.

## Generating Tomcat server.xml with Remco

The following environment variables can be used to create Tomcat's _server.xml_ when using the
`remco` command.

* `TOMCAT_CONNECTOR_PROXYPORT`: For the primary Connector, value of _proxyPort_. If not provided and
  `DHIS2_SERVER_BASEURL` is set, the value will be derived from the URL port in
  `DHIS2_SERVER_BASEURL`.

* `TOMCAT_CONNECTOR_SCHEME`: For the primary Connector, value of _scheme_. If not provided and
  `DHIS2_SERVER_BASEURL` begins with "https://", the value will be "https".

* `TOMCAT_CONNECTOR_SECURE`: For the primary Connector, value of _secure_. If not provided and
  `DHIS2_SERVER_HTTPS` is "on", the value will be "true".


# Example: Docker Compose

The included
[docker-compose.yml](https://github.com/baosystems/docker-dhis2/blob/main/docker-compose.yml) file
provides a single-node experience with DHIS2 on Tomcat and PostgreSQL with PostGIS. Platform
architectures amd64 and arm64 are supported.

The version of DHIS2 can be set in the _.env_ file; see
[.env.example](https://github.com/baosystems/docker-dhis2/blob/main/.env.example) for an example.
See https://github.com/baosystems/docker-dhis2/pkgs/container/dhis2/versions for available versions.

## Quick

### Start

```bash
docker compose pull

docker compose up --detach
```

You can access the site through http://localhost:8080/

### Watch logs

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
docker compose run --rm pass_init bash -c 'for i in pg_dhis pg_postgres ; do echo -n "pass_${i}.txt: "; cat "/pass_${i}/pass_${i}.txt"; done'
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
wget -nc -O dhis2-db-sierra-leone-2.37.sql.gz https://databases.dhis2.org/sierra-leone/2.37/dhis2-db-sierra-leone.sql.gz

# Stop Tomcat
docker compose stop dhis2

# Drop and re-create the database using the db-empty.sh helper script
docker compose run --rm dhis2_init db-empty.sh

# Import the database backup into the empty database
gunzip -c dhis2-db-sierra-leone-2.37.sql.gz | docker compose exec -T database psql -q -v 'ON_ERROR_STOP=1' --username='postgres' --dbname='dhis2'

# If the previous command didn't work, try the steps below which will copy the file into the container before importing
#docker cp dhis2-db-sierra-leone-2.37.sql.gz "$( docker compose ps -q 'database' | head -n1 )":/tmp/db.sql.gz
#docker compose exec database bash -c "gunzip -c /tmp/db.sql.gz | psql -v 'ON_ERROR_STOP=1' --username='postgres' --dbname='dhis2' && rm -v /tmp/db.sql.gz"

# Re-initialize DHIS2
docker compose run --rm --env 'DHIS2_INIT_FORCE=1' dhis2_init

# Start Tomcat
docker compose start dhis2
```

### Export the database to a file on your system

An included helper script will run `pg_dump` with generated tables excluded and perform some minor
changes to increase the liklihood of being imported on other systems.

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
# Let's say you started with 2.36.6:

cat >> .env <<'EOF'
DHIS2_TAG=2.36.6
EOF

docker compose up --detach

# Later, upgrade to 2.37.2:

cat >> .env <<'EOF'
DHIS2_TAG=2.37.2
EOF

docker compose stop dhis2

docker compose rm -f -s dhis2_init

docker compose pull

docker compose up --detach --remove-orphans
```
