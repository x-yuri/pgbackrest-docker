#!/bin/sh -eu
tmp=`mktemp`
on_exit() {
    rm "$tmp"
}
trap on_exit EXIT

e=0
pgbackrest --stanza=db --log-level-console info "$@" backup >"$tmp" 2>&1 || e=$?
cat "$tmp"
if [ "$e" -gt 0 ]; then
    msg=$(printf 'Output:\n\n%s' "`cat "$tmp"`")
    curl -s --user "api:$MAILGUN_KEY" \
        https://api.mailgun.net/v3/"$MAILGUN_DOMAIN"/messages \
        -F from="$MAILGUN_FROM" \
        -F to="$MAILGUN_TO" \
        -F subject='There was an error during backup' \
        -F text="$msg"
fi
exit "$e"
