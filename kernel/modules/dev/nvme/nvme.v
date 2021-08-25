module nvme

import pci
import memory
import lib
import x86.idt
import x86.kio
import event
import bitmap

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
pub mut:
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
	qid_bitmap bitmap.GenericBitmap

	admin_queue &NVMEQueuePair
	namespace_list []&NVMENamespace
}

struct NVMEQueuePair {
pub mut:
	qid u64
	entry_cnt u64
	sq_head u64
	sq_tail u64
	cq_head u64
	cq_tail u64
	phase bool
	vector u64
	irq u64
	admin bool

	parent_controller &NVMEController

	submission_queue &NVMECommand
	completion_queue &NVMECompletion
	submission_doorbell &u32
	completion_doorbell &u32

	cid_bitmap bitmap.GenericBitmap
}

struct NVMENamespace {
pub mut:
	lba_cnt u64
	lba_size u64
	max_prps u64
	nsid u64

	parent_controller &NVMEController
	identity &NVMENamespaceID
}

__global (
	controller_list []&NVMEController
)

pub fn (mut namespace NVMENamespace) initialise(mut parent_controller &NVMEController, nsid u64) int {
	unsafe { namespace.parent_controller = parent_controller }
	namespace.nsid = nsid
	namespace.identity = &NVMENamespaceID(u64(memory.pmm_alloc(lib.div_roundup(sizeof(NVMENamespaceID), page_size))) + higher_half)

	mut new_command := &NVMECommand(memory.calloc(sizeof(NVMECommand), 1))

	unsafe {
		new_command.opcode = opcode_identify 
		new_command.private.identify.cns = 0
		new_command.private.identify.nsid = u32(nsid)
		new_command.private.identify.prp1 = u64(namespace.identity) - higher_half
	}

	if parent_controller.admin_queue.send_cmd_and_wait(mut new_command, -1) == 0xffff {
		print('nvme: nsid ${nsid:x} : unable to read namespace identity\n')
		return -1
	}

	calcuate_max_prps := fn (mut c &NVMEController, identity &NVMENamespaceID) u64 {
		lba_shift := identity.lbaf_list[identity.flbas & 0xf].ds

		shift := 12 + (c.regs.cap >> 48 & 0xf)
		mut max_transfer_shift := u64(20)

		if c.controller_id.mdts != 0 {
			max_transfer_shift = u64(shift + c.controller_id.mdts)
		}

		max_lbas := 1 << (max_transfer_shift - lba_shift)

		return (u64(max_lbas) * (1 << u64(lba_shift))) / 0x1000
	}

	namespace.max_prps = calcuate_max_prps(mut parent_controller, namespace.identity)
	namespace.lba_cnt = namespace.identity.nsze
	namespace.lba_size = 1 << u64(namespace.identity.lbaf_list[namespace.identity.flbas & 0b11111].ds)
	
	return 0
}

pub fn (mut pair NVMEQueuePair) initialise(parent_controller &NVMEController, vector u64, irq u64, admin bool) bool {
	qid := parent_controller.qid_bitmap.alloc() or {
		print('nvme: no available qid\n')
		return false
	}

	if qid != 0 && admin == true {
		print('nvme: cannot create admin queue with non-zero qid\n')
		return false
	}

	pair.parent_controller = unsafe { parent_controller }
	pair.vector = vector
	pair.irq = irq
	pair.admin = admin
	pair.entry_cnt = parent_controller.queue_entries

	pair.submission_queue = &NVMECommand(u64(memory.pmm_alloc(lib.div_roundup(pair.entry_cnt * sizeof(NVMECommand), page_size))) + higher_half)
	pair.completion_queue = &NVMECompletion(u64(memory.pmm_alloc(lib.div_roundup(pair.entry_cnt * sizeof(NVMECompletion), page_size))) + higher_half)

	submission_offset := page_size + 2 * qid * (4 << parent_controller.strides)
	pair.submission_doorbell = &u32(u64(parent_controller.regs) + submission_offset)

	completion_offset := page_size + ((2 * qid + 1) * (4 << parent_controller.strides))
	pair.completion_doorbell = &u32(u64(parent_controller.regs) + completion_offset)

	pair.cid_bitmap.initialise(pair.entry_cnt)

	if admin == true {
		return true
	}

	return false
}

pub fn (mut pair NVMEQueuePair) send_cmd(mut submission &NVMECommand, cid int) int {
	mut command_cid := cid

	if cid == -1 {
		command_cid = int(pair.cid_bitmap.alloc() or {
			print('nvme: no available cids on qid ${pair.qid:x}\n')
			return -1
		})
	}

	submission.cid = u16(command_cid)

	unsafe {
		pair.submission_queue[pair.sq_tail] = submission
	}

	pair.sq_tail++

	if pair.sq_tail == pair.entry_cnt {
		pair.sq_tail = 0
	}

	kio.mmout(unsafe { &u64(pair.submission_doorbell) }, pair.sq_tail)

	return 0
}

pub fn (mut pair NVMEQueuePair) send_cmd_and_wait(mut submission NVMECommand, cid int) u16 {
	if pair.send_cmd(mut submission, cid) == -1 {
		print('nvme: unable to send a command to qid ${pair.qid:x}\n')
		return 0xffff
	}

	mut events := [&int_events[pair.vector]]
	event.await(mut events, true) or { }

	mut completion_entry := unsafe { pair.completion_queue[pair.cq_head] }

	if (completion_entry.status >> 1) != 0 {
		print('nvme: command error: status ${completion_entry.status:x}\n')
		return completion_entry.status
	}

	pair.cq_head++

	if pair.cq_head == pair.entry_cnt {
		pair.cq_head = 0
		pair.phase = !pair.phase
	}

	pair.cid_bitmap.free(u64(cid))

	kio.mmout( unsafe { &u64(pair.submission_doorbell) }, pair.cq_head)

	return completion_entry.status 
}

