module nvme

import pci
import memory
import lib

const (
	nvme_class = 0x1
	nvme_subclass = 0x8
	nvme_progif = 0x2
)

const (
	opcode_delete_sq = 0x0
	opcode_create_sq = 0x1
	opcode_delete_cq = 0x4
	opcode_create_cq = 0x5
	opcode_identify = 0x6
	opcode_abort = 0x8
	opcode_set_features = 0x9
	opcode_get_features = 0xa
	opcode_ns_management = 0xd
	opcode_format_cmd = 0x80
)

[packed]
struct NVMERegisters {
pub mut:
	cap u64
	vs u32
	intms u32
	intmc u32
	cc u32
	rsvd1 u32
	csts u32
	rsvd2 u32
	aqa u32
	asq u64
	acq u64
}

[packed]
struct NVMECommandCreateCQ {
pub mut:
	rsvd1[5] u32
	prp1 u64
	rsvd2 u64
	cqid u16
	qsize u16
	cq_flags u16
	irq_vector u16
	rsvd3[4] u32
}

[packed]
struct NVMECommandCreateSQ {
pub mut:
	rsvd1[5] u32
	prp1 u64
	rsvd2 u64
	sqid u16
	qsize u16
	sq_flags u16
	cqid u16
	rsvd3[4] u32
}

[packed]
struct NVMECommandDeleteQ {
pub mut:
	rsvd1[9] u32
	qid u16
	rsvd2 u16
	rsvd3[5] u32
}

[packed]
struct NVMECommandAbort {
pub mut:
	rsvd1[9] u32
	sqid u16
	cid u16
	rsvd2[5] u32
}

[packed]
struct NVMECommandFeatures {
pub mut:
	nsid u32
	rsvd1[2] u64
	prp1 u64
	prp2 u64
	fid u32
	dword11 u32
	rsvd2[4] u32
}

[packed]
struct NVMECommandIdentify {
pub mut:
	nsid u32
	rsvd1[2] u64
	prp1 u64
	prp2 u64
	cns u32
	rsvd2[5] u32
}

[packed]
struct NVMECommandRW {
pub mut:
	nsid u32
	rsvd1 u64
	metadata u64
	prp1 u64
	prp2 u64
	slba u64
	length u16
	control u16
	dsmgmt u32
	reftag u32
	apptag u16
	appmask u16
}

union NVMECommandPrivate {
pub mut:
	create_cq NVMECommandCreateCQ
	create_sq NVMECommandCreateSQ
	delete_queue NVMECommandDeleteQ
	abort NVMECommandAbort
	features NVMECommandFeatures
	identify NVMECommandIdentify
	rw NVMECommandRW
}

[packed]
struct NVMECommand {
pub mut:
	opcode u8
	flags u8
	cid u16
	private NVMECommandPrivate
}

[packed]
struct NVMECompletion {
pub mut:
	result u32
	rsvd u32
	sq_head u16
	sq_id u16
	cid u16
	status u16
}

[packed]
struct NVMEPowerStateID {
pub mut:
	max_power u16
	rsvd1 u8
	flags u8
	entry_lat u32
	exit_lat u32
	read_tput u8
	read_lat u8
	write_tput u8
	write_lat u8
	idle_power u16
	idle_scale u8
	rsvd2 u8
	active_power u16
	active_work_scale u8
	rsvd3[9] u8
}

[packed]
struct NVMEControllerID {
pub mut:
	vid u16
	ssvid u16
	sn[20] char
	mn[40] char
	fr[8] char
	rab u8
	ieee[3] u8
	mic u8
	mdts u8
	cntlid u16
	ver u32
	rsvd1[172] u8
	oacs u16
	acl u8
	aerl u8
	frmw u8
	lpa u8
	elpe u8
	npss u8
	avscc u8
	apsta u8
	wctemp u16
	cctemp u16
	rsvd2[242] u8
	sqes u8
	cqes u8
	rsvd3[2] u8
	nn u32
	oncs u16
	fuses u16
	fna u8
	vwc u8
	awun u16
	awupf u16
	nvscc u8
	rsvd4 u8
	acwu u16
	rsvd5[2] u8
	sgls u32
	rsvd6[1508] u8
	psd[32] NVMEPowerStateID
	vs[1024] u8
}

[packed]
struct NVMELbaf { 
pub mut:
	ms u16
	ds u8
	rp u8
}

[packed]
struct NVMENamespaceID {
pub mut:
	nsze u64
	ncap u64
	nuse u64
	nsfeat u8
	nlbaf u8
	flbas u8
	mc u8 
	dpc u8
	dps u8 
	nmic u8 
	rescap u8 
	fpi u8 
	rsvd1 u8 
	nawun u16
	nawupf u16
	nacwu u16
	nabsn u16
	nabo u16
	nabspf u16
	rsvd2 u16
	nvmcap[2] u64
	rsvd3[40] u8
	nguid[16] u8
	eui64[8] u8
	lbaf_list[16] NVMELbaf
	rsvd4[192] u8
	vs[3712] u8
}

struct NVMEController { 
mut:
	pci_bar pci.PCIBar

	regs &NVMERegisters
	controller_id &NVMEControllerID

	queue_entries u64
	max_page_size u64
	min_page_size u64
	page_size u64
	max_transfer_shift u64
	max_prps u64
	strides u64
}

__global (
	controller_list []&NVMEController
)

pub fn (mut c NVMEController) initialise(pci_device pci.PCIDevice) bool {
	pci_device.enable_bus_mastering()

	if pci_device.is_bar_present(0x0) == false {
		print('nvme: unable to locate BAR0\n')
		return false
	}

	c.pci_bar = pci_device.get_bar(0x0)

	c.regs = &NVMERegisters(c.pci_bar.base + higher_half)

	major_version := (c.regs.vs >> 16) & 0xffff
	minor_version := (c.regs.vs >> 8) & 0xff
	tertiary_version := c.regs.vs & 0xff

	print('nvme: Version Detected [${major_version}:${minor_version}:${tertiary_version}]\n')

	if (u64(c.regs.cap) & (u64(1) << 37)) == 0 {
		print('nvme: NVME command set not supported\n')
		return false
	}

	c.max_page_size = lib.power(2, 12 + ((c.regs.cap >> 52) & 0xf))
	c.min_page_size = lib.power(2, 12 + ((c.regs.cap >> 48) & 0xf))

	cc := c.regs.cc

	if (cc & (1 << 0)) != 0 {
		c.regs.cc = cc & ~(1 << 0) // disable controller
	}

	for c.regs.csts & (1 << 0) != 0 { }

	if pci_device.msi_support == true {
		print('nvme: device is msi capable\n')
	} else if pci_device.msix_support == true {
		print('nvme: device is msix capable\n')
	} else {
		print('nvme: device is not msi or msix capable\n')
		return false
	}

	return true
}

pub fn initialise() {
	for device in scanned_devices {
		if device.class == nvme_class && device.subclass == nvme_subclass && device.prog_if == nvme_progif {
			mut nvme_device := &NVMEController(memory.calloc(sizeof(NVMEController), 1))

			if nvme_device.initialise(device) == true {
				controller_list << nvme_device
			}
		}
	}
}
