#!/bin/sh -eux
cp host-keys/* /etc/ssh
mkdir -p ~/.ssh
cp authorized_keys ~/.ssh
/usr/sbin/sshd -D
