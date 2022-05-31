#!/bin/sh -eux
cp host-keys/* /etc/ssh
mkdir -p ~postgres/.ssh
cp id_rsa authorized_keys known_hosts ~postgres/.ssh
chown -R postgres: ~postgres/.ssh
/usr/sbin/sshd
wait4ports tcp://"`echo "$STORAGE_BOX" | cut -d/ -f3`":139
if [ "${DONT_START_DB-}" ]; then
    exec sleep infinity
else
    exec docker-entrypoint.sh postgres
fi
