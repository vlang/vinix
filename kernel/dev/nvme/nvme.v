@[has_globals]
module nvme

import pci
import devcore
import dma
import proc
import memory
import lib
import bitmap
import stat
import klock
import event.eventstruct
import resource
import errno
import block.fence
import block.partition
import fs
import katomic
import x86.hpet as hpet_clock

const nvme_class = 0x1
const nvme_subclass = 0x8
const nvme_progif = 0x2

const opcode_delete_sq = 0x0
const opcode_create_sq = 0x1
const opcode_delete_cq = 0x4
const opcode_create_cq = 0x5
const opcode_identify = 0x6
const opcode_abort = 0x8
const opcode_set_features = 0x9
const opcode_get_features = 0xa
const opcode_ns_management = 0xd
const opcode_format_cmd = 0x80

// Only one command is outstanding while reset/disable shares the controller
// lock. One I/O queue also works with the specification's default queue grant.
const nvme_io_queue_cnt = 1
const opcode_flush = u8(0)
const opcode_dataset_management = u8(9)
const command_timeout_ns = u64(30_000_000_000)
const max_transfer = u64(128 * 1024)
const command_failed = u16(0xffff)
// A timeout without RDY clearing leaves the submitted DMA buffers owned by
// the controller. Only this result requires the caller to quarantine them.
const command_dma_owned = u16(0xfffe)

@[packed]
struct NVMERegisters {
pub mut:
	cap   u64
	vs    u32
	intms u32
	intmc u32
	cc    u32
	rsvd1 u32
	csts  u32
	rsvd2 u32
	aqa   u32
	asq   u64
	acq   u64
}

@[packed]
struct NVMECommandCreateCQ {
pub mut:
	rsvd1      [5]u32
	prp1       u64
	rsvd2      u64
	cqid       u16
	qsize      u16
	cq_flags   u16
	irq_vector u16
	rsvd3      [4]u32
}

@[packed]
struct NVMECommandCreateSQ {
pub mut:
	rsvd1    [5]u32
	prp1     u64
	rsvd2    u64
	sqid     u16
	qsize    u16
	sq_flags u16
	cqid     u16
	rsvd3    [4]u32
}

@[packed]
struct NVMECommandDeleteQ {
pub mut:
	rsvd1 [9]u32
	qid   u16
	rsvd2 u16
	rsvd3 [5]u32
}

@[packed]
struct NVMECommandAbort {
pub mut:
	rsvd1 [9]u32
	sqid  u16
	cid   u16
	rsvd2 [5]u32
}

@[packed]
struct NVMECommandFeatures {
pub mut:
	nsid    u32
	rsvd1   [2]u64
	prp1    u64
	prp2    u64
	fid     u32
	dword11 u32
	rsvd2   [4]u32
}

@[packed]
struct NVMECommandIdentify {
pub mut:
	nsid  u32
	rsvd1 [2]u64
	prp1  u64
	prp2  u64
	cns   u32
	rsvd2 [5]u32
}

@[packed]
struct NVMECommandRW {
pub mut:
	nsid     u32
	rsvd1    u64
	metadata u64
	prp1     u64
	prp2     u64
	slba     u64
	length   u16
	control  u16
	dsmgmt   u32
	reftag   u32
	apptag   u16
	appmask  u16
}

@[packed]
struct NVMECommandDataset {
pub mut:
	nsid u32
	reserved1 [2]u64
	prp1 u64
	prp2 u64
	ranges u32
	attributes u32
	reserved2 [4]u32
}

@[packed]
struct NVMEDiscardRange {
mut:
	attributes u32
	blocks u32
	start u64
}

union NVMECommandPrivate {
pub mut:
	create_cq    NVMECommandCreateCQ
	create_sq    NVMECommandCreateSQ
	delete_queue NVMECommandDeleteQ
	abort        NVMECommandAbort
	features     NVMECommandFeatures
	identify     NVMECommandIdentify
	get_log      NVMECommandGetLog
	rw           NVMECommandRW
	dataset      NVMECommandDataset
}

@[packed]
struct NVMECommand {
pub mut:
	opcode  u8
	flags   u8
	cid     u16
	private NVMECommandPrivate
}

@[packed]
struct NVMECompletion {
pub mut:
	result  u32
	rsvd    u32
	sq_head u16
	sq_id   u16
	cid     u16
	status  u16
}

