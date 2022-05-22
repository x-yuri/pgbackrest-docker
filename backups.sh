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
