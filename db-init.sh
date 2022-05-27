cp postgresql.conf pg_hba.conf /var/lib/postgresql/data
if [ "$ROLE" = primary ]; then
    createuser replicator --replication
fi
