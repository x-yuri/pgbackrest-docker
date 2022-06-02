This repository contains a couple of examples of using `pgBackRest` under `docker`. This can be used as a `docker` playground, or as a base for your setup.

* [basic](https://github.com/x-yuri/pgbackrest-docker/tree/basic) `pg` in one container, `pgBackRest` repository in the other, communacation over SSH.
  * [slicd](https://github.com/x-yuri/pgbackrest-docker/tree/slicd) Backups are performed automatically by means of a job scheduler (`slicd`).
    * [rsync](https://github.com/x-yuri/pgbackrest-docker/tree/rsync) Backups are mirrored to the other container over SSH.
    * [cifs](https://github.com/x-yuri/pgbackrest-docker/tree/cifs) Backups are stored in the other container, mounted using CIFS.
      * [readdir-fix](https://github.com/x-yuri/pgbackrest-docker/tree/readdir-fix) A workaround to make expire work with CIFS.
  * [standby-inline](https://github.com/x-yuri/pgbackrest-docker/tree/standby-inline) A standby in the same `docker-compose` project.
  * [standby](https://github.com/x-yuri/pgbackrest-docker/tree/standby) A standby in a separate `docker-compose` project.

Encryption is ignored here.

```
$ ./gen-keys.sh
$ ./gen-pg-stuff.sh
$ docker-compose up
$ cd standby; DONT_START_STANDBY=1 docker-compose up
$ docker-compose exec backups pgbackrest --stanza=db --log-level-console info backup
$ docker-compose exec -u postgres db psql -U postgres -c 'create table t (f int)'
$ docker-compose exec -u postgres db psql -U postgres -c 'insert into t (f) values (1)'
$ cd standby; docker-compose exec -u postgres standby pgbackrest --stanza=db --type standby --log-level-console info restore
$ cd standby; docker-compose up
$ docker-compose exec -u postgres db psql -U postgres -c 'insert into t (f) values (2)'
$ cd standby; docker-compose exec -u postgres standby psql -U postgres -c 'select * from t'
 f 
---
 1
 2
(2 rows)
```

Inspect the state:

```
$ docker-compose exec -u postgres db psql -U postgres -c 'select pg_current_wal_lsn()'
$ docker-compose exec -u postgres db psql -U postgres -xc 'select * from pg_stat_replication'
$ docker-compose exec -u postgres db ps -ef
...
   35 postgres  0:00 postgres: walsender replicator 10.0.0.254(50794) streaming 0/40001C0
$ cd standby; docker-compose exec -u postgres standby psql -U postgres -c 'select pg_is_in_recovery()'
$ cd standby; docker-compose exec -u postgres standby psql -U postgres -c 'select pg_last_wal_receive_lsn()'
$ cd standby; docker-compose exec -u postgres standby psql -U postgres -c 'select pg_last_wal_replay_lsn()'
$ cd standby; docker-compose exec -u postgres standby psql -U postgres -xc 'select * from pg_stat_wal_receiver'
$ cd standby; docker-compose exec -u postgres standby ps -ef
...
   37 postgres  0:00 postgres: walreceiver   streaming 0/40001C0
```

Switchover:

```
$ DONT_START_DB=1 docker-compose up
$ cd standby; docker-compose exec -u postgres standby pg_ctl promote
$ docker-compose exec backups sed -Ei 's/^pg1-host=.*/pg1-host=standby/' /etc/pgbackrest/pgbackrest.conf
$ docker-compose exec backups pgbackrest --stanza=db --log-level-console info backup
```

`.env` (diff):

```diff
diff --git a/.env b/.env
index 93fb278..d5c77f3 100644
--- a/.env
+++ b/.env
@@ -1 +1,5 @@
 DONT_START_DB=
+DB_PORT=5555
+BACKUPS_PORT=2222
+STANDBY_IP=192.168.88.254
+STANDBY_PORT=2223
```

`docker-compose.yml` (diff):

```diff
diff --git a/docker-compose.yml b/docker-compose.yml
index b8b69dc..b1df1ee 100644
--- a/docker-compose.yml
+++ b/docker-compose.yml
@@ -13,6 +13,10 @@ services:
       - ./id_rsa:/id_rsa
       - ./authorized_keys:/authorized_keys
       - ./known_hosts-db:/known_hosts
+    ports:
+      - $DB_PORT:5432
+    networks:
+      - db
 
   backups:
     build:
@@ -25,7 +29,17 @@ services:
       - ./id_rsa:/id_rsa
       - ./authorized_keys:/authorized_keys
       - ./known_hosts-backups:/known_hosts
+    ports:
+      - $BACKUPS_PORT:22
+    networks:
+      - db
 
 volumes:
   db:
   backups:
+
+networks:
+  db:
+    ipam:
+      config:
+        - subnet: 10.0.0.0/24
```

`Dockerfile-db` (diff):

```diff
diff --git a/Dockerfile-db b/Dockerfile-db
index f0c1397..b2c6312 100644
--- a/Dockerfile-db
+++ b/Dockerfile-db
@@ -1,5 +1,5 @@
 FROM postgres:12-alpine3.15
-COPY postgresql.conf db.sh ./
+COPY postgresql.conf pg_hba.conf db.sh ./
 COPY db-init.sh /docker-entrypoint-initdb.d
 COPY pgbackrest-db.conf /etc/pgbackrest/pgbackrest.conf
 RUN set -x && apk add --no-cache pgbackrest openssh pwgen \
```

`db-init.sh` (diff):

```diff
diff --git a/db-init.sh b/db-init.sh
index 091a438..7ad95ae 100644
--- a/db-init.sh
+++ b/db-init.sh
@@ -1 +1,2 @@
-cp postgresql.conf /var/lib/postgresql/data
+cp postgresql.conf pg_hba.conf /var/lib/postgresql/data
+createuser replicator --replication
```

`standby/.env` (diff):

```diff
diff --git a/standby/.env b/standby/.env
new file mode 100644
index 0000000..2ca833e
--- /dev/null
+++ b/standby/.env
@@ -0,0 +1,6 @@
+DONT_START_STANDBY=
+DB_IP=192.168.88.254
+DB_PORT=5555
+BACKUPS_IP=192.168.88.254
+BACKUPS_PORT=2222
+STANDBY_PORT=2223
```

`standby/docker-compose.yml` (diff):

```diff
diff --git a/standby/docker-compose.yml b/standby/docker-compose.yml
new file mode 100644
index 0000000..506f63d
--- /dev/null
+++ b/standby/docker-compose.yml
@@ -0,0 +1,25 @@
+services:
+  standby:
+    build:
+      context: ..
+      dockerfile: standby/Dockerfile
+      args:
+        DB_IP: $DB_IP
+        DB_PORT: $DB_PORT
+        BACKUPS_IP: $BACKUPS_IP
+        BACKUPS_PORT: $BACKUPS_PORT
+    init: yes
+    environment:
+      POSTGRES_HOST_AUTH_METHOD: trust
+      DONT_START_STANDBY: $DONT_START_STANDBY
+    volumes:
+      - db:/var/lib/postgresql/data
+      - ../host-keys-standby:/host-keys
+      - ../id_rsa:/id_rsa
+      - ../authorized_keys:/authorized_keys
+      - ../known_hosts-standby:/known_hosts
+    ports:
+      - $STANDBY_PORT:22
+
+volumes:
+  db:
```

`standby/Dockerfile` (diff):

```diff
diff --git a/standby/Dockerfile b/standby/Dockerfile
new file mode 100644
index 0000000..5549dd7
--- /dev/null
+++ b/standby/Dockerfile
@@ -0,0 +1,14 @@
+FROM postgres:12-alpine3.15
+ARG DB_IP
+ARG DB_PORT
+ARG BACKUPS_IP
+ARG BACKUPS_PORT
+COPY postgresql.conf standby/standby.sh standby/pgbackrest.conf.tpl ./
+COPY standby/db-init.sh /docker-entrypoint-initdb.d
+RUN set -x && apk add --no-cache pgbackrest openssh gettext pwgen \
+    && pg_versions uninstall \
+    && set +x && echo "postgres:`pwgen -1`" | chpasswd && set -x \
+    && envsubst '$DB_IP $DB_PORT $BACKUPS_IP $BACKUPS_PORT' \
+        <pgbackrest.conf.tpl \
+        >/etc/pgbackrest/pgbackrest.conf
+CMD ["./standby.sh"]
```

`standby/db-init.sh` (diff):

```diff
diff --git a/standby/db-init.sh b/standby/db-init.sh
new file mode 100644
index 0000000..091a438
--- /dev/null
+++ b/standby/db-init.sh
@@ -0,0 +1 @@
+cp postgresql.conf /var/lib/postgresql/data
```

`standby/standby.sh` (diff):

```diff
diff --git a/standby/standby.sh b/standby/standby.sh
new file mode 100755
index 0000000..eec98fe
--- /dev/null
+++ b/standby/standby.sh
@@ -0,0 +1,11 @@
+#!/bin/sh -eux
+cp host-keys/* /etc/ssh
+mkdir -p ~postgres/.ssh
+cp id_rsa authorized_keys known_hosts ~postgres/.ssh
+chown -R postgres: ~postgres/.ssh
+/usr/sbin/sshd
+if [ "${DONT_START_STANDBY-}" ]; then
+    exec sleep infinity
+else
+    exec docker-entrypoint.sh postgres
+fi
```

`standby/pgbackrest.conf.tpl` (diff):

```diff
diff --git a/standby/pgbackrest.conf.tpl b/standby/pgbackrest.conf.tpl
new file mode 100644
index 0000000..acfb0ef
--- /dev/null
+++ b/standby/pgbackrest.conf.tpl
@@ -0,0 +1,7 @@
+[db]
+pg1-path=/var/lib/postgresql/data
+recovery-option=primary_conninfo=host=$DB_IP port=$DB_PORT user=replicator
+
+repo1-host=$BACKUPS_IP
+repo1-host-port=$BACKUPS_PORT
+repo1-host-user=root
```

`.env`:

```sh
DONT_START_DB=
DB_PORT=5555
BACKUPS_PORT=2222
STANDBY_IP=192.168.88.254
STANDBY_PORT=2223
```

`docker-compose.yml`:

```yaml
services:
  db:
    build:
      context: .
      dockerfile: Dockerfile-db
    init: yes
    environment:
      POSTGRES_HOST_AUTH_METHOD: trust
      DONT_START_DB: $DONT_START_DB
    volumes:
      - db:/var/lib/postgresql/data
      - ./host-keys:/host-keys
      - ./id_rsa:/id_rsa
      - ./authorized_keys:/authorized_keys
      - ./known_hosts-db:/known_hosts
    ports:
      - $DB_PORT:5432
    networks:
      - db

  backups:
    build:
      context: .
      dockerfile: Dockerfile-backups
    init: yes
    volumes:
      - backups:/var/lib/pgbackrest
      - ./host-keys:/host-keys
      - ./id_rsa:/id_rsa
      - ./authorized_keys:/authorized_keys
      - ./known_hosts-backups:/known_hosts
    ports:
      - $BACKUPS_PORT:22
    networks:
      - db

volumes:
  db:
  backups:

networks:
  db:
    ipam:
      config:
        - subnet: 10.0.0.0/24
```

`Dockerfile-db`:

```dockerfile
FROM postgres:12-alpine3.15
COPY postgresql.conf pg_hba.conf db.sh ./
COPY db-init.sh /docker-entrypoint-initdb.d
COPY pgbackrest-db.conf /etc/pgbackrest/pgbackrest.conf
RUN set -x && apk add --no-cache pgbackrest openssh pwgen \
    && pg_versions uninstall \
    && set +x && echo "postgres:`pwgen -1`" | chpasswd && set -x
CMD ["./db.sh"]
```

`db-init.sh`:

```sh
cp postgresql.conf pg_hba.conf /var/lib/postgresql/data
createuser replicator --replication
```

`db.sh`:

```sh
#!/bin/sh -eux
cp host-keys/* /etc/ssh
mkdir -p ~postgres/.ssh
cp id_rsa authorized_keys known_hosts ~postgres/.ssh
chown -R postgres: ~postgres/.ssh
/usr/sbin/sshd
if [ "${DONT_START_DB-}" ]; then
    exec sleep infinity
else
    exec docker-entrypoint.sh postgres
fi
```

`pgbackrest-db.conf`:

```
[db]
pg1-path=/var/lib/postgresql/data

repo1-host=backups
repo1-host-user=root
```

`Dockerfile-backups`:

```dockerfile
FROM alpine:3.15
COPY backups.sh ./
COPY pgbackrest-backups.conf /etc/pgbackrest/pgbackrest.conf
RUN set -x && apk add --no-cache pgbackrest openssh wait4ports pwgen \
    && set +x && echo "root:`pwgen -1`" | chpasswd && set -x
CMD ["./backups.sh"]
```

`backups.sh`:

```sh
#!/bin/sh -eux
cp host-keys/* /etc/ssh
mkdir -p ~/.ssh
cp id_rsa authorized_keys known_hosts ~/.ssh
/usr/sbin/sshd
if [ "`ls /var/lib/pgbackrest | wc -l`" = 0 ]; then
    wait4ports tcp://db:5432
    pgbackrest --stanza=db --log-level-console info stanza-create
fi
exec sleep infinity
```

`pgbackrest-backups.conf`:

```
[db]
pg1-host=db
pg1-path=/var/lib/postgresql/data

repo1-path=/var/lib/pgbackrest
repo1-retention-full=2
```

`standby/.env`:

```
DONT_START_STANDBY=
DB_IP=192.168.88.254
DB_PORT=5555
BACKUPS_IP=192.168.88.254
BACKUPS_PORT=2222
STANDBY_PORT=2223
```

`standby/docker-compose.yml`:

```yaml
services:
  standby:
    build:
      context: ..
      dockerfile: standby/Dockerfile
      args:
        DB_IP: $DB_IP
        DB_PORT: $DB_PORT
        BACKUPS_IP: $BACKUPS_IP
        BACKUPS_PORT: $BACKUPS_PORT
    init: yes
    environment:
      POSTGRES_HOST_AUTH_METHOD: trust
      DONT_START_STANDBY: $DONT_START_STANDBY
    volumes:
      - db:/var/lib/postgresql/data
      - ../host-keys-standby:/host-keys
      - ../id_rsa:/id_rsa
      - ../authorized_keys:/authorized_keys
      - ../known_hosts-standby:/known_hosts
    ports:
      - $STANDBY_PORT:22

volumes:
  db:
```

`standby/Dockerfile`:

```dockerfile
FROM postgres:12-alpine3.15
ARG DB_IP
ARG DB_PORT
ARG BACKUPS_IP
ARG BACKUPS_PORT
COPY postgresql.conf standby/standby.sh standby/pgbackrest.conf.tpl ./
COPY standby/db-init.sh /docker-entrypoint-initdb.d
RUN set -x && apk add --no-cache pgbackrest openssh gettext pwgen \
    && pg_versions uninstall \
    && set +x && echo "postgres:`pwgen -1`" | chpasswd && set -x \
    && envsubst '$DB_IP $DB_PORT $BACKUPS_IP $BACKUPS_PORT' \
        <pgbackrest.conf.tpl \
        >/etc/pgbackrest/pgbackrest.conf
CMD ["./standby.sh"]
```

`standby/db-init.sh`:

```sh
cp postgresql.conf /var/lib/postgresql/data
```

`standby/standby.sh`:

```sh
#!/bin/sh -eux
cp host-keys/* /etc/ssh
mkdir -p ~postgres/.ssh
cp id_rsa authorized_keys known_hosts ~postgres/.ssh
chown -R postgres: ~postgres/.ssh
/usr/sbin/sshd
if [ "${DONT_START_STANDBY-}" ]; then
    exec sleep infinity
else
    exec docker-entrypoint.sh postgres
fi
```

`standby/pgbackrest.conf.tpl`:

```
[db]
pg1-path=/var/lib/postgresql/data
recovery-option=primary_conninfo=host=$DB_IP port=$DB_PORT user=replicator

repo1-host=$BACKUPS_IP
repo1-host-port=$BACKUPS_PORT
repo1-host-user=root
```