@[packed]
struct NVMEPowerStateID {
pub mut:
	max_power         u16
	rsvd1             u8
	flags             u8
	entry_lat         u32
	exit_lat          u32
	read_tput         u8
	read_lat          u8
	write_tput        u8
	write_lat         u8
	idle_power        u16
	idle_scale        u8
	rsvd2             u8
	active_power      u16
	active_work_scale u8
	rsvd3             [9]u8
}

@[packed]
struct NVMEControllerID {
pub mut:
	vid    u16
	ssvid  u16
	sn     [20]char
	mn     [40]char
	fr     [8]char
	rab    u8
	ieee   [3]u8
	mic    u8
	mdts   u8
	cntlid u16
	ver    u32
	rsvd1  [172]u8
	oacs   u16
	acl    u8
	aerl   u8
	frmw   u8
	lpa    u8
	elpe   u8
	npss   u8
	avscc  u8
	apsta  u8
	wctemp u16
	cctemp u16
	rsvd2  [242]u8
	sqes   u8
	cqes   u8
	rsvd3  [2]u8
	nn     u32
	oncs   u16
	fuses  u16
	fna    u8
	vwc    u8
	awun   u16
	awupf  u16
	nvscc  u8
	rsvd4  u8
	acwu   u16
	rsvd5  [2]u8
	sgls   u32
	rsvd6  [1508]u8
	psd    [32]NVMEPowerStateID
	vs     [1024]u8
}

@[packed]
struct NVMELbaf {
pub mut:
	ms u16
	ds u8
	rp u8
}

@[packed]
struct NVMENamespaceID {
pub mut:
	nsze      u64
	ncap      u64
	nuse      u64
	nsfeat    u8
	nlbaf     u8
	flbas     u8
	mc        u8
	dpc       u8
	dps       u8
	nmic      u8
	rescap    u8
	fpi       u8
	rsvd1     u8
	nawun     u16
	nawupf    u16
	nacwu     u16
	nabsn     u16
	nabo      u16
	nabspf    u16
	rsvd2     u16
	nvmcap    [2]u64
	rsvd3     [40]u8
	nguid     [16]u8
	eui64     [8]u8
	lbaf_list [16]NVMELbaf
	rsvd4     [192]u8
	vs        [3712]u8
}

struct NVMEController {
pub mut:
	l             klock.Lock
	failed        bool
	dma_quiesced  bool
	// Put down for a sleep; see power.v.
	asleep        bool
	pci_bar       pci.PCIBar
	volatile regs          &NVMERegisters
	volatile controller_id &NVMEControllerID

	queue_entries      u64
	max_page_size      u64
	min_page_size      u64
	page_size          u64
	max_transfer_shift u64
	max_prps           u64
	strides            u64
	qid_bitmap         bitmap.GenericBitmap

	admin_queue    &NVMEQueuePair
	namespace_list []&NVMENamespace

	io_queue_bitmap bitmap.GenericBitmap
	queue_list      []&NVMEQueuePair
}

struct NVMEQueuePair {
pub mut:
	qid       u64
	entry_cnt u64
	sq_head   u64
	sq_tail   u64
	cq_head   u64
	cq_tail   u64
	phase     bool
	vector    u64
	irq       u64
	admin     bool
	l         klock.Lock

	parent_controller   &NVMEController
	volatile submission_queue    &NVMECommand
	volatile completion_queue    &NVMECompletion
	volatile submission_doorbell &u32
	volatile completion_doorbell &u32

	cid_bitmap bitmap.GenericBitmap
}

struct NVMENamespace {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
	metrics resource.BlockMetrics

	max_prps u64
	nsid     u64

	parent_controller &NVMEController
	volatile identity          &NVMENamespaceID
}

__global (
	controller_list []&NVMEController
)

fn (mut dev NVMENamespace) read(_handle voidptr, buffer voidptr, loc u64, count u64) ?i64 {
	result := dev.read_tracked_inner(_handle, buffer, loc, count) or { dev.metrics.failed(); return none }
	if result > 0 { dev.metrics.completed(u64(result), false) }
	return result
}
fn (mut dev NVMENamespace) read_tracked_inner(_handle voidptr, buffer voidptr, loc u64, count u64) ?i64 {
	return dev.transfer(buffer, loc, count, false)
}

