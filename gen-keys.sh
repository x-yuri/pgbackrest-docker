#!/bin/sh -eu
files=`find -maxdepth 1 -path './id_rsa' \
                     -o -path './authorized_keys*' \
                     -o -path './host-keys*' \
                     -o -path './known_hosts*'`
if [ "$files" ]; then
    t=`date +%Y%m%d-%H%M%S`
    mkdir ".bak-$t"
    echo "$files" | xargs -rd\\n mv -t ".bak-$t"
fi
docker run --rm alpine:3.15 sh -euc '
    { apk add openssh-server

    yes "" | ssh-keygen -N ""
    cd ~/.ssh
    cp id_rsa.pub authorized_keys
    prefix="no-agent-forwarding,no-X11-forwarding,no-port-forwarding,command=\"/usr/bin/pgbackrest \${SSH_ORIGINAL_COMMAND#* }\""
    sed -Ei "s@^@$prefix @" authorized_keys
    cp id_rsa.pub authorized_keys-backup-storage
    prefix="no-agent-forwarding,no-X11-forwarding,no-port-forwarding,command=\"/usr/bin/rsync \${SSH_ORIGINAL_COMMAND#* }\""
    sed -Ei "s@^@$prefix @" authorized_keys-backup-storage

    mkdir host-keys
    ssh-keygen -A
    cp /etc/ssh/ssh_host* host-keys
    rm /etc/ssh/ssh_host*
    mkdir host-keys-backup-storage
    ssh-keygen -A
    cp /etc/ssh/ssh_host* host-keys-backup-storage

    awk -v host=backups "{print host, \$1, \$2}" \
        host-keys/ssh_host_ecdsa_key.pub \
        host-keys/ssh_host_ed25519_key.pub \
        host-keys/ssh_host_rsa_key.pub \
        > known_hosts-db

    awk -v host=db "{print host, \$1, \$2}" \
        host-keys/ssh_host_ecdsa_key.pub \
        host-keys/ssh_host_ed25519_key.pub \
        host-keys/ssh_host_rsa_key.pub \
        > known_hosts-backups
    awk -v host=backup-storage "{print host, \$1, \$2}" \
        host-keys-backup-storage/ssh_host_ecdsa_key.pub \
        host-keys-backup-storage/ssh_host_ed25519_key.pub \
        host-keys-backup-storage/ssh_host_rsa_key.pub \
        >> known_hosts-backups

    tar czf keys.tar.gz id_rsa authorized_keys* host-keys* known_hosts*; } >/dev/null
    cat keys.tar.gz
' > keys.tar.gz
tar xf keys.tar.gz
rm keys.tar.gz
