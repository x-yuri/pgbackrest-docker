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