fn (mut dev NVMENamespace) write(_handle voidptr, buffer voidptr, loc u64, count u64) ?i64 {
	if !fence.before_write() { errno.set(errno.eio); dev.metrics.failed(); return none }
	result := dev.write_tracked_inner(_handle, buffer, loc, count) or { dev.metrics.failed(); return none }
	if result > 0 { dev.metrics.completed(u64(result), true) }
	return result
}
fn (mut dev NVMENamespace) write_tracked_inner(_handle voidptr, buffer voidptr, loc u64, count u64) ?i64 {
	return dev.transfer(buffer, loc, count, true)
}

fn (mut dev NVMENamespace) transfer(buffer voidptr, loc u64, count u64, write bool) ?i64 {
	if loc % dev.stat.blksize != 0 || count % dev.stat.blksize != 0
		|| loc > u64(dev.stat.size) || count > u64(dev.stat.size) - loc {
		errno.set(errno.eio)
		return none
	}
	if count == 0 { return 0 }
	if dev.max_prps == 0 {
		errno.set(errno.eio)
		return none
	}
	most := if dev.max_prps * page_size < max_transfer {
		dev.max_prps * page_size
	} else {
		max_transfer
	}
	pages := lib.div_roundup(if count < most { count } else { most }, page_size)
	physical := memory.pmm_alloc_nozero_fallible(pages)
	if physical == unsafe { nil } {
		errno.set(errno.enomem)
		return none
	}
	bounce := voidptr(u64(physical) + higher_half)
	mut owned := false
	defer {
		// A failed reset cannot prove that DMA has stopped. The permanent
		// offline state prevents new submissions; retain this one allocation.
		if !owned { memory.pmm_free(physical, pages) }
	}
	for done := u64(0); done < count; {
		chunk := if count - done < most { count - done } else { most }
		caller := voidptr(u64(buffer) + done)
		if write { unsafe { C.memcpy(bounce, caller, chunk) } }
		// A write that waited, for a controller put down for a sleep, while
		// an image of memory was taken is held like one that begins now.
		// Not as surely as on SATA, where this is asked with the disk's
		// lock held: the command is queued further down, under the
		// controller's.
		if write && fence.closed() {
			if fence.mine() {
				errno.set(errno.eio)
				return none
			}
			fence.wait_open()
		}
		result := dev.rw_lba(bounce, (loc + done) / u64(dev.stat.blksize), chunk / u64(dev.stat.blksize), write)
		if result != 0 {
			owned = result == -2
			errno.set(errno.eio)
			return none
		}
		proc.account_disk_transfer(chunk, write)
		if !write { unsafe { C.memcpy(caller, bounce, chunk) } }
		proc.account_disk_io(dev.stat.rdev, chunk, write)
		done += chunk
	}
	return i64(count)
}

fn (mut dev NVMENamespace) sync(_handle voidptr) ? {
	mut completed := false
	defer { if completed { dev.metrics.flushed() } else { dev.metrics.failed() } }
	// Submission copies the command into the permanent queue. Keep the
	// borrowed command on this stack even if disable cannot stop payload DMA.
	mut command := unsafe { &NVMECommand(C.vinix_stack_alloc(sizeof(NVMECommand))) }
	unsafe { *command = NVMECommand{} }
	command.opcode = opcode_flush
	unsafe { command.private.rw.nsid = u32(dev.nsid) }
	// All requests share the controller lock, so the barrier cannot pass a
	// submitted write. FLUSH applies to the namespace, irrespective of queue.
	if dev.parent_controller.queue_list[0].send_cmd_and_wait(mut command, -1) != 0 {
		errno.set(errno.eio)
		return none
	}
	completed = true
}

fn (mut dev NVMENamespace) discard(offset u64, bytes u64) ? {
	mut completed := false
	defer { if !completed { dev.metrics.failed() } }
	if !fence.before_write() { errno.set(errno.eio); return none }
	if !resource.discard_range_valid(u64(dev.stat.size), u64(dev.stat.blksize), offset, bytes) {
		errno.set(errno.einval); return none
	}
	if dev.parent_controller.failed { errno.set(errno.enodev); return none }
	if dev.parent_controller.controller_id.oncs & (1 << 2) == 0 {
		errno.set(errno.eopnotsupp); return none
	}
	physical := memory.pmm_alloc_nozero_fallible(1) @[freed]
	if physical == unsafe { nil } { errno.set(errno.enomem); return none }
	mut owned := false
	defer { if !owned { memory.pmm_free(physical, 1) } }
	mut range := unsafe { &NVMEDiscardRange(u64(physical) + higher_half) }
	mut command := unsafe { &NVMECommand(C.vinix_stack_alloc(sizeof(NVMECommand))) }
	mut start := offset / u64(dev.stat.blksize)
	mut left := bytes / u64(dev.stat.blksize)
	for left != 0 {
		blocks := if left < u32(-1) { u32(left) } else { u32(-1) }
		range.attributes = 0
		range.blocks = blocks
		range.start = start
		unsafe {
			*command = NVMECommand{}
			command.opcode = opcode_dataset_management
			command.private.dataset.nsid = u32(dev.nsid)
			command.private.dataset.prp1 = u64(physical)
			command.private.dataset.ranges = 0 // One range, zero based.
			command.private.dataset.attributes = 1 << 2 // Deallocate.
		}
		status := dev.parent_controller.queue_list[0].send_cmd_and_wait(mut command, -1)
		if status != 0 {
			owned = status == command_dma_owned
			errno.set(errno.eio); return none
		}
		start += blocks
		left -= blocks
	}
	completed = true
}

