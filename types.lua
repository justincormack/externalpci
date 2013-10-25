local ffi, bit = require "ffi", require "bit"

local p = {}

p.VIRTIO_NET = {
  VENDOR_ID           = 0x1AF4,
  DEVICE_ID           = 0x1000,
  SUBSYSTEM_ID        = 0x0001,
  SUBSYSTEM_VENDOR_ID = 0x1AF4,
}

p.EXTERNALPCI_REQ = {
  REGION = 0,
  PCI_INFO = 1,
  IOT = 2,
  IRQ = 3,
  RESET = 4,
  EXIT = 5,
}

p.EXTERNALPCI_RES_FLAG = {
  FETCH_IRQS = 1,
}

p.IOT = {
  READ = 0,
  WRITE = 1,
}

p.MSIX_VECTORS = 3
p.VIRT_QUEUES  = 3
p.QUEUE_ELEMENTS = 1024

p.EXTERNALPCI_RES_FLAG_FETCH_IRQS = 1

-- the fd fields are not ideal for us, prefer Lua objects
ffi.cdef[[
struct externalpci_region {
  int fd;
  uint64_t offset;
  uint64_t phys_addr;
  uint64_t size;
};

struct externalpci_irq_req {
  int fd;
  int idx;
};

struct externalpci_irq_res {
  bool valid;
  bool more;
};

struct externalpci_iot_req {
  uint64_t hwaddr;
  uint32_t value;
  uint8_t  size;
  uint8_t  bar;
  int type; /* IOT.READ/WRITE */
};

struct externalpci_iot_res {
  uint32_t value;
};

struct externalpci_pci_info_res {
  uint16_t vendor_id;
  uint16_t device_id;
  uint16_t subsystem_id;
  uint16_t subsystem_vendor_id;
  uint8_t  msix_vectors;

  uint8_t  hotspot_bar;
  uint16_t hotspot_addr;
  uint8_t  hotspot_size;
  int      hotspot_fd;

  struct {
    uint32_t size;
  } bar[6];
};

struct externalpci_req {
  uint32_t type;
  union {
    struct externalpci_region  region;
    struct externalpci_iot_req iot_req;
    struct externalpci_irq_req irq_req;
  };
};

struct externalpci_res {
  uint32_t type;
  uint32_t flags;
  union {
    struct externalpci_pci_info_res pci_info;
    struct externalpci_iot_res      iot_res;
    struct externalpci_irq_res      irq_res;
  };
};
]]

local function lenfn(tp) return ffi.sizeof(tp) end
local mt = {__len = lenfn}

p.region = ffi.typeof("struct externalpci_region")
p.req = ffi.metatype("struct externalpci_req", mt)
p.res = ffi.metatype("struct externalpci_res", mt)
p.iot_req = ffi.typeof("struct externalpci_iot_req")
p.iot_res = ffi.typeof("struct externalpci_iot_res")
p.irq_req = ffi.typeof("struct externalpci_irq_req")
p.irq_res = ffi.typeof("struct externalpci_irq_res")
p.pci_info_res = ffi.typeof("struct externalpci_pci_info_res")

-- constants from ljsyscall
p.PCI_BASE_ADDRESS = {
  SPACE         = 0x01,
  SPACE_IO      = 0x01,
  SPACE_MEMORY  = 0x00,
  MEM_TYPE_MASK = 0x06,
  MEM_TYPE_32   = 0x00,
  MEM_TYPE_1M   = 0x02,
  MEM_TYPE_64   = 0x04,
  MEM_PREFETCH  = 0x08,
  --MEM_MASK      (~0x0fUL)
  --IO_MASK       (~0x03UL)
}

p.VIRTIO = {
  PCI_HOST_FEATURES       = 0,
  PCI_GUEST_FEATURES      = 4,
  PCI_QUEUE_PFN           = 8,
  PCI_QUEUE_NUM           = 12,
  PCI_QUEUE_SEL           = 14,
  PCI_QUEUE_NOTIFY        = 16,
  PCI_STATUS              = 18,
  PCI_ISR                 = 19,
  PCI_ISR_CONFIG          = 0x2,
  MSI_CONFIG_VECTOR       = 20,
  MSI_QUEUE_VECTOR        = 22,
  MSI_NO_VECTOR           = 0xffff,
  PCI_ABI_VERSION         = 0,
  PCI_QUEUE_ADDR_SHIFT    = 12,
  PCI_VRING_ALIGN         = 4096,
  -- VIRTIO_PCI_CONFIG_OFF(msix_enabled)     ((msix_enabled) ? 24 : 20)
}

p.EPOLL = {
  IN  = 0x001,
  PRI = 0x002,
  OUT = 0x004,
  RDNORM = 0x040,
  RDBAND = 0x080,
  WRNORM = 0x100,
  WRBAND = 0x200,
  MSG = 0x400,
  ERR = 0x008,
  HUP = 0x010,
  RDHUP = 0x2000,
  ONESHOT = bit.lshift(1, 30),
  ET = bit.lshift(1, 30) * 2, -- 2^31 but making sure no sign issue
}

return p

