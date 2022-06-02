FROM postgres:12-alpine3.15
ARG DB_IP
ARG DB_PORT
ARG BACKUPS_IP
ARG BACKUPS_PORT
COPY postgresql.conf standby/standby.sh standby/pgbackrest.conf.tpl ./
COPY standby/db-init.sh /docker-entrypoint-initdb.d
RUN set -x && apk add --no-cache pgbackrest openssh gettext pwgen \
    && pg_versions uninstall \
    && set +x && echo "postgres:`pwgen -1`" | chpasswd && set -x \
    && envsubst '$DB_IP $DB_PORT $BACKUPS_IP $BACKUPS_PORT' \
        <pgbackrest.conf.tpl \
        >/etc/pgbackrest/pgbackrest.conf
CMD ["./standby.sh"]
