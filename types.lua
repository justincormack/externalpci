local ffi = require "ffi"

local t = {}

t.EXTERNALPCI_REQ = {
  REGION = 0,
  PCI_INFO = 1,
  IOT = 2,
  IRQ = 3,
  RESET = 4,
  EXIT = 5,
}

t.EXTERNALPCI_RES_FLAG = {
  FETCH_IRQS = 1,
}

t.IOT = {
  READ = 0,
  WRITE = 1,
}

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

t.region = ffi.typeof("struct externalpci_region")
t.req = ffi.typeof("struct externalpci_req")
t.res = ffi.typeof("struct externalpci_res")
t.iot_req = ffi.typeof("struct externalpci_iot_req")
t.iot_res = ffi.typeof("struct externalpci_iot_res")
t.irq_req = ffi.typeof("struct externalpci_irq_req")
t.irq_res = ffi.typeof("struct externalpci_irq_res")
t.pci_info_res = ffi.typeof("struct externalpci_pci_info_res")

