sysdig-haproxy-syslog
---------------------

A [Sysdig](http://www.sysdig.org) chisel to tail HAProxy logs

### demo steps

Build the HAProxy image, run the web components

```
% docker-compose build
% docker-compose up
```

Run the chisel, make a request, and stop the chisel

```
% export SYSDIG_CHISEL_DIR=$PWD
% sysdig -c haproxy-syslog "haproxy haproxy 1024 stdout"
% curl http://localhost:8080
```

Your output should be similar:

```
^Csyslog.events.line.seen tags=[] value=2
syslog.events.line.maxlen tags=[] value=162
syslog.frontend.connected tags=[haproxy.frontend:http-in] value=0
syslog.global.connected tags=[] value=0
syslog.server.connected tags=[haproxy.frontend:http-in,haproxy.backend:webapp-http,haproxy.server:webapp] value=0
syslog.backend.connected tags=[haproxy.frontend:http-in,haproxy.backend:webapp-http] value=0
```
