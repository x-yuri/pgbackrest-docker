#!/bin/sh -eu
files=`find -path './postgresql.conf*' -o -path './pg_hba.conf*'`
if [ "$files" ]; then
    t=`date +%Y%m%d-%H%M%S`
    mkdir ".bak-$t"
    echo "$files" | xargs -rd\\n mv -t ".bak-$t"
fi

image=`grep '^\s*FROM\s\+postgres' Dockerfile-db | awk '{print $2}'`
c=`docker run --rm -itde POSTGRES_HOST_AUTH_METHOD=trust "$image"`
docker exec "$c" sh -euc '
    { apk add wait4ports
    wait4ports tcp://localhost:5432
    cd ~postgres/data
    tar czf pg.tar.gz postgresql.conf \
                      pg_hba.conf; } >/dev/null 2>&1
    cat pg.tar.gz' \
    > pg.tar.gz
docker stop "$c"
tar xf pg.tar.gz
rm pg.tar.gz

mv postgresql.conf postgresql.conf.orig
sed -E -e '/.*archive_mode.*/i archive_mode = on' \
    -e "/.*archive_command.*/i archive_command = 'pgbackrest --stanza=db --log-level-console info archive-push %p'" \
    postgresql.conf.orig \
    > postgresql.conf

cp pg_hba.conf pg_hba.conf.orig
echo 'host  replication  replicator  10.0.0.1/32  trust' \
    >> pg_hba.conf
chmod a+r pg_hba.conf
