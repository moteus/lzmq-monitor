return function (pipe, handle)

local function prequire(...)
  local ok, mod = pcall(require, ...)
  if ok then return mod end
  return nil, mod
end

local zmq      = require "lzmq"
local zloop    = require "lzmq.loop"
local bit      = prequire "bit"
if not bit then bit = require "bit32" end

local loop
local ctx       = pipe:context()
local allow_any = false
local verbose   = false
local events    = 0
local monitored
local sink

local function log(...)
  if verbose then
    print(string.format(...))
  end
end

local on_event do 

local known_events = {
  [ zmq.EVENT_ACCEPTED        or "----" ] = "Accepted";
  [ zmq.EVENT_ACCEPT_FAILED   or "----" ] = "Accept failed";
  [ zmq.EVENT_BIND_FAILED     or "----" ] = "Bind failed";
  [ zmq.EVENT_CLOSED          or "----" ] = "Closed";
  [ zmq.EVENT_CLOSE_FAILED    or "----" ] = "Close failed";
  [ zmq.EVENT_DISCONNECTED    or "----" ] = "Disconnected";
  [ zmq.EVENT_CONNECTED       or "----" ] = "Connected";
  [ zmq.EVENT_CONNECT_DELAYED or "----" ] = "Connect delayed";
  [ zmq.EVENT_CONNECT_RETRIED or "----" ] = "Connect retried";
  [ zmq.EVENT_LISTENING       or "----" ] = "Listening";
  [ zmq.EVENT_MONITOR_STOPPED or "----" ] = "Monitor stopped";
}

on_event = function(sok)
  local event, value, address = sok:recv_event()
  if not event then return end

  local description = known_events[event]
  if not description then
    log("E: zmonitor: illegal socket monitor event: " .. tostring(event))
    return
  end

  log("I: zmonitor: %s - %s", description, address)

  pipe:sendx(
    tostring(event), tostring(value), address, description
  )
end

end

local on_pipe do -- front end API

local API = {} do

function API.LISTEN(msg)
  local event = tonumber(msg[2]) or 0
  events = bit.bor(events, event)
  return 'OK'
end

function API.START(msg)
  assert (not sink)

  local endpoint, err = monitored:monitor(events);
  if not endpoint then
    log("E: zmonitor attach monitor socket: " .. err)
    return
  end
  log("I: zmonitor attach monitor socket: " .. endpoint)
  assert (endpoint, err)

  sink, err = loop:add_new_socket(
    {zmq.PAIR, connect = endpoint, linger = 0, sndtimeo = 100, rcvtimeo = 100},
    on_event
  )
  if not endpoint then
    log("E: zmonitor creat sink socket: " .. err)
    return
  end
  log("I: zmonitor creat sink socket pass")

  return 'OK'
end

function API.VERBOSE(msg)
  local enabled = msg[2]
  verbose = (enabled == '1')
  return 'OK'
end

function API.TERMINATE(msg)
  loop:interrupt()
  return 'OK'
end

end

on_pipe = function(sok)
  local msg = sok:recv_all()
  if not msg then return loop:interrupt() end
  local cmd = msg[1]
  log("I: zmonitor received API command: %s", table.concat(msg, '::'))
  local fn = API[cmd]
  if not fn then
    log("E: zmonitor: invalid command from API: %s", cmd)
    return 
  end
  local res = fn(msg)
  if res then
    sok:send(res)
    log("I: zmonitor API done: %s", res)
  end
end

end

do -- main loop

local ok, err

-- INIT INSTANCE
repeat

monitored, err = zmq.init_socket(handle)
if not monitored then 
  err = err or "can not init monitored socket"
  break
end

loop, err = zloop.new(2, ctx)
if not loop then
  err = "can not create zmq.loop: " .. tostring(err)
  break
end

pipe:set_linger(100)

ok, err = loop:add_socket(pipe, on_pipe)
if not ok then
  err = "can not start poll pipe socket: " .. tostring(err)
  break
end

until true

if ok then
  pipe:send("OK")

  log("I: zmonitor start loop")
  loop:start()
  log("I: zmonitor loop interrupted")
else
  log("E: zmonitor init fail: " .. tostring(err))
  pipe:sendx("ERROR", tostring(err))
end

end

if monitored then
  monitored:reset_monitor()
end

ctx:destroy(100)

log("I: zmonitor thread done!")
end
