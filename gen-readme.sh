#!/bin/sh -eu

file_order='.env
docker-compose.yml
Dockerfile-db
db-init.sh
db.sh
pgbackrest-db.conf
pgbackrest-standby.conf
Dockerfile-backups
backups.sh
crontab
back-up.sh
pgbackrest-backups.conf
standby/.env
standby/docker-compose.yml
standby/Dockerfile
standby/db-init.sh
standby/standby.sh
standby/pgbackrest.conf.tpl'

files() {
    local files=$1
    files=`echo "$file_order" | while IFS= read -r f; do
        grep -Fx "$f" <(echo "$files") || true
    done
    echo "$files" | while IFS= read -r f; do
        if ! grep -Fx "$f" <(echo "$file_order") >/dev/null; then
            echo "$f"
        fi
    done`
    files=`echo "$files" | grep -Fxv -e README.md -e gen-keys.sh -e gen-postgresql.conf.sh -e gen-pg-stuff.sh -e gen-readme.sh`
    echo "$files"
}

if git rev-parse HEAD~ >/dev/null 2>&1; then
    files=$(files "`git show --name-only --pretty=`")
    echo "$files" | while IFS= read -r f; do
        echo
        echo '`'"$f"'`'" (diff):"
        echo
        echo '```diff'
        git --no-pager diff --no-color HEAD~ "$f"
        echo '```'
    done
fi

files=$(files "`git ls-files`")
echo "$files" | while IFS= read -r f; do
    case "$f" in
    *.conf) ft=;;
    *.sh) ft=sh;;
    *.tpl) ft=;;
    *.yaml) ft=yaml;;
    *.yml) ft=yaml;;
    .env) ft=sh;;
    Dockerfile*) ft=dockerfile;;
    */Dockerfile*) ft=dockerfile;;
    esac
    echo
    echo '`'"$f"'`'":"
    echo
    echo '```'"$ft"
    cat "$f"
    echo '```'
done
