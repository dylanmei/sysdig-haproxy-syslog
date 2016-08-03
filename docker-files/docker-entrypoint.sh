#!/bin/sh

rm -f /var/run/rsyslogd.pid
service rsyslog start
tail -n 0 -f /var/log/haproxy.log &

exec haproxy -f /etc/haproxy/haproxy.cfg