fn (mut dev NVMENamespace) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut dev NVMENamespace) unref(_handle voidptr) ? {
	katomic.dec(mut &dev.refcount)
}

fn (mut dev NVMENamespace) link(_handle voidptr) ? {
	katomic.inc(mut &dev.stat.nlink)
}

fn (mut dev NVMENamespace) unlink(_handle voidptr) ? {
	katomic.dec(mut &dev.stat.nlink)
}

fn (mut dev NVMENamespace) grow(_handle voidptr, _new_size u64) ? {
	return none
}

fn (mut dev NVMENamespace) block_status() resource.BlockStatus {
	dev.l.acquire()
	defer { dev.l.release() }
	mut flags := resource.block_flush
	if dev.parent_controller.failed { flags |= resource.block_offline }
	if dev.parent_controller.controller_id.oncs & (1 << 2) != 0 { flags |= resource.block_discard }
	return dev.metrics.snapshot(u64(dev.stat.size), u64(dev.stat.blksize), flags, dev.block_identity())
}

fn (dev &NVMENamespace) block_identity() resource.BlockIdentity {
	return resource.BlockIdentity{is_block: true, disk_id: dev.stat.rdev, length: u64(dev.stat.size)}
}

fn (mut dev NVMENamespace) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return 0
}

pub fn (mut namespace NVMENamespace) initialise(mut parent_controller NVMEController, nsid u64) int {
	unsafe {
		namespace.parent_controller = parent_controller
	}
	namespace.nsid = nsid
	namespace.identity = unsafe {
		&NVMENamespaceID(u64(memory.pmm_alloc(lib.div_roundup[u64](sizeof(NVMENamespaceID), page_size))) +
			higher_half)
	}

	mut new_command := NVMECommand{}

	unsafe {
		new_command.opcode = opcode_identify
		new_command.private.identify.cns = 0
		new_command.private.identify.nsid = u32(nsid)
		new_command.private.identify.prp1 = u64(namespace.identity) - higher_half
	}
	if parent_controller.admin_queue.send_cmd_and_wait(mut new_command, -1) != 0 {
		C.kprintf(c'nvme: nsid %llx : unable to read namespace identity\n', u64(nsid))
		return -1
	}

	format := namespace.identity.flbas & 0xf
	if format > namespace.identity.nlbaf || namespace.identity.lbaf_list[format].ms != 0
		|| namespace.identity.lbaf_list[format].ds < 9
		|| namespace.identity.lbaf_list[format].ds > 12
		|| namespace.identity.nsze == 0
		|| namespace.identity.nsze > u64(0x7fff_ffff_ffff_ffff) >> namespace.identity.lbaf_list[format].ds {
		return -1
	}
	namespace.max_prps = calculate_max_prps(mut parent_controller, namespace.identity)
	namespace.stat.blocks = namespace.identity.nsze
	namespace.stat.blksize = 1 << u64(namespace.identity.lbaf_list[format].ds)
	namespace.stat.size = namespace.stat.blocks * namespace.stat.blksize
	namespace.stat.rdev = resource.create_dev_id()
	namespace.stat.mode = 0o644 | stat.ifblk

	return 0
}

fn calculate_max_prps(mut c NVMEController, _identity &NVMENamespaceID) u64 {
	shift := 12 + ((c.regs.cap >> 48) & 0xf)
	limit_shift := shift + c.controller_id.mdts
	bytes := if c.controller_id.mdts == 0 || limit_shift >= 17 {
		max_transfer
	} else {
		u64(1) << limit_shift
	}
	return bytes / page_size
}

