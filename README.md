Provide values in the `.env` file:

```sh
MAILGUN_KEY=...
MAILGUN_DOMAIN=...
MAILGUN_FROM=...
MAILGUN_TO=...
```

```

Wait for a backup.

```
Wait for a backup.

$ DISABLE_BACKUPS=1 DONT_START_DB=1 docker-compose up
$ DISABLE_BACKUPS=1 docker-compose up
$ DISABLE_BACKUPS=1 DONT_START_DB=1 docker-compose up
$ DISABLE_BACKUPS=1 docker-compose up
`.env` (diff):

```diff
diff --git a/.env b/.env
index 93fb278..8c0695c 100644
--- a/.env
+++ b/.env
@@ -1 +1,6 @@
 DONT_START_DB=
+DISABLE_BACKUPS=
+MAILGUN_KEY=...
+MAILGUN_DOMAIN=...
+MAILGUN_FROM=...
+MAILGUN_TO=...
```

`docker-compose.yml` (diff):

```diff
diff --git a/docker-compose.yml b/docker-compose.yml
index b8b69dc..25ab1af 100644
--- a/docker-compose.yml
+++ b/docker-compose.yml
@@ -19,6 +19,12 @@ services:
       context: .
       dockerfile: Dockerfile-backups
     init: yes
+    environment:
+      DISABLE_BACKUPS: $DISABLE_BACKUPS
+      MAILGUN_KEY: $MAILGUN_KEY
+      MAILGUN_DOMAIN: $MAILGUN_DOMAIN
+      MAILGUN_FROM: $MAILGUN_FROM
+      MAILGUN_TO: $MAILGUN_TO
     volumes:
       - backups:/var/lib/pgbackrest
       - ./host-keys:/host-keys
```

`Dockerfile-backups` (diff):

```diff
diff --git a/Dockerfile-backups b/Dockerfile-backups
index 1460d61..ef00a1d 100644
--- a/Dockerfile-backups
+++ b/Dockerfile-backups
@@ -1,6 +1,23 @@
+FROM alpine:3.15 as slicd
+RUN set -x && apk add --no-cache build-base curl \
+    && curl https://skarnet.org/software/skalibs/skalibs-2.3.10.0.tar.gz -o skalibs-2.3.10.0.tar.gz \
+    && tar xf skalibs-2.3.10.0.tar.gz \
+    && cd skalibs-2.3.10.0 \
+    && ./configure \
+    && make install \
+    && cd .. \
+    && curl https://jjacky.com/slicd/slicd-0.2.0.tar.gz -o slicd-0.2.0.tar.gz \
+    && tar xf slicd-0.2.0.tar.gz \
+    && cd slicd-0.2.0 \
+    && ./configure \
+    && make install
+
 FROM alpine:3.15
 COPY backups.sh ./
 COPY pgbackrest-backups.conf /etc/pgbackrest/pgbackrest.conf
-RUN set -x && apk add --no-cache pgbackrest openssh wait4ports pwgen \
-    && set +x && echo "root:`pwgen -1`" | chpasswd && set -x
+COPY --from=slicd /bin/slicd-* /bin/setuid /bin/miniexec /bin/
+COPY crontab back-up.sh ./
+RUN set -x && apk add --no-cache pgbackrest openssh curl wait4ports pwgen \
+    && set +x && echo "root:`pwgen -1`" | chpasswd && set -x \
+    && slicd-parser -s crontab -o crontab.bin
 CMD ["./backups.sh"]
```

`backups.sh` (diff):

```diff
diff --git a/backups.sh b/backups.sh
index f2a9590..e3d544d 100755
--- a/backups.sh
+++ b/backups.sh
@@ -7,4 +7,8 @@ if [ "`ls /var/lib/pgbackrest | wc -l`" = 0 ]; then
     wait4ports tcp://db:5432
     pgbackrest --stanza=db --log-level-console info stanza-create
 fi
-exec sleep infinity
+if [ "${DISABLE_BACKUPS-}" ]; then
+    exec sleep infinity
+else
+    exec sh -c 'slicd-sched crontab.bin | slicd-exec -- setuid %u sh -c'
+fi
```

`crontab` (diff):

```diff
diff --git a/crontab b/crontab
new file mode 100644
index 0000000..74f666e
--- /dev/null
+++ b/crontab
@@ -0,0 +1 @@
+* * * * * root ./back-up.sh --type full
```

`back-up.sh` (diff):

```diff
diff --git a/back-up.sh b/back-up.sh
new file mode 100755
index 0000000..1eef995
--- /dev/null
+++ b/back-up.sh
@@ -0,0 +1,20 @@
+#!/bin/sh -eu
+tmp=`mktemp`
+on_exit() {
+    rm "$tmp"
+}
+trap on_exit EXIT
+
+e=0
+pgbackrest --stanza=db --log-level-console info "$@" backup >"$tmp" 2>&1 || e=$?
+cat "$tmp"
+if [ "$e" -gt 0 ]; then
+    msg=$(printf 'Output:\n\n%s' "`cat "$tmp"`")
+    curl -s --user "api:$MAILGUN_KEY" \
+        https://api.mailgun.net/v3/"$MAILGUN_DOMAIN"/messages \
+        -F from="$MAILGUN_FROM" \
+        -F to="$MAILGUN_TO" \
+        -F subject='There was an error during backup' \
+        -F text="$msg"
+fi
+exit "$e"
```

DISABLE_BACKUPS=
MAILGUN_KEY=...
MAILGUN_DOMAIN=...
MAILGUN_FROM=...
MAILGUN_TO=...
    environment:
      DISABLE_BACKUPS: $DISABLE_BACKUPS
      MAILGUN_KEY: $MAILGUN_KEY
      MAILGUN_DOMAIN: $MAILGUN_DOMAIN
      MAILGUN_FROM: $MAILGUN_FROM
      MAILGUN_TO: $MAILGUN_TO
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

COPY --from=slicd /bin/slicd-* /bin/setuid /bin/miniexec /bin/
COPY crontab back-up.sh ./
RUN set -x && apk add --no-cache pgbackrest openssh curl wait4ports pwgen \
    && set +x && echo "root:`pwgen -1`" | chpasswd && set -x \
    && slicd-parser -s crontab -o crontab.bin
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