fn (mut c NVMEController) get_controller_id() int {
	c.controller_id = &NVMEControllerID(u64(memory.pmm_alloc(lib.div_roundup(sizeof(NVMEControllerID), page_size))) + higher_half)

	mut new_command := &NVMECommand(memory.calloc(sizeof(NVMECommand), 1))

	unsafe {
		new_command.opcode = opcode_identify
		new_command.private.identify.cns = 1
		new_command.private.identify.prp1 = u64(c.controller_id) - higher_half
	}

	if c.admin_queue.send_cmd_and_wait(mut new_command, -1) == 0xffff {
		print('nvme: unable to read controller id\n')
		return -1
	}

	return 0
}

pub fn (mut c NVMEController) initialise(pci_device &pci.PCIDevice) int {
	pci_device.enable_bus_mastering()

	if pci_device.is_bar_present(0x0) == false {
		print('nvme: unable to locate BAR0\n')
		return -1
	}

	c.pci_bar = pci_device.get_bar(0x0)

	c.regs = &NVMERegisters(c.pci_bar.base + higher_half)

	major_version := (c.regs.vs >> 16) & 0xffff
	minor_version := (c.regs.vs >> 8) & 0xff
	tertiary_version := c.regs.vs & 0xff

	print('nvme: Version Detected [${major_version}:${minor_version}:${tertiary_version}]\n')

	if (u64(c.regs.cap) & (u64(1) << 37)) == 0 {
		print('nvme: NVME command set not supported\n')
		return -1
	}

	c.max_page_size = lib.power(2, 12 + ((c.regs.cap >> 52) & 0xf))
	c.min_page_size = lib.power(2, 12 + ((c.regs.cap >> 48) & 0xf))

	if (c.regs.cc & (1 << 0)) != 0 {
		c.regs.cc = c.regs.cc & ~(1 << 0) // disable controller
	}

	for c.regs.csts & (1 << 0) != 0 { }

	mut vect := byte(0)

	if pci_device.msi_support == true {
		print('nvme: device is msi capable\n')

		vect = idt.allocate_vector()
		pci_device.set_msi(vect)
	} else if pci_device.msix_support == true {
		print('nvme: device is msix capable\n')

		vect = idt.allocate_vector()
		pci_device.set_msix(vect)
	} else {
		print('nvme: device is not msi or msix capable\n')
		return -1
	}

	c.queue_entries = c.regs.cap & 0xffff
	c.strides = c.regs.cap >> 32 & 0xf

	c.qid_bitmap.initialise(0xffff)

	c.admin_queue = &NVMEQueuePair(memory.calloc(sizeof(NVMEQueuePair), 1))
	if c.admin_queue.initialise(c, vect, 0, true) == false {
		print('nvme: failed to create an admin queue\n')
		return -1
	}

	c.regs.aqa = u32((c.queue_entries - 1) << 16 | (c.queue_entries - 1))
	c.regs.asq = u64(c.admin_queue.submission_queue) - higher_half
	c.regs.acq = u64(c.admin_queue.completion_queue) - higher_half

	c.regs.cc =		(0 << 4) | // nvme command set
					(0 << 11) | // ams = round robin
					(0 << 14) | // no shutdown notifications
					(6 << 16) | // io submission queue size 16 bytes
					(4 << 20) | // io completion queue size 64 bytes
					(1 << 0) // enable	

	for {
		if c.regs.csts & (1 << 0) != 0 {
			break
		} else if c.regs.csts & (1 << 1) != 0 {
			print('nvme: controller fatal status\n')
			return -1
		}
	}

	print('nvme: controller restart\n')

	if c.get_controller_id() == -1 {
		print('nvme: fatal error\n')
		return -1
	}

	print('nvme: vendor ID: ${c.controller_id.vid:x}\n')
	print('nvme: subsystem vendor ID: ${c.controller_id.ssvid}\n')

	nsid_list := &u32(u64(memory.pmm_alloc(lib.div_roundup(c.controller_id.nn * 4, page_size))) + higher_half)

	mut new_command := &NVMECommand(memory.calloc(sizeof(NVMECommand), 1))

	unsafe {
		new_command.opcode = opcode_identify 
		new_command.private.identify.cns = 2
		new_command.private.identify.prp1 = u64(nsid_list) - higher_half
	}

	if c.admin_queue.send_cmd_and_wait(mut new_command, -1) == 0xffff {
		print('nvme: unable to read nsid list\n')
		return -1
	}

	for i := u64(0); i < c.controller_id.nn; i++ {
		if unsafe { nsid_list[i] != 0 } {
			mut new_namespace := &NVMENamespace(memory.calloc(sizeof(NVMENamespace), 1))

			if new_namespace.initialise(mut c, unsafe { nsid_list[i] }) != 0 {
				print('nvme: fatel error\n')
				return -1
			}

			print('nvme: namespace id: ${new_namespace.nsid:x}\n')
			print('nvme: lba cnt: ${new_namespace.lba_cnt:x}\n')
			print('nvme: lba size: ${new_namespace.lba_size:x}\n')
			print('nvme: max prps: ${new_namespace.max_prps:x}\n')

			c.namespace_list << new_namespace
		}
	}

	return 0
}

pub fn initialise() {
	for device in scanned_devices {
		if device.class == nvme_class && device.subclass == nvme_subclass && device.prog_if == nvme_progif {
			mut nvme_device := &NVMEController(memory.calloc(sizeof(NVMEController), 1))

			if nvme_device.initialise(device) != -1 {
				controller_list << nvme_device
			}
		}
	}
}