pub fn (mut pair NVMEQueuePair) initialise(mut parent_controller NVMEController, vector u64, irq u64, admin bool) int {
	qid := parent_controller.qid_bitmap.alloc() or {
		print('nvme: no available qid\n')
		return -1
	}

	if qid != 0 && admin == true {
		print('nvme: cannot create admin queue with non-zero qid\n')
		return -1
	}

	pair.parent_controller = unsafe { parent_controller }
	pair.qid = qid
	pair.phase = true
	pair.vector = vector
	pair.irq = irq
	pair.admin = admin
	pair.entry_cnt = parent_controller.queue_entries

	pair.submission_queue = unsafe {
		&NVMECommand(u64(memory.pmm_alloc(lib.div_roundup[u64](pair.entry_cnt * sizeof(NVMECommand), page_size))) +
			higher_half)
	}
	pair.completion_queue = unsafe {
		&NVMECompletion(u64(memory.pmm_alloc(lib.div_roundup[u64](pair.entry_cnt * sizeof(NVMECompletion), page_size))) +
			higher_half)
	}

	submission_offset := page_size + 2 * qid * (4 << parent_controller.strides)
	pair.submission_doorbell = unsafe { &u32(u64(parent_controller.regs) + submission_offset) }

	completion_offset := page_size + ((2 * qid + 1) * (4 << parent_controller.strides))
	pair.completion_doorbell = unsafe { &u32(u64(parent_controller.regs) + completion_offset) }

	pair.cid_bitmap.initialise(pair.entry_cnt)

	if admin == true {
		return 0
	}

	mut create_cq_command := NVMECommand{}

	unsafe {
		create_cq_command.opcode = opcode_create_cq
		create_cq_command.private.create_cq.prp1 = u64(pair.completion_queue) - higher_half
		create_cq_command.private.create_cq.cqid = u16(qid)
		create_cq_command.private.create_cq.qsize = u16(pair.entry_cnt - 1)
		create_cq_command.private.create_cq.irq_vector = u16(irq)
		// This driver polls completions; no interrupt handler owns the queue.
		create_cq_command.private.create_cq.cq_flags = 1 << 0
	}
	if parent_controller.admin_queue.send_cmd_and_wait(mut create_cq_command, -1) != 0 {
		print('nvme: unable to create completion queue\n')
		return -1
	}

	mut create_sq_command := NVMECommand{}

	unsafe {
		create_sq_command.opcode = opcode_create_sq
		create_sq_command.private.create_sq.prp1 = u64(pair.submission_queue) - higher_half
		create_sq_command.private.create_sq.cqid = u16(qid)
		create_sq_command.private.create_sq.sqid = u16(qid)
		create_sq_command.private.create_sq.qsize = u16(pair.entry_cnt - 1)
		create_sq_command.private.create_sq.sq_flags = (1 << 0) | (1 << 1)
	}
	if parent_controller.admin_queue.send_cmd_and_wait(mut create_sq_command, -1) != 0 {
		print('nvme: unable to create submission queue\n')
		return -1
	}

	C.kprintf(c'nvme: created io queue pair with qid %llx\n', u64(qid))

	return 0
}

pub fn (mut pair NVMEQueuePair) send_cmd(mut submission NVMECommand, cid int) int {
	mut command_cid := cid

	if cid == -1 {
		command_cid = int(pair.cid_bitmap.alloc() or {
			C.kprintf(c'nvme: no available cids on qid %llx\n', u64(pair.qid))
			return -1
		})
	}

	submission.cid = u16(command_cid)

	unsafe {
		pair.submission_queue[pair.sq_tail] = submission
	}
	katomic.sync()
	pair.sq_tail++

	if pair.sq_tail == pair.entry_cnt {
		pair.sq_tail = 0
	}

	unsafe {
		katomic.sync()
		*pair.submission_doorbell = u32(pair.sq_tail)
	}
	return 0
}

// The caller holds the controller lock. Stop the controller on timeout before
// returning its DMA buffers. RDY=0 is the ownership boundary; an unresponsive
// controller stays offline and the caller must retain its submitted buffers.
fn (mut c NVMEController) fail_controller() u16 {
	c.failed = true
	mut volatile regs := c.regs
	regs.intms = u32(-1)
	regs.cc &= ~u32(1)
	deadline := hpet_clock.nanoseconds() + c.ready_timeout_ns()
	for regs.csts & 1 != 0 {
		if hpet_clock.nanoseconds() >= deadline {
			c.dma_quiesced = false
			C.kprintf(c'nvme: controller offline with DMA buffers retained\n')
			return command_dma_owned
		}
		klock.spin_hint()
	}
	c.dma_quiesced = true
	C.kprintf(c'nvme: controller disabled after command failure\n')
	return command_failed
}

