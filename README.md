This repository contains a couple of examples of using `pgBackRest` under `docker`. This can be used as a `docker` playground, or as a base for your setup.

* [basic](https://github.com/x-yuri/pgbackrest-docker/tree/basic) `pg` in one container, `pgBackRest` repository in the other, communacation over SSH.
  * [slicd](https://github.com/x-yuri/pgbackrest-docker/tree/slicd) Backups are performed automatically by means of a job scheduler (`slicd`).
    * [rsync](https://github.com/x-yuri/pgbackrest-docker/tree/rsync) Backups are mirrored to the other container over SSH.
    * [cifs](https://github.com/x-yuri/pgbackrest-docker/tree/cifs) Backups are stored in the other container, mounted using CIFS.
      * [readdir-fix](https://github.com/x-yuri/pgbackrest-docker/tree/readdir-fix) A workaround to make expire work with CIFS.
  * [standby-inline](https://github.com/x-yuri/pgbackrest-docker/tree/standby-inline) A standby in the same `docker-compose` project.
  * [standby](https://github.com/x-yuri/pgbackrest-docker/tree/standby) A standby in a separate `docker-compose` project.

Encryption is ignored here.

Provide values in `.env`:

```sh
MAILGUN_KEY=...
MAILGUN_DOMAIN=...
MAILGUN_FROM=...
MAILGUN_TO=...
STORAGE_BOX=...  # //SERVER/SHARE
STORAGE_BOX_USER=...
STORAGE_BOX_PASS=...
```

There are [issues][a] with using CIFS under [Alpine Linux][b]:

[a]: https://github.com/pgbackrest/pgbackrest/issues/1754#issuecomment-1133805373
[b]: https://gist.github.com/x-yuri/aa6db295cd56f757537f756bc390b1df

```
2022-05-27 19:29:00.003 P00   INFO: backup command begin 2.36: --exec-id=64-57aba533 --log-level-console=info --pg1-host=db --pg1-path=/var/lib/postgresql/data --repo1-path=/mnt/pgbackrest --repo1-retention-full=2 --repo1-type=cifs --stanza=db --type=full
2022-05-27 19:29:00.820 P00   INFO: execute non-exclusive pg_start_backup(): backup begins after the next regular checkpoint completes
2022-05-27 19:29:01.223 P00   INFO: backup start archive = 000000010000000000000006, lsn = 0/6000028
2022-05-27 19:29:32.283 P00   INFO: execute non-exclusive pg_stop_backup() and wait for all WAL segments to archive
2022-05-27 19:29:32.484 P00   INFO: backup stop archive = 000000010000000000000006, lsn = 0/6000138
2022-05-27 19:29:32.515 P00   INFO: check archive for segment(s) 000000010000000000000006:000000010000000000000006
2022-05-27 19:29:32.771 P00   INFO: new backup label = 20220527-192900F
2022-05-27 19:29:33.011 P00   INFO: full backup size = 23.6MB, file total = 979
2022-05-27 19:29:33.011 P00   INFO: backup command end: completed successfully (33008ms)
2022-05-27 19:29:33.011 P00   INFO: expire command begin 2.36: --exec-id=64-57aba533 --log-level-console=info --repo1-path=/mnt/pgbackrest --repo1-retention-full=2 --repo1-type=cifs --stanza=db
2022-05-27 19:29:33.021 P00   INFO: repo1: expire full backup 20220527-192645F
2022-05-27 19:29:33.086 P00   INFO: repo1: remove expired backup 20220527-192645F
ERROR: [061]: repo1: unable to remove path '/mnt/pgbackrest/backup/db/20220527-192645F/pg_data/base/13457': [39] Directory not empty
ERROR: [104]: expire command encountered 1 error(s), check the log file for details
2022-05-27 19:29:33.434 P00   INFO: expire command end: aborted with exception [104]
```

See the [`readdir-fix`](https://github.com/x-yuri/pgbackrest-docker/tree/readdir-fix) branch.

```
$ ./gen-keys.sh
$ ./gen-postgresql.conf.sh
$ DISABLE_BACKUPS=1 docker-compose up
$ docker-compose exec backups pgbackrest --stanza=db --log-level-console info --type full backup
$ docker-compose exec backups pgbackrest --stanza=db --log-level-console info --type full backup
$ docker-compose exec backups pgbackrest --stanza=db --log-level-console info --type full backup
```
