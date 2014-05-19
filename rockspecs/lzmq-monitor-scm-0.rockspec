package = "lzmq-monitor"
version = "scm-0"

source = {
  url = "https://github.com/moteus/lzmq-monitor/archive/master.zip",
  dir = "lzmq-monitor-master",
}

description = {
  summary = "Module for ZMQ socket event monitoring",
  homepage = "https://github.com/moteus/lzmq-monitor",
  license = "MIT/X11",
}

dependencies = {
  "lua >= 5.1, < 5.3",
  -- "lzmq > 0.3.6" or "lzmq-ffi > 0.3.6",
}

build = {
  copy_directories = {"test"},

  type = "builtin",

  modules = {
    ["lzmq.monitor"       ] = "src/lua/lzmq/monitor.lua";
    ["lzmq.impl.monitor"  ] = "src/lua/lzmq/impl/monitor.lua";
  },
}
