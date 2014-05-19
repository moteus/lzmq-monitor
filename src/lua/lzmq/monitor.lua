local zmq      = require "lzmq"
local zthreads = require "lzmq.threads"
local ztimer   = require "lzmq.timer"
local string   = require "string"

local monitor_thread_proc = string.dump(function(...)
  local pipe = ...
  local ctx = pipe:context()
  local ok, err = pcall(function(...)
    require "lzmq.impl.monitor"(...)
  end, ...)
  if not ok then
    if not pipe:closed() then
      pipe:sendx("ERROR", tostring(err))
    end
    ctx:destroy(200)
  end
end)

local zmonitor = {} do
zmonitor.__index = zmonitor

function zmonitor:new(skt)
  local o = setmetatable({
    private_ = {
      skt = assert(skt);
      ctx = assert(skt:context());
    }
  }, self)

  assert(o:_init())
  return o
end

function zmonitor:_init()
  if not self:started() then
    local thread, pipe = zthreads.fork(self:context(),
      monitor_thread_proc, self.private_.skt:lightuserdata()
    )

    if not thread then return nil, pipe end
    thread:start(true, true)
    local ok, err = pipe:recvx()

    if not ok then -- thread terminate
      if not pipe:closed() then
        pipe:send('TERMINATE') -- just in case
      end
      thread:join()
      pipe:close()
      return nil, err
    end

    if ok == 'ERROR' then
      thread:join()
      pipe:close()
      return nil, err
    end

    assert(ok == 'OK')

    self.private_.thread, self.private_.pipe = thread, pipe
    pipe:set_rcvtimeo(100)
  end
  return true
end

function zmonitor:destroy()
  if self.private_ then
    self:stop()
    self.private_ = nil
  end
end

zmonitor.__gc = zmonitor.destroy

function zmonitor:started()
  return not not self.private_.thread
end

function zmonitor:alive()
  local thread = self.private_.thread
  if thread and thread.alive then
    return thread:alive()
  end
  return self:started()
end

function zmonitor:context()
  return self.private_.ctx
end

function zmonitor:sendx(...)
  return self.private_.pipe:sendx(...)
end

function zmonitor:recvx(...)
  return self.private_.pipe:recvx(...)
end

function zmonitor:join(...)
  self.private_.thread:join(...)
  self.private_.pipe:close()
  self.private_.thread, self.private_.pipe = nil
end

function zmonitor:stop()
  if self:alive() then
    self:sendx('TERMINATE')
  end
  if self:started() then
    self:join()
  end
end

function zmonitor:listen(event)
  self:sendx('LISTEN', tostring(event))
  return self:recvx()
end

function zmonitor:start()
  self:sendx('START')
  return self:recvx()
end

function zmonitor:verbose(...)
  local enable = ...
  if select("#", ...) == 0 then enable = true end
  self:sendx('VERBOSE', enable and '1' or '0')
  return self:recvx()
end

end

return {
  new = function(...) return zmonitor:new(...) end;
}
