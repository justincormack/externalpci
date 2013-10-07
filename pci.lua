local function assert(cond, s, ...)
  if cond == nil then error(tostring(s)) end
  return cond, s, ...
end

local S = require "syscall"
local t = S.t
local p = require "types" -- pci types

local maxevents = 1024
local poll = {
  init = function(this)
    return setmetatable({fd = assert(S.epoll_create())}, {__index = this})
  end,
  event = t.epoll_event(),
  add = function(this, s)
    local event = this.event
    event.events = c.EPOLL.IN
    event.data.fd = s:getfd()
    assert(this.fd:epoll_ctl("add", s, event))
  end,
  events = t.epoll_events(maxevents),
  get = function(this)
    return this.fd:epoll_wait(this.events)
  end,
  eof = function(ev) return ev.HUP or ev.ERR or ev.RDHUP end,
}

local sockfile = "/tmp/sv3"
S.unlink(sockfile)

local sock = assert(S.socket("local", "seqpacket"))
local sa = t.sockaddr_un(sockfile)

assert(sock:bind(sa))
assert(sock:listen())

local ep = poll:init()
ep:add(sock)

local w = {}

local function loop()

for i, ev in ep:get() do

  if ep.eof(ev) then
    ev.fd:close()
    w[ev.fd] = nil
  end

  if ev.fd == sock:getfd() then -- server socket, accept
    repeat
      local a, err = sock:accept(ss, nil, "nonblock")
      if a then
        ep:add(a.fd)
        w[a.fd:getfd()] = a.fd
      end
    until not a
  else
    local fd = w[ev.fd]
    fd:read(buffer, bufsize)
    local n = fd:write(reply)
    assert(n == #reply)
    assert(fd:close())
    w[ev.fd] = nil
  end
end

return loop()

end

loop()

