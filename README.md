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
$ DONT_START_STANDBY=1 docker-compose up
$ docker-compose exec backups pgbackrest --stanza=db --log-level-console info backup
$ docker-compose exec -u postgres db psql -U postgres -c 'create table t (f int)'
$ docker-compose exec -u postgres db psql -U postgres -c 'insert into t (f) values (1)'
$ docker-compose exec -u postgres standby pgbackrest --stanza=db --type standby --log-level-console info restore
$ docker-compose up
$ docker-compose exec -u postgres db psql -U postgres -c 'insert into t (f) values (2)'
$ docker-compose exec -u postgres standby psql -U postgres -c 'select * from t'
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
$ docker-compose exec -u postgres standby psql -U postgres -c 'select pg_is_in_recovery()'
$ docker-compose exec -u postgres standby psql -U postgres -c 'select pg_last_wal_receive_lsn()'
$ docker-compose exec -u postgres standby psql -U postgres -c 'select pg_last_wal_replay_lsn()'
$ docker-compose exec -u postgres standby psql -U postgres -xc 'select * from pg_stat_wal_receiver'
$ docker-compose exec -u postgres standby ps -ef
...
   37 postgres  0:00 postgres: walreceiver   streaming 0/40001C0
```

Switchover:

```
$ DONT_START_DB=1 docker-compose up
$ docker-compose exec -u postgres standby pg_ctl promote
$ docker-compose exec backups sed -Ei 's/^pg1-host=.*/pg1-host=standby/' /etc/pgbackrest/pgbackrest.conf
$ docker-compose exec backups pgbackrest --stanza=db --log-level-console info backup
```

`.env` (diff):

```diff
diff --git a/.env b/.env
index 93fb278..a530150 100644
--- a/.env
+++ b/.env
@@ -1 +1,2 @@
 DONT_START_DB=
+DONT_START_STANDBY=
```

`docker-compose.yml` (diff):

```diff
diff --git a/docker-compose.yml b/docker-compose.yml
index b8b69dc..674b1ef 100644
--- a/docker-compose.yml
+++ b/docker-compose.yml
@@ -3,16 +3,21 @@ services:
     build:
       context: .
       dockerfile: Dockerfile-db
+      args:
+        ROLE: primary
     init: yes
     environment:
       POSTGRES_HOST_AUTH_METHOD: trust
       DONT_START_DB: $DONT_START_DB
+      ROLE: primary
     volumes:
       - db:/var/lib/postgresql/data
       - ./host-keys:/host-keys
       - ./id_rsa:/id_rsa
       - ./authorized_keys:/authorized_keys
       - ./known_hosts-db:/known_hosts
+    networks:
+      - db
 
   backups:
     build:
@@ -25,7 +30,37 @@ services:
       - ./id_rsa:/id_rsa
       - ./authorized_keys:/authorized_keys
       - ./known_hosts-backups:/known_hosts
+    networks:
+      - db
+
+  standby:
+    build:
+      context: .
+      dockerfile: Dockerfile-db
+      args:
+        ROLE: standby
+    init: yes
+    environment:
+      POSTGRES_HOST_AUTH_METHOD: trust
+      DONT_START_STANDBY: $DONT_START_STANDBY
+      ROLE: standby
+    volumes:
+      - standby:/var/lib/postgresql/data
+      - ./host-keys-standby:/host-keys
+      - ./id_rsa:/id_rsa
+      - ./authorized_keys:/authorized_keys
+      - ./known_hosts-standby:/known_hosts
+    networks:
+      db:
+        ipv4_address: 10.0.0.254
 
 volumes:
   db:
+  standby:
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
index f0c1397..0bb6495 100644
--- a/Dockerfile-db
+++ b/Dockerfile-db
@@ -1,8 +1,14 @@
 FROM postgres:12-alpine3.15
-COPY postgresql.conf db.sh ./
+ARG ROLE
+COPY postgresql.conf pg_hba.conf db.sh ./
 COPY db-init.sh /docker-entrypoint-initdb.d
-COPY pgbackrest-db.conf /etc/pgbackrest/pgbackrest.conf
+COPY pgbackrest-db.conf pgbackrest-standby.conf ./
 RUN set -x && apk add --no-cache pgbackrest openssh pwgen \
     && pg_versions uninstall \
-    && set +x && echo "postgres:`pwgen -1`" | chpasswd && set -x
+    && set +x && echo "postgres:`pwgen -1`" | chpasswd && set -x \
+    && if [ "$ROLE" = primary ]; then \
+        cp pgbackrest-db.conf /etc/pgbackrest/pgbackrest.conf; \
+    else \
+        cp pgbackrest-standby.conf /etc/pgbackrest/pgbackrest.conf; \
+    fi
 CMD ["./db.sh"]
