This repository contains a couple of examples of using `pgBackRest` under `docker`. This can be used as a `docker` playground, or as a base for your setup.

* [basic](https://github.com/x-yuri/pgbackrest-docker/tree/basic) `pg` in one container, `pgBackRest` repository in the other, communacation over SSH.
  * [slicd](https://github.com/x-yuri/pgbackrest-docker/tree/slicd) Backups are performed automatically by means of a job scheduler (`slicd`).
    * [rsync](https://github.com/x-yuri/pgbackrest-docker/tree/rsync) Backups are mirrored to the other container over SSH.
    * [cifs](https://github.com/x-yuri/pgbackrest-docker/tree/cifs) Backups are stored in the other container, mounted using CIFS.
      * [readdir-fix](https://github.com/x-yuri/pgbackrest-docker/tree/readdir-fix) A workaround to make expire work with CIFS.
  * [standby-inline](https://github.com/x-yuri/pgbackrest-docker/tree/standby-inline) A standby in the same `docker-compose` project.
  * [standby](https://github.com/x-yuri/pgbackrest-docker/tree/standby) A standby in a separate `docker-compose` project.

Encryption is ignored here.

Provide values in `.env`:

```sh
MAILGUN_KEY=...
MAILGUN_DOMAIN=...
MAILGUN_FROM=...
MAILGUN_TO=...
STORAGE_BOX=...  # //SERVER/SHARE
STORAGE_BOX_USER=...
STORAGE_BOX_PASS=...
```

There are [issues][a] with using CIFS under [Alpine Linux][b]:

[a]: https://github.com/pgbackrest/pgbackrest/issues/1754#issuecomment-1133805373
[b]: https://gist.github.com/x-yuri/aa6db295cd56f757537f756bc390b1df

```
2022-05-27 19:29:00.003 P00   INFO: backup command begin 2.36: --exec-id=64-57aba533 --log-level-console=info --pg1-host=db --pg1-path=/var/lib/postgresql/data --repo1-path=/mnt/pgbackrest --repo1-retention-full=2 --repo1-type=cifs --stanza=db --type=full
2022-05-27 19:29:00.820 P00   INFO: execute non-exclusive pg_start_backup(): backup begins after the next regular checkpoint completes
2022-05-27 19:29:01.223 P00   INFO: backup start archive = 000000010000000000000006, lsn = 0/6000028
2022-05-27 19:29:32.283 P00   INFO: execute non-exclusive pg_stop_backup() and wait for all WAL segments to archive
2022-05-27 19:29:32.484 P00   INFO: backup stop archive = 000000010000000000000006, lsn = 0/6000138
2022-05-27 19:29:32.515 P00   INFO: check archive for segment(s) 000000010000000000000006:000000010000000000000006
2022-05-27 19:29:32.771 P00   INFO: new backup label = 20220527-192900F
2022-05-27 19:29:33.011 P00   INFO: full backup size = 23.6MB, file total = 979
2022-05-27 19:29:33.011 P00   INFO: backup command end: completed successfully (33008ms)
2022-05-27 19:29:33.011 P00   INFO: expire command begin 2.36: --exec-id=64-57aba533 --log-level-console=info --repo1-path=/mnt/pgbackrest --repo1-retention-full=2 --repo1-type=cifs --stanza=db
2022-05-27 19:29:33.021 P00   INFO: repo1: expire full backup 20220527-192645F
2022-05-27 19:29:33.086 P00   INFO: repo1: remove expired backup 20220527-192645F
ERROR: [061]: repo1: unable to remove path '/mnt/pgbackrest/backup/db/20220527-192645F/pg_data/base/13457': [39] Directory not empty
ERROR: [104]: expire command encountered 1 error(s), check the log file for details
2022-05-27 19:29:33.434 P00   INFO: expire command end: aborted with exception [104]
```

See the [`readdir-fix`](https://github.com/x-yuri/pgbackrest-docker/tree/readdir-fix) branch.

```
$ ./gen-keys.sh
$ ./gen-postgresql.conf.sh
$ docker-compose up
```

Wait for a backup.

```
$ docker-compose exec -u postgres db psql -U postgres -c 'create table t (f int)'
$ docker-compose exec -u postgres db psql -U postgres -c 'insert into t (f) values (1)'
$ docker-compose exec -u postgres db psql -U postgres -c 'select * from t'
 f 
---
 1
(1 row)
$ docker-compose exec -u postgres db psql -U postgres -Atc 'select current_timestamp'
2022-05-23 03:55:24.782817+00
$ docker-compose exec -u postgres db psql -U postgres -c 'insert into t (f) values (2)'
$ docker-compose exec -u postgres db psql -U postgres -c 'select * from t'
 f 
---
 1
 2
(2 rows)
```

Wait for a backup.

Restore:

```
$ DISABLE_BACKUPS=1 DONT_START_DB=1 docker-compose up
$ docker-compose exec db sh -c 'rm -r /var/lib/postgresql/data/*'
$ docker-compose exec -u postgres db pgbackrest --stanza=db --log-level-console info restore
$ DISABLE_BACKUPS=1 docker-compose up
$ docker-compose exec -u postgres db psql -U postgres -c 'select * from t'
 f 
---
 1
 2
(2 rows)
```

PITR:

```
$ DISABLE_BACKUPS=1 DONT_START_DB=1 docker-compose up
$ docker-compose exec db sh -c 'rm -r /var/lib/postgresql/data/*'
$ docker-compose exec -u postgres db pgbackrest --stanza=db --log-level-console info --type time --target '2022-05-23 03:55:24.782817+00' --target-action promote restore
$ DISABLE_BACKUPS=1 docker-compose up
$ docker-compose exec -u postgres db psql -U postgres -c 'select * from t'
 f 
---
 1
(1 row)
```

`.env` (diff):

```diff
diff --git a/.env b/.env
index 8c0695c..b9be029 100644
--- a/.env
+++ b/.env
@@ -4,3 +4,6 @@ MAILGUN_KEY=...
 MAILGUN_DOMAIN=...
 MAILGUN_FROM=...
 MAILGUN_TO=...
+STORAGE_BOX=...
+STORAGE_BOX_USER=...
+STORAGE_BOX_PASS=...
```

`docker-compose.yml` (diff):

```diff
diff --git a/docker-compose.yml b/docker-compose.yml
index 25ab1af..8d715ac 100644
--- a/docker-compose.yml
+++ b/docker-compose.yml
@@ -19,14 +19,17 @@ services:
       context: .
       dockerfile: Dockerfile-backups
     init: yes
+    privileged: yes
     environment:
       DISABLE_BACKUPS: $DISABLE_BACKUPS
       MAILGUN_KEY: $MAILGUN_KEY
       MAILGUN_DOMAIN: $MAILGUN_DOMAIN
       MAILGUN_FROM: $MAILGUN_FROM
       MAILGUN_TO: $MAILGUN_TO
+      STORAGE_BOX: $STORAGE_BOX
+      STORAGE_BOX_USER: $STORAGE_BOX_USER
+      STORAGE_BOX_PASS: $STORAGE_BOX_PASS
     volumes:
-      - backups:/var/lib/pgbackrest
       - ./host-keys:/host-keys
       - ./id_rsa:/id_rsa
       - ./authorized_keys:/authorized_keys
@@ -34,4 +37,3 @@ services:
 
 volumes:
   db:
-  backups:
```

`Dockerfile-backups` (diff):

```diff
diff --git a/Dockerfile-backups b/Dockerfile-backups
index ef00a1d..dc72446 100644
--- a/Dockerfile-backups
+++ b/Dockerfile-backups
@@ -17,7 +17,8 @@ COPY backups.sh ./
 COPY pgbackrest-backups.conf /etc/pgbackrest/pgbackrest.conf
 COPY --from=slicd /bin/slicd-* /bin/setuid /bin/miniexec /bin/
 COPY crontab back-up.sh ./
-RUN set -x && apk add --no-cache pgbackrest openssh curl wait4ports pwgen \
+RUN set -x && apk add --no-cache pgbackrest openssh cifs-utils \
+        curl wait4ports pwgen \
     && set +x && echo "root:`pwgen -1`" | chpasswd && set -x \
     && slicd-parser -s crontab -o crontab.bin
 CMD ["./backups.sh"]
```

`backups.sh` (diff):

```diff
diff --git a/backups.sh b/backups.sh
index e3d544d..33931a4 100755
--- a/backups.sh
+++ b/backups.sh
@@ -1,9 +1,12 @@
 #!/bin/sh -eux
+echo "username=$STORAGE_BOX_USER" > /backup-creds.txt
+set +x; echo "password=$STORAGE_BOX_PASS" >> /backup-creds.txt; set -x
+mount.cifs -o cred=/backup-creds.txt,file_mode=0600,dir_mode=0700 "$STORAGE_BOX" /mnt
 cp host-keys/* /etc/ssh
 mkdir -p ~/.ssh
 cp id_rsa authorized_keys known_hosts ~/.ssh
 /usr/sbin/sshd
-if [ "`ls /var/lib/pgbackrest | wc -l`" = 0 ]; then
+if ! [ -e /mnt/pgbackrest ]; then
     wait4ports tcp://db:5432
     pgbackrest --stanza=db --log-level-console info stanza-create
 fi
```

`pgbackrest-backups.conf` (diff):

```diff
diff --git a/pgbackrest-backups.conf b/pgbackrest-backups.conf
index 783d575..3777c6d 100644
--- a/pgbackrest-backups.conf
+++ b/pgbackrest-backups.conf
@@ -2,5 +2,6 @@
 pg1-host=db
 pg1-path=/var/lib/postgresql/data
 
-repo1-path=/var/lib/pgbackrest
+repo1-path=/mnt/pgbackrest
+repo1-type=cifs
 repo1-retention-full=2
```

`.env`:

```sh
DONT_START_DB=
DISABLE_BACKUPS=
MAILGUN_KEY=...
MAILGUN_DOMAIN=...
MAILGUN_FROM=...
MAILGUN_TO=...
STORAGE_BOX=...
STORAGE_BOX_USER=...
STORAGE_BOX_PASS=...
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

  backups:
    build:
      context: .
      dockerfile: Dockerfile-backups
    init: yes
    privileged: yes
    environment:
      DISABLE_BACKUPS: $DISABLE_BACKUPS
      MAILGUN_KEY: $MAILGUN_KEY
      MAILGUN_DOMAIN: $MAILGUN_DOMAIN
      MAILGUN_FROM: $MAILGUN_FROM
      MAILGUN_TO: $MAILGUN_TO
      STORAGE_BOX: $STORAGE_BOX
      STORAGE_BOX_USER: $STORAGE_BOX_USER
      STORAGE_BOX_PASS: $STORAGE_BOX_PASS
    volumes:
      - ./host-keys:/host-keys
      - ./id_rsa:/id_rsa
      - ./authorized_keys:/authorized_keys
      - ./known_hosts-backups:/known_hosts

volumes:
  db:
```

`Dockerfile-db`:

```dockerfile
FROM postgres:12-alpine3.15
COPY postgresql.conf db.sh ./
COPY db-init.sh /docker-entrypoint-initdb.d
COPY pgbackrest-db.conf /etc/pgbackrest/pgbackrest.conf
RUN set -x && apk add --no-cache pgbackrest openssh pwgen \
    && pg_versions uninstall \
    && set +x && echo "postgres:`pwgen -1`" | chpasswd && set -x
CMD ["./db.sh"]
```

`db-init.sh`:

```sh
cp postgresql.conf /var/lib/postgresql/data
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
FROM alpine:3.15 as slicd
RUN set -x && apk add --no-cache build-base curl \
    && curl https://skarnet.org/software/skalibs/skalibs-2.3.10.0.tar.gz -o skalibs-2.3.10.0.tar.gz \
    && tar xf skalibs-2.3.10.0.tar.gz \
    && cd skalibs-2.3.10.0 \
    && ./configure \
    && make install \
    && cd .. \
    && curl https://jjacky.com/slicd/slicd-0.2.0.tar.gz -o slicd-0.2.0.tar.gz \
    && tar xf slicd-0.2.0.tar.gz \
    && cd slicd-0.2.0 \
    && ./configure \
    && make install

FROM alpine:3.15
COPY backups.sh ./
COPY pgbackrest-backups.conf /etc/pgbackrest/pgbackrest.conf
COPY --from=slicd /bin/slicd-* /bin/setuid /bin/miniexec /bin/
COPY crontab back-up.sh ./
RUN set -x && apk add --no-cache pgbackrest openssh cifs-utils \
        curl wait4ports pwgen \
    && set +x && echo "root:`pwgen -1`" | chpasswd && set -x \
    && slicd-parser -s crontab -o crontab.bin
CMD ["./backups.sh"]
```

`backups.sh`:

```sh
#!/bin/sh -eux
echo "username=$STORAGE_BOX_USER" > /backup-creds.txt
set +x; echo "password=$STORAGE_BOX_PASS" >> /backup-creds.txt; set -x
mount.cifs -o cred=/backup-creds.txt,file_mode=0600,dir_mode=0700 "$STORAGE_BOX" /mnt
cp host-keys/* /etc/ssh
mkdir -p ~/.ssh
cp id_rsa authorized_keys known_hosts ~/.ssh
/usr/sbin/sshd
if ! [ -e /mnt/pgbackrest ]; then
    wait4ports tcp://db:5432
    pgbackrest --stanza=db --log-level-console info stanza-create
fi
if [ "${DISABLE_BACKUPS-}" ]; then
    exec sleep infinity
else
    exec sh -c 'slicd-sched crontab.bin | slicd-exec -- setuid %u sh -c'
fi
```

`crontab`:

```sh
* * * * * root ./back-up.sh --type full
```

`back-up.sh`:

```sh
#!/bin/sh -eu
tmp=`mktemp`
on_exit() {
    rm "$tmp"
}
trap on_exit EXIT

e=0
pgbackrest --stanza=db --log-level-console info "$@" backup >"$tmp" 2>&1 || e=$?
cat "$tmp"
if [ "$e" -gt 0 ]; then
    msg=$(printf 'Output:\n\n%s' "`cat "$tmp"`")
    curl -s --user "api:$MAILGUN_KEY" \
        https://api.mailgun.net/v3/"$MAILGUN_DOMAIN"/messages \
        -F from="$MAILGUN_FROM" \
        -F to="$MAILGUN_TO" \
        -F subject='There was an error during backup' \
        -F text="$msg"
fi
exit "$e"
```

`pgbackrest-backups.conf`:

```
[db]
pg1-host=db
pg1-path=/var/lib/postgresql/data

repo1-path=/mnt/pgbackrest
repo1-type=cifs
repo1-retention-full=2
```
