description = "HAProxy Syslog tailer";
short_description = "HAProxy Syslog tailer";
category = "Logs";

-- Argument list
args = {
  {
    name = "log-tag",
    description = "Value of the tag field in the syslog header; this is usually 'haproxy'",
    argtype = "string",
    optional = true,
  }, {
    name = "namespace",
    description = "Namespace of the HAProxy log metrics",
    argtype = "string",
    optional = true,
  }, {
    name = "snaplen",
    description = "By default, the chisel analyzes the first 1024 bytes of each log-line",
    argtype = "int",
    optional = true,
  }, {
    name = "output",
    description = "By default, the chisel pushes metrics to 'statsd'; otherwise write to 'stdout'",
    argtype = "string",
    optional = true,
  }
}

-- Imports and globals
require "common"
local logtag = "haproxy"
local namespace = "haproxy"
local snaplen = 1024
local output = "statsd"

local fields = {
  ["evt.buffer"] = nil,
  ["evt.buflen"] = nil,
}

local counters = {
  ["syslog.events.line.seen"]       = {},
  ["syslog.events.parse.succeeded"] = {},
  ["syslog.events.parse.failed"]    = {},
}

local gauges = {
  ["syslog.events.line.maxlen"] = {},
}

local logpattern = "([%a%d-_]+) " ..               -- frontend_name
    "([%a%d-_]+)/([%a%d-_]+) " ..                  -- backend_name / server_name
    "(-?%d+)/(-?%d+)/(-?%d+)/(-?%d+)/(-?%d+) " ..  -- Tq / Tw / Tc / Tr / Tt*
    "(%d+) " ..                                    -- status_code
    "%+?(%d+) " ..                                 -- bytes_read
    "%S+ " ..                                      -- captured_request_cookie
    "%S+ " ..                                      -- captured_response_cookie
    "%S+ " ..                                      -- termination_state
    "(%d+)/(%d+)/(%d+)/(%d+)/(%+?)(%d+) " ..       -- actconn / feconn / beconn / srv_conn / retries*
    "(%d+)/(%d+) "                                 -- srv_queue / backend_queue

function on_set_arg(name, val)
  print(name .. "=" .. val)
  if name == "log-tag" then
    logtag = val
  end
  if name == "namespace" then
    program = val
  end
  if name == "snaplen" then
    snaplen = val
  end
  if name == "output" then
    output = val
  end

  return true
end

-- Initialization callback. Same as in regular chisels.
function on_init()
  chisel.set_interval_s(10)
  chisel.set_filter(string.format([[
    evt.is_syslog=true
    and evt.dir=<
    and evt.failed=false
    and proc.name=haproxy
    and evt.buffer contains %s]],
    logtag))

  -- Request the fields that we will need values from
  fields["evt.buffer"] = chisel.request_field("evt.buffer")
  fields["evt.buflen"] = chisel.request_field("evt.buflen")
  sysdig.set_snaplen(snaplen)

  return true
end

function on_capture_start()
  counter{name="syslog.events.line.seen", value=0}
  gauge{name="syslog.events.line.maxlen", value=0}
  counter{name="syslog.events.parse.succeeded", value=0}
  counter{name="syslog.events.parse.failed", value=0}
  if output == "stdout" then
    metric_writer = write_metric_to_stdout
  else
    metric_writer = write_metric_to_statsd
  end
  return true
end

-- Event parsing callback. Same as in regular chisels.
function on_event()
  counter{name="syslog.events.line.seen"}

  buflen = evt.field(fields["evt.buflen"])
  if buflen > gauges["syslog.events.line.maxlen"][1] then
    gauge{name="syslog.events.line.maxlen", value=buflen}
  end

  buffer = evt.field(fields["evt.buffer"])

  if parse(buffer) then
    counter{name="syslog.events.parse.succeeded"}
  else
    counter{name="syslog.events.parse.failed"}
  end

  return true
end

function on_interval()
  if output == "stdout" then
    for _, name in ipairs({"syslog.events.line.seen"}) do
      push_metric(name, counters[name])
    end
  end

  return true
