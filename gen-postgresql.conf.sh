#!/bin/sh -eu
files=`find -path './postgresql.conf*'`
if [ "$files" ]; then
    t=`date +%Y%m%d-%H%M%S`
    mkdir ".bak-$t"
    echo "$files" | xargs -rd\\n mv -t ".bak-$t"
fi

image=`grep '^\s*FROM\s\+postgres' Dockerfile-db | awk '{print $2}'`
c=`docker run --rm -itde POSTGRES_HOST_AUTH_METHOD=trust "$image"`
docker exec "$c" sh -euc '
    { apk add wait4ports
    wait4ports tcp://localhost:5432; } >/dev/null 2>&1
    cat /var/lib/postgresql/data/postgresql.conf' \
    > postgresql.conf.orig
docker stop "$c"

sed -E -e '/.*archive_mode.*/i archive_mode = on' \
    -e "/.*archive_command.*/i archive_command = 'pgbackrest --stanza=db --log-level-console info archive-push %p'" \
    postgresql.conf.orig \
    > postgresql.conf