```

`db-init.sh` (diff):

```diff
diff --git a/db-init.sh b/db-init.sh
index 091a438..df9ec85 100644
--- a/db-init.sh
+++ b/db-init.sh
@@ -1 +1,4 @@
-cp postgresql.conf /var/lib/postgresql/data
+cp postgresql.conf pg_hba.conf /var/lib/postgresql/data
+if [ "$ROLE" = primary ]; then
+    createuser replicator --replication
+fi
```

`db.sh` (diff):

```diff
diff --git a/db.sh b/db.sh
index b0c1de5..7c7be94 100755
--- a/db.sh
+++ b/db.sh
@@ -4,7 +4,7 @@ mkdir -p ~postgres/.ssh
 cp id_rsa authorized_keys known_hosts ~postgres/.ssh
 chown -R postgres: ~postgres/.ssh
 /usr/sbin/sshd
-if [ "${DONT_START_DB-}" ]; then
+if [ "${DONT_START_DB-}" ] || [ "${DONT_START_STANDBY-}" ]; then
     exec sleep infinity
 else
     exec docker-entrypoint.sh postgres
```

`pgbackrest-standby.conf` (diff):

```diff
diff --git a/pgbackrest-standby.conf b/pgbackrest-standby.conf
new file mode 100644
index 0000000..a6eb66b
--- /dev/null
+++ b/pgbackrest-standby.conf
@@ -0,0 +1,6 @@
+[db]
+pg1-path=/var/lib/postgresql/data
+recovery-option=primary_conninfo=host=db user=replicator
+
+repo1-host=backups
+repo1-host-user=root
```

`.env`:

```sh
DONT_START_DB=
DONT_START_STANDBY=
```

`docker-compose.yml`:

```yaml
services:
  db:
    build:
      context: .
      dockerfile: Dockerfile-db
      args:
        ROLE: primary
    init: yes
    environment:
      POSTGRES_HOST_AUTH_METHOD: trust
      DONT_START_DB: $DONT_START_DB
      ROLE: primary
    volumes:
      - db:/var/lib/postgresql/data
      - ./host-keys:/host-keys
      - ./id_rsa:/id_rsa
      - ./authorized_keys:/authorized_keys
      - ./known_hosts-db:/known_hosts
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
    networks:
      - db

  standby:
    build:
      context: .
      dockerfile: Dockerfile-db
      args:
        ROLE: standby
    init: yes
    environment:
      POSTGRES_HOST_AUTH_METHOD: trust
      DONT_START_STANDBY: $DONT_START_STANDBY
      ROLE: standby
    volumes:
      - standby:/var/lib/postgresql/data
      - ./host-keys-standby:/host-keys
      - ./id_rsa:/id_rsa
      - ./authorized_keys:/authorized_keys
      - ./known_hosts-standby:/known_hosts
    networks:
      db:
        ipv4_address: 10.0.0.254

volumes:
  db:
  standby:
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
ARG ROLE
COPY postgresql.conf pg_hba.conf db.sh ./
COPY db-init.sh /docker-entrypoint-initdb.d
COPY pgbackrest-db.conf pgbackrest-standby.conf ./
RUN set -x && apk add --no-cache pgbackrest openssh pwgen \
    && pg_versions uninstall \
    && set +x && echo "postgres:`pwgen -1`" | chpasswd && set -x \
    && if [ "$ROLE" = primary ]; then \
        cp pgbackrest-db.conf /etc/pgbackrest/pgbackrest.conf; \
    else \
        cp pgbackrest-standby.conf /etc/pgbackrest/pgbackrest.conf; \
    fi
CMD ["./db.sh"]
```

`db-init.sh`:

```sh
cp postgresql.conf pg_hba.conf /var/lib/postgresql/data
if [ "$ROLE" = primary ]; then
    createuser replicator --replication
fi
```

`db.sh`:

```sh
#!/bin/sh -eux
cp host-keys/* /etc/ssh
mkdir -p ~postgres/.ssh
cp id_rsa authorized_keys known_hosts ~postgres/.ssh
chown -R postgres: ~postgres/.ssh
/usr/sbin/sshd
if [ "${DONT_START_DB-}" ] || [ "${DONT_START_STANDBY-}" ]; then
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

`pgbackrest-standby.conf`:

```
[db]
pg1-path=/var/lib/postgresql/data
recovery-option=primary_conninfo=host=db user=replicator

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
