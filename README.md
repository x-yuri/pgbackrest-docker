This repository contains a couple of examples of using `pgBackRest` under `docker`. This can be used as a `docker` playground, or as a base for your setup.

* [basic](https://github.com/x-yuri/pgbackrest-docker/tree/basic) `pg` in one container, `pgBackRest` repository in the other, communacation over SSH.
  * [slicd](https://github.com/x-yuri/pgbackrest-docker/tree/slicd) Backups are performed automatically by means of a job scheduler (`slicd`).
    * [rsync](https://github.com/x-yuri/pgbackrest-docker/tree/rsync) Backups are mirrored to the other container over SSH.
    * [cifs](https://github.com/x-yuri/pgbackrest-docker/tree/cifs) Backups are stored in the other container, mounted using CIFS.
      * [readdir-fix](https://github.com/x-yuri/pgbackrest-docker/tree/readdir-fix) A workaround to make expire work with CIFS.
  * [standby-inline](https://github.com/x-yuri/pgbackrest-docker/tree/standby-inline) A standby in the same `docker-compose` project.
  * [standby](https://github.com/x-yuri/pgbackrest-docker/tree/standby) A standby in a separate `docker-compose` project.

Encryption is ignored here.

```
$ ./gen-keys.sh
$ ./gen-postgresql.conf.sh
$ docker-compose up
$ docker-compose exec backups pgbackrest --stanza=db --log-level-console info check
$ docker-compose exec -u postgres db pgbackrest --stanza=db --log-level-console info check
$ docker-compose exec backups pgbackrest --stanza=db --log-level-console info backup
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
$ docker-compose exec backups pgbackrest --stanza=db --log-level-console info backup
```

Restore:

```
$ DONT_START_DB=1 docker-compose up
$ docker-compose exec db sh -c 'rm -r /var/lib/postgresql/data/*'
$ docker-compose exec -u postgres db pgbackrest --stanza=db --log-level-console info restore
$ docker-compose up
$ docker-compose exec -u postgres db psql -U postgres -c 'select * from t'
 f 
---
 1
 2
(2 rows)
```

PITR:

```
$ DONT_START_DB=1 docker-compose up
$ docker-compose exec db sh -c 'rm -r /var/lib/postgresql/data/*'
$ docker-compose exec -u postgres db pgbackrest --stanza=db --log-level-console info --type time --target '2022-05-23 03:55:24.782817+00' --target-action promote restore
$ docker-compose up
$ docker-compose exec -u postgres db psql -U postgres -c 'select * from t'
 f 
---
 1
(1 row)
```

`.env`:

```sh
DONT_START_DB=
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
    volumes:
      - backups:/var/lib/pgbackrest
      - ./host-keys:/host-keys
      - ./id_rsa:/id_rsa
      - ./authorized_keys:/authorized_keys
      - ./known_hosts-backups:/known_hosts

volumes:
  db:
  backups:
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
FROM alpine:3.15
COPY backups.sh ./
COPY pgbackrest-backups.conf /etc/pgbackrest/pgbackrest.conf
RUN set -x && apk add --no-cache pgbackrest openssh wait4ports pwgen \
    && set +x && echo "root:`pwgen -1`" | chpasswd && set -x
CMD ["./backups.sh"]
```

`backups.sh`:

```sh
#!/bin/sh -eux
cp host-keys/* /etc/ssh
mkdir -p ~/.ssh
cp id_rsa authorized_keys known_hosts ~/.ssh
/usr/sbin/sshd
if [ "`ls /var/lib/pgbackrest | wc -l`" = 0 ]; then
    wait4ports tcp://db:5432
    pgbackrest --stanza=db --log-level-console info stanza-create
fi
exec sleep infinity
```

`pgbackrest-backups.conf`:

```
[db]
pg1-host=db
pg1-path=/var/lib/postgresql/data

repo1-path=/var/lib/pgbackrest
repo1-retention-full=2
```
