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

Retention [might fail][a] if it needs to delete a big directory (a directory with a lot of files).

[a]: https://gist.github.com/x-yuri/aa6db295cd56f757537f756bc390b1df

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

`Dockerfile-backups` (diff):

```diff
diff --git a/Dockerfile-backups b/Dockerfile-backups
index dc72446..c56ca24 100644
--- a/Dockerfile-backups
+++ b/Dockerfile-backups
@@ -12,11 +12,24 @@ RUN set -x && apk add --no-cache build-base curl \
     && ./configure \
     && make install
 
+FROM alpine:3.16 as musl
+RUN set -x && apk add build-base curl gpg gnupg-dirmngr gpg-agent \
+    && curl https://musl.libc.org/releases/musl-1.2.2.tar.gz -o musl-1.2.2.tar.gz \
+    && curl https://musl.libc.org/releases/musl-1.2.2.tar.gz.asc -o musl-1.2.2.tar.gz.asc \
+    && gpg --recv-key 836489290BB6B70F99FFDA0556BCDB593020450F \
+    && gpg --verify musl-1.2.2.tar.gz.asc musl-1.2.2.tar.gz \
+    && tar xf musl-1.2.2.tar.gz \
+    && cd musl-1.2.2 \
+    && sed -i 's/char buf\[2048\]/char buf[8192]/' src/dirent/__dirent.h \
+    && ./configure \
+    && make install
+
 FROM alpine:3.15
 COPY backups.sh ./
 COPY pgbackrest-backups.conf /etc/pgbackrest/pgbackrest.conf
 COPY --from=slicd /bin/slicd-* /bin/setuid /bin/miniexec /bin/
 COPY crontab back-up.sh ./
+COPY --from=musl /lib/ld-musl-x86_64.so.1 /lib/ld-musl-x86_64.so.1
 RUN set -x && apk add --no-cache pgbackrest openssh cifs-utils \
         curl wait4ports pwgen \
     && set +x && echo "root:`pwgen -1`" | chpasswd && set -x \
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

FROM alpine:3.16 as musl
RUN set -x && apk add build-base curl gpg gnupg-dirmngr gpg-agent \
    && curl https://musl.libc.org/releases/musl-1.2.2.tar.gz -o musl-1.2.2.tar.gz \
    && curl https://musl.libc.org/releases/musl-1.2.2.tar.gz.asc -o musl-1.2.2.tar.gz.asc \
    && gpg --recv-key 836489290BB6B70F99FFDA0556BCDB593020450F \
    && gpg --verify musl-1.2.2.tar.gz.asc musl-1.2.2.tar.gz \
    && tar xf musl-1.2.2.tar.gz \
    && cd musl-1.2.2 \
    && sed -i 's/char buf\[2048\]/char buf[8192]/' src/dirent/__dirent.h \
    && ./configure \
    && make install

FROM alpine:3.15
COPY backups.sh ./
COPY pgbackrest-backups.conf /etc/pgbackrest/pgbackrest.conf
COPY --from=slicd /bin/slicd-* /bin/setuid /bin/miniexec /bin/
COPY crontab back-up.sh ./
COPY --from=musl /lib/ld-musl-x86_64.so.1 /lib/ld-musl-x86_64.so.1
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
