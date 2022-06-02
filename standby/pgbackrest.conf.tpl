[db]
pg1-path=/var/lib/postgresql/data
recovery-option=primary_conninfo=host=$DB_IP port=$DB_PORT user=replicator

repo1-host=$BACKUPS_IP
repo1-host-port=$BACKUPS_PORT
repo1-host-user=root