end

-- End of capture callback
function on_capture_end()
  -- gauges
  for name, value in pairs(gauges) do
    push_metric(name, gauges[name])
  end

  -- counters (need to reset counters!)
  -- timers

  return true
end

-- This function is onvoked by the sysdig cloud agent every time it's time to 
-- generate a new sample, which happens once a second.
-- This is where the chisel can add its own metrics to the sample that goes to
-- the sysdig cloud backend, using the push_metric() function.
-- The metrics pushed here will appear as statsd metrics in the sysdig cloud
-- user interface.
function on_end_of_sample()
  -- gauges
  for name, value in pairs(gauges) do
    push_metric(name, gauges[name])
  end

  -- counters (need to reset counters!)
  -- timers

  return true
end

function parse(buffer)
  local first, last = string.find(buffer, logtag .. "%[%d+%]:%s[%d%.:]+%s%[.*%]%s")
  if first then
    local log = string.sub(buffer, last + 1)
    local frontend_name, backend_name, server_name,
      tq, tw, tc, tr, tt,
      status_code,
      bytes_read,
      actconn, feconn, beconn, srv_conn, redispatched, retries,
      srv_queue, backend_queue = string.match(log, logpattern)

    if frontend_name then
      gauge{name="syslog.global.connected", value=actconn}

      gauge{name="syslog.frontend.connected", value=feconn,
        frontend=frontend_name}

      if backend_name then
        gauge{name="syslog.backend.connected", value=beconn,
          frontend=frontend_name, backend=backend_name}

        if server_name then
          gauge{name="syslog.server.connected", value=srv_conn,
            frontend=frontend_name, backend=backend_name, server=server_name}
        end
      end

      return true
    end
  end

  if string.match(buffer, "Connect from %S+ to %S+ %(stats/HTTP%)") then
    return true
  end

  if string.match(buffer, "Proxy %S+ started") then
    return true
  end

  return false
end

function push_metric(name, bag)
  for key, val in pairs(bag) do
    if key == 1 then
      metric_writer(name, {}, val)
    else
      push_metric_with_tags(name, val, {key})
    end
  end
end

function push_metric_with_tags(name, bag, tags)
  for key, val in pairs(bag) do
    if key == 1 then
      metric_writer(name, tags, val)
    else
      table.insert(tags, key)
      push_metric_with_tags(name, val, tags)
    end
  end
end

local tag_labels = {"haproxy.frontend", "haproxy.backend", "haproxy.server"}

function tag_cleaner(value)
  value = string.gsub(value, "[<>]", "")
  return string.lower(value)
end

function write_metric_to_stdout(name, tags, value)
  local list = ""
  for i, tag in ipairs(tags) do
    if i > 1 then list = list .. "," end
    list = list .. tag_labels[i] .. ":" .. tag_cleaner(tag)
  end

  print(string.format("%s tags=[%s] value=%d", name, list, value))
end

function write_metric_to_statsd(name, tags, value)
  local map = {}
  for i, tag in ipairs(tags) do
    map[tag_labels[i]] = tag_cleaner(tag)
  end

  sysdig.push_metric(namespace .. "." .. name, value, map)
end

function gauge(args)
  if not args.name then error("gauge name is required!") end

  local metric = gauges[args.name]
  if not metric then
    gauges[args.name] = {}
    metric = gauges[args.name]
  end

  for _, dimension in ipairs({args.frontend, args.backend, args.server}) do
    if not metric[dimension] then
      metric[dimension] = {}
    end
    metric = metric[dimension]
  end

  metric[1] = args.value or 0
end

function counter(args)
  if not args.name then error("counter name is required!") end

  local metric = counters[args.name]
  if not metric then
    counters[args.name] = {}
    metric = counters[args.name]
  end

  for _, dimension in ipairs({args.frontend, args.backend, args.server}) do
    if not metric[dimension] then
      metric[dimension] = {}
    end
    metric = metric[dimension]
  end

  local value = metric[1]
  local incby = args.value or 1
  if not value then
    metric[1] = incby
  else
    metric[1] = value + incby
  end
end
