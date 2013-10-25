-- proof of concept

-- TODO identify client when outputting (fd to client number)

local function assert(cond, s, ...)
  if cond == nil then error(tostring(s)) end
  return cond, s, ...
end

local ffi, bit = require "ffi", require "bit"

package.path = "./?.lua;./ljsyscall/?.lua;"

local S = require "syscall"
local t, s = S.t, S.types.s
local p = require "types" -- pci types

local voidp = ffi.typeof("void *")
function void(x)
  return ffi.cast(voidp, x)
end

local maxevents = 1024
local poll = {
  init = function(this)
    return setmetatable({fd = assert(S.epoll_create())}, {__index = this})
  end,
  event = t.epoll_event(),
  add = function(this, s)
    local event = this.event
    event.events = p.EPOLL.IN
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

local address_hint = t.uintptr(0x100000000ULL)

local sock = assert(S.socket("local", "seqpacket"))
local sa = t.sockaddr_un(sockfile)

assert(sock:bind(sa))
assert(sock:listen())

local ep = poll:init()
ep:add(sock)

local evfd = assert(S.eventfd()) -- eventfd for network events

local w = {}

local req, res = p.req(), p.res()
local iovreq = t.iovec(req, #req)
local iovres = t.iovec(res, #res)
local chdr = t.cmsghdr("socket", "rights", nil, s.int) -- space for single fd
local msg = t.msghdr()

local function resp(fd)
  -- receive request
  local recvfd
  msg.iov, msg.control = iovreq, chdr
  local n, err = fd:recvmsg(msg)
  if n and n ~= #req then
    print("bad request size " .. n .. " not " .. #req)
    n = nil
  end
  if n and n == 0 then
    print("client closed connection")
    n = nil
  end
  if n then
    for mc, cmsg in msg:cmsgs() do
      for fd in cmsg:fds() do
        recvfd = fd
      end
    end
    if req.type == p.EXTERNALPCI_REQ.REGION or req.type == p.EXTERNALPCI_REQ.IRQ then
      if not recvfd then n = nil end
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
      n = handle_request[req.type](req, res, recvfd)
      if not n then print("req handler failed") end
    end
  end
  if not n then
    if err then print("recv error: " .. tostring(err)) end
    fd:close()
    print("connection closed")
    return
  end
  -- send response
  msg.iov, msg.control = iovres, nil
  if res.type == p.EXTERNALPCI_REQ.PCI_INFO then -- need to send fd
    chdr:setfd(res.pci_info.hotspot_fd)
    msg.control = chdr
  end
  local n, err = fd:sendmsg(msg)
  if n and n ~= #res then
    print("short send " .. n .. " not " .. #res)
    n = nil
  end
  if not n then
    if err then print("send error: " .. tostring(err)) end
    fd:close()
    print("connection closed")
    return
  end
  return true
end

local function loop()

for i, ev in ep:get() do

  if ep.eof(ev) then
    w[ev.fd]:close()
    w[ev.fd] = nil
  end

  if ev.fd == sock:getfd() then -- server socket, accept
    local a, err = sock:accept(ss, nil)
    if a then
      ep:add(a)
      w[a:getfd()] = a
    end
  else
    local ok = resp(w[ev.fd])
    if not ok then w[ev.fd] = nil end
  end
end

return loop()

end

handle_request[p.EXTERNALPCI_REQ.PCI_INFO] = function(req, res)
  local info = res.pci_info
  -- device info (static)
  info.vendor_id, info.device_id, info.subsystem_id, info.subsystem_vendor_id =
    p.VIRTIO_NET.VENDOR_ID, p.VIRTIO_NET.DEVICE_ID, p.VIRTIO_NET.SUBSYSTEM_ID, p.VIRTIO_NET.SUBSYSTEM_VENDOR_ID

  -- bar sizes, just one IO space
  info.bar[0].size = 0x40 + p.PCI_BASE_ADDRESS.SPACE_IO
  for i = 1, 5 do
    info.bar[i].size = 0
  end
  -- irq info
  info.msix_vectors = p.MSIX_VECTORS
  -- hotspot
  info.hotspot_bar = 0
  info.hotspot_addr = p.VIRTIO.PCI_QUEUE_NOTIFY
  info.hotspot_size = 2
  info.hotspot_fd = evfd:getfd()
  return true
end

handle_request[p.EXTERNALPCI_REQ.REGION] = function(req, res, fd)
  local mem, err = S.mmap(void(address_hint), req.region.size, "read, write", "shared", fd, req.region.offset)
  fd:close()
  if not mem then
    print("mmap: " .. tostring(err))
    return
  end
  address_hint = address_hint + req.region.size
  print("Inserting memory region " .. tostring(req.region.phys_addr) .. "+" .. tostring(req.region.size) .. " at " .. tostring(mem))
  -- TODO pass mem, size to Snabb switch this is client buffer
  return true
end

handle_request[p.EXTERNALPCI_REQ.RESET] = function(req, res)
  print("RESET device")
  -- TODO tell Snabb we have a device reset
  return true
end

handle_request[p.EXTERNALPCI_REQ.IRQ] = function(req, res, fd)
  if req.irq_req.idx < 0 or req.irq_req.idx >= p.MSIX_VECTORS then
    print("invalid index for MSIX")
    return
  end
  -- TODO check that fd not received for this index already
  print("got IRQ fd " .. fd:getfd() .. "for MSIX " .. req.irq_req.idx)
  -- give fd to Snabb for signalling on!
  if req.irq_req.idx + 1 < p.MSIX_VECTORS then res.irq_res.more = 1 else res.irq_res.more = 0 end
  return true
end

function devread(bar, addr, size)
  print("unimplemented dev read")
  -- TODO!!!!
  return 0
end

function devwrite(bar, addr, size, value) -- return true if irqss changed
  print("unimplemented dev write")
  -- TODO!!!!
  return false
end

handle_request[p.EXTERNALPCI_REQ.IOT] = function(req, res)
  if req.iot_req.type == p.IOT.READ then -- read
    res.iot_res.value = devread(req.iot_req.bar, req.iot_req.hwaddr, req.iot_req.size)
  else -- write
    local irqs_changed = devwrite(req.iot_req.bar, req.iot_req.hwaddr, req.iot_req.size, req.iot_req.value)
    if irqs_changed then res.flags = bit.bor(res.flags, p.EXTERNALPCI_RES_FLAG_FETCH_IRQS) end
  end
  return true
end

loop()

