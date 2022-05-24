#!/bin/sh -eu
tmp=`mktemp`
tmp2=`mktemp`
on_exit() {
    rm "$tmp" "$tmp2"
}
trap on_exit EXIT

mail() {
    msg=$(printf 'Output:\n\n%s' "`cat "$tmp" "$tmp2"`")
    curl -s --user "api:$MAILGUN_KEY" \
        https://api.mailgun.net/v3/"$MAILGUN_DOMAIN"/messages \
        -F from="$MAILGUN_FROM" \
        -F to="$MAILGUN_TO" \
        -F subject='There was an error during backup' \
        -F text="$msg"
}

e=0
pgbackrest --stanza=db --log-level-console info "$@" backup >"$tmp" 2>&1 || e=$?
cat "$tmp"
if [ "$e" = 0 ]; then
    e2=0
    rsync -a --delete /var/lib/pgbackrest "$STORAGE_BOX": >"$tmp2" 2>&1 || e2=$?
    cat "$tmp2"
    if [ "$e2" -gt 0 ]; then
        mail
        e=$e2
    fi
else
    mail
fi
exit "$e"