fn (c &NVMEController) ready_timeout_ns() u64 {
	// CAP.TO is a number of 500 ms units. Retain a 500 ms minimum for
	// devices reporting zero, instead of accepting an unbounded reset.
	mut volatile regs := c.regs
	units := (regs.cap >> 24) & 0xff
	return (if units == 0 { u64(1) } else { units }) * 500_000_000
}

pub fn (mut pair NVMEQueuePair) send_cmd_and_wait(mut submission NVMECommand, cid int) u16 {
	mut controller := pair.parent_controller
	// Serialize every queue, including admin, through reset/disable. A queue
	// lock alone allows a timed-out controller to DMA into another caller's
	// already released buffers while that caller believes its command failed.
	// A controller put down for a sleep takes nothing until it is back; it is
	// looked at again with the lock, since a sleep may begin in between.
	for {
		controller.wait_awake()
		controller.l.acquire()
		if !controller.asleep { break }
		controller.l.release()
	}
	defer { controller.l.release() }
	return pair.exchange(mut submission, cid)
}

// One command and its completion. The caller holds the controller lock.
fn (mut pair NVMEQueuePair) exchange(mut submission NVMECommand, cid int) u16 {
	mut controller := pair.parent_controller
	if controller.failed { return command_failed }
	if pair.send_cmd(mut submission, cid) == -1 { return command_failed }
	deadline := hpet_clock.nanoseconds() + command_timeout_ns
	mut volatile regs := controller.regs
	mut volatile completions := pair.completion_queue
	for {
		status := unsafe { completions[pair.cq_head].status }
		if (status & 1 != 0) == pair.phase { break }
		if regs.csts & 2 != 0 || hpet_clock.nanoseconds() >= deadline {
			return controller.fail_controller()
		}
		klock.spin_hint()
	}
	katomic.sync()
	completion := unsafe { completions[pair.cq_head] }
	if completion.cid != submission.cid || completion.sq_id != pair.qid {
		C.kprintf(c'nvme: unexpected completion on qid %llu\n', u64(pair.qid))
		return controller.fail_controller()
	}
	pair.sq_head = completion.sq_head
	pair.cq_head++
	if pair.cq_head == pair.entry_cnt {
		pair.cq_head = 0
		pair.phase = !pair.phase
	}
	pair.cid_bitmap.free_entry(u64(submission.cid))
	katomic.sync()
	unsafe { *pair.completion_doorbell = u32(pair.cq_head) }
	// Consume failed completions too, and remove the phase bit so callers
	// consistently test for zero rather than mistaking an I/O error for success.
	return completion.status >> 1
}

pub fn (mut ns NVMENamespace) rw_lba(buffer voidptr, start u64, cnt u64, rw bool) int {
	bytes := cnt * u64(ns.stat.blksize)
	if cnt == 0 || cnt > 65536 || bytes > ns.max_prps * page_size || bytes > max_transfer {
		return -1
	}
	// Only PRPs reference DMA memory; the command itself is copied by send_cmd.
	mut new_command := unsafe { &NVMECommand(C.vinix_stack_alloc(sizeof(NVMECommand))) }
	unsafe { *new_command = NVMECommand{} }
	mut prp_list := voidptr(unsafe { nil })
	if bytes > page_size * 2 {
		// One PRP list page, without chaining, is enough for our bounded
		// 128 KiB transfers. The first page goes in PRP1, the rest here.
		prp_list = memory.pmm_alloc_nozero_fallible(1)
		if prp_list == unsafe { nil } { return -1 }
		mut entries := unsafe { &u64(u64(prp_list) + higher_half) }
		prp_count := lib.div_roundup(bytes, page_size) - 1
		for i := u64(0); i < prp_count; i++ {
			unsafe { entries[i] = u64(buffer) - higher_half + (i + 1) * page_size }
		}
		unsafe { new_command.private.rw.prp2 = u64(prp_list) }
	} else if bytes > page_size {
		unsafe { new_command.private.rw.prp2 = u64(buffer) - higher_half + page_size }
	}
	new_command.opcode = if rw { u8(1) } else { u8(2) }
	unsafe {
		new_command.private.rw.nsid = u32(ns.nsid)
		new_command.private.rw.slba = start
		new_command.private.rw.length = u16(cnt - 1)
		new_command.private.rw.prp1 = u64(buffer) - higher_half
	}
	result := ns.parent_controller.queue_list[0].send_cmd_and_wait(mut new_command, -1)
	if prp_list != unsafe { nil } && result != command_dma_owned {
		memory.pmm_free(prp_list, 1)
	}
	if result == command_dma_owned { return -2 }
	return if result == 0 { 0 } else { -1 }
}

