This repository contains a couple of examples of using `pgBackRest` under `docker`. This can be used as a `docker` playground, or as a base for your setup.

* [basic](https://github.com/x-yuri/pgbackrest-docker/tree/basic) `pg` in one container, `pgBackRest` repository in the other, communacation over SSH.
  * [slicd](https://github.com/x-yuri/pgbackrest-docker/tree/slicd) Backups are performed automatically by means of a job scheduler (`slicd`).
    * [rsync](https://github.com/x-yuri/pgbackrest-docker/tree/rsync) Backups are mirrored to the other container over SSH.
    * [cifs](https://github.com/x-yuri/pgbackrest-docker/tree/cifs) Backups are stored in the other container, mounted using CIFS.
      * [readdir-fix](https://github.com/x-yuri/pgbackrest-docker/tree/readdir-fix) A workaround to make expire work with CIFS.
  * [standby-inline](https://github.com/x-yuri/pgbackrest-docker/tree/standby-inline) A standby in the same `docker-compose` project.
  * [standby](https://github.com/x-yuri/pgbackrest-docker/tree/standby) A standby in a separate `docker-compose` project.

Encryption is ignored here.

Provide values in the `.env` file:

```sh
MAILGUN_KEY=...
MAILGUN_DOMAIN=...
MAILGUN_FROM=...
MAILGUN_TO=...
STORAGE_BOX=...  # USER@HOST
```

In case you're running SSH on a custom port, add `-e 'ssh -pPORT'` to the `rsync` commands.

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
$ docker-compose exec backups sh -c 'rm -r /var/lib/pgbackrest/*'
$ docker-compose exec backups sh -c 'rsync -a --delete "$STORAGE_BOX":pgbackrest /var/lib'
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
index 8c0695c..534436d 100644
--- a/.env
+++ b/.env
@@ -4,3 +4,4 @@ MAILGUN_KEY=...
 MAILGUN_DOMAIN=...
 MAILGUN_FROM=...
 MAILGUN_TO=...
+STORAGE_BOX=...
```

`docker-compose.yml` (diff):

```diff
diff --git a/docker-compose.yml b/docker-compose.yml
index 25ab1af..be5a4d4 100644
--- a/docker-compose.yml
+++ b/docker-compose.yml
@@ -25,6 +25,7 @@ services:
       MAILGUN_DOMAIN: $MAILGUN_DOMAIN
       MAILGUN_FROM: $MAILGUN_FROM
       MAILGUN_TO: $MAILGUN_TO
+      STORAGE_BOX: $STORAGE_BOX
     volumes:
       - backups:/var/lib/pgbackrest
       - ./host-keys:/host-keys
```

`Dockerfile-backups` (diff):

```diff
diff --git a/Dockerfile-backups b/Dockerfile-backups
index ef00a1d..74701bb 100644
--- a/Dockerfile-backups
+++ b/Dockerfile-backups
@@ -17,7 +17,7 @@ COPY backups.sh ./
 COPY pgbackrest-backups.conf /etc/pgbackrest/pgbackrest.conf
 COPY --from=slicd /bin/slicd-* /bin/setuid /bin/miniexec /bin/
 COPY crontab back-up.sh ./
-RUN set -x && apk add --no-cache pgbackrest openssh curl wait4ports pwgen \
+RUN set -x && apk add --no-cache pgbackrest openssh rsync curl wait4ports pwgen \
     && set +x && echo "root:`pwgen -1`" | chpasswd && set -x \
     && slicd-parser -s crontab -o crontab.bin
 CMD ["./backups.sh"]
```

`back-up.sh` (diff):

```diff
diff --git a/back-up.sh b/back-up.sh
index 1eef995..03404e9 100755
--- a/back-up.sh
+++ b/back-up.sh
@@ -1,20 +1,33 @@
 #!/bin/sh -eu
 tmp=`mktemp`
+tmp2=`mktemp`
 on_exit() {
-    rm "$tmp"
+    rm "$tmp" "$tmp2"
 }
 trap on_exit EXIT
 
-e=0
-pgbackrest --stanza=db --log-level-console info "$@" backup >"$tmp" 2>&1 || e=$?
-cat "$tmp"
-if [ "$e" -gt 0 ]; then
-    msg=$(printf 'Output:\n\n%s' "`cat "$tmp"`")
+mail() {
+    msg=$(printf 'Output:\n\n%s' "`cat "$tmp" "$tmp2"`")
     curl -s --user "api:$MAILGUN_KEY" \
         https://api.mailgun.net/v3/"$MAILGUN_DOMAIN"/messages \
         -F from="$MAILGUN_FROM" \
         -F to="$MAILGUN_TO" \
         -F subject='There was an error during backup' \
         -F text="$msg"
+}
+
+e=0
+pgbackrest --stanza=db --log-level-console info "$@" backup >"$tmp" 2>&1 || e=$?
+cat "$tmp"
+if [ "$e" = 0 ]; then
+    e2=0
+    rsync -a --delete /var/lib/pgbackrest "$STORAGE_BOX": >"$tmp2" 2>&1 || e2=$?
+    cat "$tmp2"
+    if [ "$e2" -gt 0 ]; then
+        mail
+        e=$e2
+    fi
+else
+    mail
 fi
 exit "$e"
```

`known_hosts` (diff):

```diff
diff --git a/known_hosts b/known_hosts
new file mode 100644
index 0000000..f2f6979
--- /dev/null
+++ b/known_hosts
@@ -0,0 +1 @@
+example.com ssh-rsa ...
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
    environment:
      DISABLE_BACKUPS: $DISABLE_BACKUPS
      MAILGUN_KEY: $MAILGUN_KEY
      MAILGUN_DOMAIN: $MAILGUN_DOMAIN
      MAILGUN_FROM: $MAILGUN_FROM
      MAILGUN_TO: $MAILGUN_TO
      STORAGE_BOX: $STORAGE_BOX
    volumes:
      - backups:/var/lib/pgbackrest
      - ./host-keys:/host-keys
      - ./id_rsa:/id_rsa
      - ./authorized_keys:/authorized_keys
      - ./known_hosts-backups:/known_hosts

volumes:
  db:
  backups:
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
RUN set -x && apk add --no-cache pgbackrest openssh rsync curl wait4ports pwgen \
    && set +x && echo "root:`pwgen -1`" | chpasswd && set -x \
    && slicd-parser -s crontab -o crontab.bin
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
tmp2=`mktemp`
on_exit() {
    rm "$tmp" "$tmp2"
}
trap on_exit EXIT

mail() {
    msg=$(printf 'Output:\n\n%s' "`cat "$tmp" "$tmp2"`")
    curl -s --user "api:$MAILGUN_KEY" \
        https://api.mailgun.net/v3/"$MAILGUN_DOMAIN"/messages \
        -F from="$MAILGUN_FROM" \
        -F to="$MAILGUN_TO" \
        -F subject='There was an error during backup' \
        -F text="$msg"
}

e=0
pgbackrest --stanza=db --log-level-console info "$@" backup >"$tmp" 2>&1 || e=$?
cat "$tmp"
if [ "$e" = 0 ]; then
    e2=0
    rsync -a --delete /var/lib/pgbackrest "$STORAGE_BOX": >"$tmp2" 2>&1 || e2=$?
    cat "$tmp2"
    if [ "$e2" -gt 0 ]; then
        mail
        e=$e2
    fi
else
    mail
fi
exit "$e"
```

`pgbackrest-backups.conf`:

```
[db]
pg1-host=db
pg1-path=/var/lib/postgresql/data

repo1-path=/var/lib/pgbackrest
repo1-retention-full=2
```

`known_hosts`:

```
example.com ssh-rsa ...
```
