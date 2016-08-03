FROM haproxy:latest

RUN apt-get update \
 && apt-get install -y --no-install-recommends procps rsyslog \
 && sed -i 's/$ActionFileDefaultTemplate RSYSLOG_TraditionalFileFormat/#$ActionFileDefaultTemplate RSYSLOG_TraditionalFileFormat/g' /etc/rsyslog.conf \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/haproxy \
 && touch /var/log/haproxy.log

EXPOSE 80 3000

ADD haproxy.rsyslog /etc/rsyslog.d/haproxy.conf
COPY docker-entrypoint.sh /