fn (mut c NVMEController) get_controller_id() int {
	c.controller_id = unsafe {
		&NVMEControllerID(u64(memory.pmm_alloc(lib.div_roundup[u64](sizeof(NVMEControllerID), page_size))) +
			higher_half)
	}

	mut new_command := NVMECommand{}

	unsafe {
		new_command.opcode = opcode_identify
		new_command.private.identify.cns = 1
		new_command.private.identify.prp1 = u64(c.controller_id) - higher_half
	}
	if c.admin_queue.send_cmd_and_wait(mut new_command, -1) != 0 {
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
	if !c.pci_bar.is_mmio || c.pci_bar.size < page_size + 16 { return -1 }
	registers := map_registers(c.pci_bar.base, page_size)
	if registers == 0 { return -1 }
	c.regs = unsafe { &NVMERegisters(registers) }

	major_version := (c.regs.vs >> 16) & 0xffff
	minor_version := (c.regs.vs >> 8) & 0xff
	tertiary_version := c.regs.vs & 0xff

	C.kprintf(c'nvme: Version Detected [%llu:%llu:%llu]\n', u64(major_version), u64(minor_version),
		u64(tertiary_version))

	if (u64(c.regs.cap) & (u64(1) << 37)) == 0 {
		print('nvme: NVME command set not supported\n')
		return -1
	}

	c.max_page_size = lib.power(2, 12 + ((c.regs.cap >> 52) & 0xf))
	c.min_page_size = lib.power(2, 12 + ((c.regs.cap >> 48) & 0xf))
	if c.min_page_size > page_size || c.max_page_size < page_size { return -1 }

	if (c.regs.cc & (1 << 0)) != 0 {
		c.regs.cc = c.regs.cc & ~(1 << 0) // disable controller
	}

	mut volatile regs := c.regs
	deadline := hpet_clock.nanoseconds() + c.ready_timeout_ns()
	for regs.csts & 1 != 0 {
		if hpet_clock.nanoseconds() >= deadline { return -1 }
		klock.spin_hint()
	}

	// CAP.MQES is zero-based; AQA permits at most 4096 admin entries.
	c.queue_entries = (c.regs.cap & 0xffff) + 1
	if c.queue_entries > 256 { c.queue_entries = 256 }
	if c.queue_entries < 2 { return -1 }
	c.strides = (c.regs.cap >> 32) & 0xf
	// Map the admin and single I/O queue's doorbells as well as registers.
	// A 64-bit BAR can lie outside the direct map's initial 4 GiB span.
	if !map_doorbells(c.pci_bar.base, c.pci_bar.size, c.strides) { return -1 }

	c.qid_bitmap.initialise(0xffff)

	c.admin_queue = &NVMEQueuePair{
		parent_controller:   unsafe { nil }
		submission_queue:    unsafe { nil }
		completion_queue:    unsafe { nil }
		completion_doorbell: unsafe { nil }
		submission_doorbell: unsafe { nil }
	}

	if c.admin_queue.initialise(mut c, 0, 0, true) != 0 {
		print('nvme: failed to create an admin queue\n')
		return -1
	}

	c.regs.aqa = u32((c.queue_entries - 1) << 16 | (c.queue_entries - 1))
	c.regs.asq = u64(c.admin_queue.submission_queue) - higher_half
	c.regs.acq = u64(c.admin_queue.completion_queue) - higher_half

	c.regs.cc = (0 << 4) | // nvme command set
	(0 << 11) | // ams = round robin
	(0 << 14) | // no shutdown notifications
	(6 << 16) | // io submission queue entry size 64 bytes
	(4 << 20) | // io completion queue entry size 16 bytes
	(1 << 0) // enable
	ready_deadline := hpet_clock.nanoseconds() + c.ready_timeout_ns()
	for {
		if regs.csts & (1 << 0) != 0 {
			break
		} else if regs.csts & (1 << 1) != 0 || hpet_clock.nanoseconds() >= ready_deadline {
			print('nvme: controller fatal status\n')
			return -1
		}
	}

	print('nvme: controller restart\n')

	if c.get_controller_id() == -1 {
		print('nvme: fatal error\n')
		return -1
	}

	C.kprintf(c'nvme: vendor ID: %llx\n', u64(c.controller_id.vid))
	C.kprintf(c'nvme: subsystem vendor ID: %llu\n', u64(c.controller_id.ssvid))

	nsid_list := unsafe {
		&u32(u64(memory.pmm_alloc(lib.div_roundup[u64](4096, page_size))) +
			higher_half)
	}

	mut new_command := NVMECommand{}

	unsafe {
		new_command.opcode = opcode_identify
		new_command.private.identify.cns = 2
		new_command.private.identify.prp1 = u64(nsid_list) - higher_half
	}
	if c.admin_queue.send_cmd_and_wait(mut new_command, -1) != 0 {
		print('nvme: unable to read nsid list\n')
		return -1
	}

	c.io_queue_bitmap.initialise(nvme_io_queue_cnt)

	for i := 0; i < nvme_io_queue_cnt; i++ {
		mut new_io_queue := &NVMEQueuePair{
			parent_controller:   unsafe { nil }
			submission_queue:    unsafe { nil }
			completion_queue:    unsafe { nil }
			submission_doorbell: unsafe { nil }
			completion_doorbell: unsafe { nil }
		}

		if new_io_queue.initialise(mut c, 0, 0, false) != 0 { return -1 }

		c.queue_list << new_io_queue
	}

	nsid_count := if c.controller_id.nn < 1024 { c.controller_id.nn } else { u32(1024) }
	for i := u64(0); i < nsid_count; i++ {
		if unsafe { nsid_list[i] != 0 } {
			mut new_namespace := &NVMENamespace{
				parent_controller: unsafe { nil }
				identity:          unsafe { nil }
			}

			if new_namespace.initialise(mut c, unsafe { nsid_list[i] }) != 0 {
				print('nvme: fatel error\n')
				return -1
			}

			C.kprintf(c'nvme: namespace id: %llx\n', u64(new_namespace.nsid))
			C.kprintf(c'nvme: lba cnt: %llx\n', u64(new_namespace.stat.blocks))
			C.kprintf(c'nvme: lba size: %llx\n', u64(new_namespace.stat.blksize))
			C.kprintf(c'nvme: max prps: %llx\n', u64(new_namespace.max_prps))

			// The device node keeps the name; the partitions' names are made
			// from the prefix, which goes afterwards.
			mut name := lib.new_text(16)
			name.add('nvme')
			name.add_decimal(controller_list.len)
			name.add_byte(`n`)
			name.add_unsigned(i)
			fs.devtmpfs_add_device(new_namespace, name.str())
			mut prefix_text := lib.new_text(16)
			prefix_text.add('nvme')
			prefix_text.add_decimal(controller_list.len)
			prefix_text.add_byte(`n`)
			prefix_text.add_unsigned(i)
			prefix_text.add_byte(`p`)
			prefix := prefix_text.str()
			partition.scan_partitions(mut new_namespace, prefix)
			unsafe { prefix.free() }

			c.namespace_list << new_namespace
		}
	}

	memory.pmm_free(voidptr(u64(nsid_list) - higher_half), 1)
	return 0
}

fn controller_matches(dev &devcore.Device) bool {
	return dev.is_pci_class(nvme_class, nvme_subclass, nvme_progif)
}

fn controller_probe(mut dev devcore.Device) bool {
	mut nvme_device := &NVMEController{
		regs:          unsafe { nil }
		controller_id: unsafe { nil }
		admin_queue:   unsafe { nil }
	}
	// The controller is told physical addresses of this driver's choosing --
	// its queues, and a request's pages as they come; behind an IOMMU it has
	// to be allowed all of memory to follow them.
	dma.allow_all(mut dev)
	if nvme_device.initialise(dev.pci) == -1 {
		// A controller that did not come up may still own the memory it was
		// given; the record is kept with it. See fail_controller().
		return false
	}
	dev.driver_data = voidptr(nvme_device)
	controller_list << nvme_device
	return true
}

// Register with the device core, which hands over every NVMe controller the
// machine has.
pub fn initialise() {
	devcore.register_driver(devcore.Driver{
		name:     'nvme'
		bus:      .pci
		matches:  controller_matches
		probe:    controller_probe
		suspend:  controller_suspend
		resume:   controller_resume
		shutdown: controller_shutdown
	}) or { return }
}
