local HAS_RUNNER = not not lunit
local lunit      = require "lunit"
local TEST_CASE  = assert(lunit.TEST_CASE)
local skip       = lunit.skip or function() end

local zmq        = require "lzmq"
local ztimer     = require "lzmq.timer"
local zmonitor   = require "lzmq.monitor"

local _ENV = TEST_CASE "lzmq.monitor" do

local ctx, sink, sinkmon, source, sourcemon

local function check_event(self, expected_event)
  local event, value, address, desc = self:recvx()
  assert(event, value)
  event = assert_number(tonumber(event), event)
  return event == expected_event
end

function setup()
  ctx = assert(zmq.context())

  sink = assert(ctx:socket(zmq.PULL))
  sinkmon = assert(zmonitor.new(sink))
  sinkmon:verbose(verbose)
  sinkmon:listen(zmq.EVENT_LISTENING)
  sinkmon:listen(zmq.EVENT_ACCEPTED)
  sinkmon:start()

  source = ctx:socket(zmq.PUSH)
  sourcemon = zmonitor.new(source)
  sourcemon:verbose(verbose)
  sourcemon:listen(zmq.EVENT_CONNECTED)
  sourcemon:listen(zmq.EVENT_DISCONNECTED)
  sourcemon:start()

  --  Allow a brief time for the message to get there...
  ztimer.sleep(200)
end

function teardown()
  if ctx then ctx:destroy() end
end

function test()
  --  Ceck sink is now listening
  local port_nbr, err = assert_number(sink:bind_to_random_port("tcp://127.0.0.1"))
  assert_true(check_event (sinkmon, zmq.EVENT_LISTENING))

  --  Check source connected to sink
  source:connect("tcp://127.0.0.1:" .. port_nbr)
  assert_true(check_event (sourcemon, zmq.EVENT_CONNECTED))

  --  Check sink accepted connection
  assert_true(check_event (sinkmon, zmq.EVENT_ACCEPTED))

  sinkmon:destroy()
  sourcemon:destroy()
  sink:close()
  source:close()
end

end

if not HAS_RUNNER then lunit.run() end
