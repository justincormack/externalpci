local function assert(cond, s, ...)
  if cond == nil then error(tostring(s)) end
  return cond, s, ...
end

local S = require "syscall"
local t, c = S.t, S.c
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

handle_request = {}

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

local req, res = p.req(), p.res()
local iov = t.iovec(req, #req)
local msg = t.msghdr{io = iov, control = req}

for i, ev in ep:get() do

  if ep.eof(ev) then
    ev.fd:close()
    w[ev.fd] = nil
  end

  if ev.fd == sock:getfd() then -- server socket, accept
    repeat
      local a, err = sock:accept(ss, nil)
      if a then
        ep:add(a.fd)
        w[a.fd:getfd()] = a.fd
      end
    until not a
  else
    local fd = w[ev.fd]
    local n, err = fd:recvmsg(msg)
    if n and #n ~= #req then
      print("bad request size")
      n = nil
    end
    if n and n == 0 then
      print("client closed connection")
      n = nil
    end
    if n then
      local recvfd
      for mc, cmsg in msg:cmsgs() do
        for fd in cmsg:fds() do
          recvfd = fd
        end
      end
      if req.type == p.EXTERNALPCI_REQ.REGION then
        if recvfd then req.region.fd = recvfd else n = nil end
      elseif req.type == p.EXTERNALPCI_REQ.IRQ then
        if recvfd then req.irq_req.fd = recvfd else n = nil end
      elseif recvfd then
        print("unexpected fd sent")
        n = nil
      end
    end
    if n then
      if not handle_request[req.type] then
        print("unhandled request type " .. req.type)
        n = nil
      else
        res.type = req.type
        n = handle_request[req.type](req, res)
      end
    end
    if not n then
      if err then print(err) end
      fd:close()
      w[ev.fd] = nil
      print("connection closed")
    end
    -- TODO send res
  end
end

return loop()

end

handle_request[p.EXTERNALPCI_REQ.PCI_INFO] = function(req, res)
  res.pci_info.vendor_id, res.pci_info.device_id, res.pci_info.subsystem_id, res.pci_info.subsystem_vendor_id =
    p.VIRTIO_NET.VENDOR_ID, p.VIRTIO_NET.DEVICE_ID, p.VIRTIO_NET.SUBSYSTEM_ID, p.VIRTIO_NET.SUBSYSTEM_VENDOR_ID



end



loop()

