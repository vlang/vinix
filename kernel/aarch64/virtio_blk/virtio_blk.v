// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module virtio_blk

// A deliberately small legacy VirtIO-MMIO block driver for QEMU's ARM `virt`
// machine.  The boot volume is a FAT image for UEFI, so a separate ext2
// volume is attached by scripts/run-aarch64.sh when --persist is requested.
import aarch64.cpu
import aarch64.uart
import aarch64.timer
import errno
import event.eventstruct
import fs
import fs.ext2
import klock
import lib
import limine
import memory
import proc
import resource
import stat

const reg_magic = u64(0x000)
const reg_device_id = u64(0x008)
const reg_host_features = u64(0x010)
const reg_guest_features = u64(0x020)
const reg_guest_page_size = u64(0x028)
const reg_queue_sel = u64(0x030)
const reg_queue_num_max = u64(0x034)
const reg_queue_num = u64(0x038)
const reg_queue_align = u64(0x03c)
const reg_queue_pfn = u64(0x040)
const reg_queue_notify = u64(0x050)
const reg_interrupt_status = u64(0x060)
const reg_interrupt_ack = u64(0x064)
const reg_status = u64(0x070)
const reg_config = u64(0x100)

const virtio_magic = u32(0x74726976)
const virtio_id_block = u32(2)
const status_acknowledge = u32(1)
const status_driver = u32(2)
const status_driver_ok = u32(4)
const status_failed = u32(128)
const descriptor_next = u16(1)
const descriptor_write = u16(2)
const feature_read_only = u32(1 << 5)
const feature_flush = u32(1 << 9)
const request_flush = u32(4)

const mmio_base = u64(0x0a000000)
const mmio_slot_size = u64(0x200)
const mmio_slot_count = u64(32)
const queue_align = u64(4096)
const max_transfer = u64(128 * 1024)
// A loaded host can pause the VM for several seconds while large Steam and
// browser libraries fault in from the disk image. Keep an outstanding request
// alive across those pauses instead of reporting a spurious I/O failure.
const request_timeout_ns = u64(30_000_000_000)

@[packed]
struct RequestHeader {
mut:
	type_    u32
	reserved u32
	sector   u64
}

struct VirtioBlockDevice {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool

	base            u64
	hhdm            u64
	queue_size      u16
	desc            u64
	avail           u64
	used            u64
	last_used       u16
	next_available  u16
	request_phys    u64
	request_virt    u64
	data_phys       u64
	data_virt       u64
	ready           bool
	read_only       bool
	flush_supported bool
	name            string
}

__global (
	devices []&VirtioBlockDevice
)

fn mmio_r32(address u64) u32 {
	value := unsafe { *&u32(address) }
	cpu.dmb_ish()
	return value
}

fn mmio_w32(address u64, value u32) {
	cpu.dmb_ish()
	unsafe { *&u32(address) = value }
}

fn align_up(value u64, alignment u64) u64 {
	return (value + alignment - 1) & ~(alignment - 1)
}

fn write_descriptor(device &VirtioBlockDevice, index u16, address u64, length u32, flags u16, next u16) {
	descriptor := device.desc + u64(index) * 16
	unsafe {
		*&u64(descriptor) = address
		*&u32(descriptor + 8) = length
		*&u16(descriptor + 12) = flags
		*&u16(descriptor + 14) = next
	}
}

fn setup_queue(mut device VirtioBlockDevice) bool {
	mmio_w32(device.base + reg_queue_sel, 0)
	maximum := mmio_r32(device.base + reg_queue_num_max)
	if maximum < 3 {
		return false
	}
	device.queue_size = if maximum < 8 { u16(maximum) } else { u16(8) }
	mmio_w32(device.base + reg_queue_num, device.queue_size)
	mmio_w32(device.base + reg_queue_align, u32(queue_align))

	avail_offset := u64(device.queue_size) * 16
	used_offset := align_up(avail_offset + 4 + 2 * u64(device.queue_size) + 2, queue_align)
	queue_bytes := used_offset + 4 + 8 * u64(device.queue_size) + 2
	queue_pages := (queue_bytes + memory.page_size - 1) / memory.page_size
	queue_phys := u64(memory.pmm_alloc(queue_pages))
	if queue_phys == 0 {
		return false
	}
	device.desc = queue_phys + device.hhdm
	device.avail = device.desc + avail_offset
	device.used = device.desc + used_offset
	unsafe { C.memset(voidptr(device.desc), 0, queue_pages * memory.page_size) }

	request_phys := u64(memory.pmm_alloc(1))
	data_phys := u64(memory.pmm_alloc(max_transfer / memory.page_size))
	if request_phys == 0 || data_phys == 0 {
		return false
	}
	device.request_phys = request_phys
	device.request_virt = request_phys + device.hhdm
	device.data_phys = data_phys
	device.data_virt = data_phys + device.hhdm
	unsafe {
		C.memset(voidptr(device.request_virt), 0, 4096)
		C.memset(voidptr(device.data_virt), 0, max_transfer)
	}
	cpu.dmb_ish()
	mmio_w32(device.base + reg_queue_pfn, u32(queue_phys / memory.page_size))
	return true
}

// Wait for the device to hand one buffer back, and consume it. Requests are
// polled rather than waited on, and `last_used` counts what this driver has
// collected; the caller submits at most one at a time.
fn (mut device VirtioBlockDevice) collect_one() bool {
	deadline := timer.get_ns() + request_timeout_ns
	mut spins := u64(0)
	for {
		cpu.dmb_ish()
		if unsafe { *&u16(device.used + 2) } != device.last_used {
			break
		}
		spins++
		if spins > 1_000_000_000 || timer.get_ns() >= deadline {
			uart.puts(c'virtio-blk: request timed out\n')
			return false
		}
	}
	device.last_used++
	cpu.dmb_ish()
	interrupts := mmio_r32(device.base + reg_interrupt_status)
	if interrupts != 0 {
		mmio_w32(device.base + reg_interrupt_ack, interrupts)
	}
	return true
}

// `read` controls the direction from the device's perspective: reads from the
// disk make the data descriptor writable by the device.
fn (mut device VirtioBlockDevice) transfer(buffer voidptr, sector u64, count u64, read bool) bool {
	if !device.ready || count == 0 || count > max_transfer || count % 512 != 0 {
		return false
	}
	device.l.acquire()
	defer {
		device.l.release()
	}

	// Every transfer shares the one request and data buffer, so a request that
	// timed out still belongs to the device: it may yet complete and write into
	// them. Collect it before reusing them, or the next completion is mistaken
	// for this request's and the data read back is whatever the abandoned one
	// left there. That is how a loaded host turned a slow disk into corrupted
	// inode tables and executable pages.
	for device.last_used != device.next_available {
		if !device.collect_one() {
			return false
		}
	}

	if !read {
		unsafe { C.memcpy(voidptr(device.data_virt), buffer, count) }
	}
	mut header := unsafe { &RequestHeader(device.request_virt) }
	header.type_ = if read { u32(0) } else { u32(1) }
	header.reserved = 0
	header.sector = sector
	unsafe { *&u8(device.request_virt + sizeof(RequestHeader)) = 0xff }

	write_descriptor(device, 0, device.request_phys, sizeof(RequestHeader), descriptor_next, 1)
	data_flags := descriptor_next | if read { descriptor_write } else { u16(0) }
	write_descriptor(device, 1, device.data_phys, u32(count), data_flags, 2)
	write_descriptor(device, 2, device.request_phys + sizeof(RequestHeader), 1, descriptor_write, 0)
	position := u64(device.next_available % device.queue_size)
	unsafe { *&u16(device.avail + 4 + position * 2) = 0 }
	device.next_available++
	cpu.dmb_ish()
	unsafe { *&u16(device.avail + 2) = device.next_available }
	mmio_w32(device.base + reg_queue_notify, 0)

	// A timeout leaves the request outstanding on purpose. The loop above
	// reclaims it before the buffers are used again.
	if !device.collect_one() {
		return false
	}
	if unsafe { *&u8(device.request_virt + sizeof(RequestHeader)) } != 0 {
		return false
	}
	if read {
		unsafe { C.memcpy(buffer, voidptr(device.data_virt), count) }
	}
	proc.account_disk_io(device.stat.rdev, count, !read)
	return true
}

fn (mut device VirtioBlockDevice) sync(_handle voidptr) ? {
	device.l.acquire()
	defer { device.l.release() }
	if !device.ready {
		errno.set(errno.eio)
		return none
	}
	// A device that did not offer FLUSH may complete volatile writes. The
	// specification does not guarantee persistence in that case.
	if !device.flush_supported {
		errno.set(errno.eio)
		return none
	}
	for device.last_used != device.next_available {
		if !device.collect_one() {
			errno.set(errno.eio)
			return none
		}
	}
	mut header := unsafe { &RequestHeader(device.request_virt) }
	header.type_ = request_flush
	header.reserved = 0
	header.sector = 0
	unsafe { *&u8(device.request_virt + sizeof(RequestHeader)) = 0xff }
	// FLUSH has only a header and status, with no data descriptor.
	write_descriptor(device, 0, device.request_phys, sizeof(RequestHeader), descriptor_next, 2)
	write_descriptor(device, 2, device.request_phys + sizeof(RequestHeader), 1, descriptor_write, 0)
	position := u64(device.next_available % device.queue_size)
	unsafe { *&u16(device.avail + 4 + position * 2) = 0 }
	device.next_available++
	cpu.dmb_ish()
	unsafe { *&u16(device.avail + 2) = device.next_available }
	mmio_w32(device.base + reg_queue_notify, 0)
	// A timeout keeps these permanent buffers outstanding; the next caller
	// collects the late completion before overwriting either descriptor.
	if !device.collect_one() || unsafe { *&u8(device.request_virt + sizeof(RequestHeader)) } != 0 {
		errno.set(errno.eio)
		return none
	}
}

fn (mut device VirtioBlockDevice) read(_handle voidptr, buffer voidptr, loc u64, count u64) ?i64 {
	if loc % 512 != 0 || count % 512 != 0 || loc + count > u64(device.stat.size) {
		errno.set(errno.eio)
		return none
	}
	mut done := u64(0)
	for done < count {
		chunk := if count - done < max_transfer { count - done } else { max_transfer }
		if !device.transfer(voidptr(u64(buffer) + done), (loc + done) / 512, chunk, true) {
			errno.set(errno.eio)
			return none
		}
		proc.account_disk_transfer(chunk, false)
		done += chunk
	}
	return i64(count)
}

fn (mut device VirtioBlockDevice) write(_handle voidptr, buffer voidptr, loc u64, count u64) ?i64 {
	if device.read_only {
		errno.set(errno.erofs)
		return none
	}
	if loc % 512 != 0 || count % 512 != 0 || loc + count > u64(device.stat.size) {
		errno.set(errno.eio)
		return none
	}
	mut done := u64(0)
	for done < count {
		chunk := if count - done < max_transfer { count - done } else { max_transfer }
		if !device.transfer(voidptr(u64(buffer) + done), (loc + done) / 512, chunk, false) {
			errno.set(errno.eio)
			return none
		}
		proc.account_disk_transfer(chunk, true)
		done += chunk
	}
	return i64(count)
}

fn (device &VirtioBlockDevice) block_identity() resource.BlockIdentity {
	return resource.BlockIdentity{is_block: true, disk_id: device.stat.rdev, length: u64(device.stat.size)}
}

fn (device &VirtioBlockDevice) read_only_backend() bool {
	return device.read_only
}

fn (mut device VirtioBlockDevice) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut device VirtioBlockDevice) unref(_handle voidptr) ? {
	device.refcount--
}

fn (mut device VirtioBlockDevice) link(_handle voidptr) ? {
	device.stat.nlink++
}

fn (mut device VirtioBlockDevice) unlink(_handle voidptr) ? {
	device.stat.nlink--
}

fn (mut device VirtioBlockDevice) grow(_handle voidptr, _new_size u64) ? {
	errno.set(errno.eio)
	return none
}

fn (mut device VirtioBlockDevice) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return 0
}

pub fn initialise(hhdm u64) {
	mut index := 0
	for slot := u64(0); slot < mmio_slot_count; slot++ {
		base := hhdm + mmio_base + slot * mmio_slot_size
		if mmio_r32(base + reg_magic) != virtio_magic || mmio_r32(base + reg_device_id) != virtio_id_block {
			continue
		}
		mut name := lib.new_text(3)
		name.add('vd')
		name.add_byte(u8(`a` + index))
		mut device := &VirtioBlockDevice{
			base: base
			hhdm: hhdm
			name: name.str()
		}
		mmio_w32(base + reg_status, 0)
		mmio_w32(base + reg_status, status_acknowledge)
		mmio_w32(base + reg_status, status_acknowledge | status_driver)
		// Accept the backend's immutable write protection before filesystems
		// inspect it, independently of support for cache flush commands.
		features := mmio_r32(base + reg_host_features) & (feature_read_only | feature_flush)
		device.read_only = features & feature_read_only != 0
		device.flush_supported = features & feature_flush != 0
		mmio_w32(base + reg_guest_features, features)
		mmio_w32(base + reg_guest_page_size, u32(memory.page_size))
		if !setup_queue(mut device) {
			mmio_w32(base + reg_status, status_acknowledge | status_driver | status_failed)
			uart.puts(c'virtio-blk: queue unavailable\n')
			continue
		}
		capacity := unsafe { *&u64(base + reg_config) }
		cpu.dmb_ish()
		if capacity == 0 || capacity > u64(0x7fff_ffff_ffff) {
			mmio_w32(base + reg_status, status_acknowledge | status_driver | status_failed)
			uart.puts(c'virtio-blk: invalid capacity\n')
			continue
		}
		device.stat.mode = stat.ifblk | 0o660
		device.stat.rdev = resource.create_dev_id()
		device.stat.blksize = 512
		device.stat.blocks = i64(capacity)
		device.stat.size = i64(capacity * 512)
		device.refcount = 1
		mmio_w32(base + reg_status, status_acknowledge | status_driver | status_driver_ok)
		device.ready = true
		fs.devtmpfs_add_device(device, device.name)
		devices << device
		uart.puts(c'virtio-blk: ready as /dev/')
		uart.puts(&char(device.name.str))
		uart.puts(c'\n')
		index++
	}
}

fn cmdline_has(option string) bool {
	kernel_file := limine.kernel_file()
	if kernel_file == unsafe { nil } || kernel_file.cmdline == unsafe { nil } {
		return false
	}
	return unsafe { cstring_to_vstring(kernel_file.cmdline) }.contains(option)
}

fn persistent_requested() bool {
	return cmdline_has('vinix.qemu_persist=1')
}

fn root_requested() bool {
	return cmdline_has('vinix.qemu_root=1')
}

// Mount the QEMU data disk as the root filesystem, so every write survives a
// restart rather than only the ones below /root. The volume carries a complete
// system, put there by the runner from the same image the initramfs is built
// from; the initramfs stays in the boot payload purely as what this falls back
// to when the volume turns out not to hold one.
//
// Returns true only when the root was actually replaced. The caller then has
// to skip unpacking the initramfs, which would otherwise write the image over
// the volume's own copy of it on every boot.
pub fn mount_persistent_root() bool {
	if !persistent_requested() || !root_requested() {
		return false
	}
	for device in devices {
		path := '/dev/${device.name}' @[freed]
		node := fs.get_node(vfs_root, path, true) or {
			unsafe { path.free() }
			continue
		}
		unsafe { path.free() }
		name_len, name := i32(device.name.len), device.name.str
		mut filesystem, ok := ext2.ext2_init(node)
		if !ok {
			C.kprintf(c'virtio-blk: /dev/%.*s is not a readable ext2 volume\n', name_len, name)
			continue
		}
		// Not attached anywhere: install_disk_root is what publishes it, and
		// only once it has checked that the volume really carries a system.
		mut root := ext2.ext2_root(mut filesystem) or {
			C.kprintf(c'virtio-blk: ext2 volume /dev/%.*s has no readable root\n', name_len,
				name)
			continue
		}
		if !fs.install_disk_root(mut root) {
			C.kprintf(c'virtio-blk: /dev/%.*s does not carry a bootable system\n', name_len,
				name)
			continue
		}
		C.kprintf(c'virtio-blk: persistent ext2 root mounted from /dev/%.*s\n', name_len, name)
		return true
	}
	println('virtio-blk: no ext2 volume carried a system; using the initramfs root')
	return false
}

// Mount the first explicitly supplied QEMU ext2 data disk on /root. Keeping
// the base root as initramfs/tmpfs makes rebuilds reproducible while ordinary
// user data survives VM restarts.
pub fn mount_persistent_home() bool {
	if !persistent_requested() {
		return true
	}
	for device in devices {
		// The mount table keeps a copy of its own.
		path := '/dev/${device.name}' @[freed]
		node := fs.get_node(vfs_root, path, true) or {
			unsafe { path.free() }
			continue
		}
		name_len, name := i32(device.name.len), device.name.str
		filesystem, ok := ext2.ext2_init(node)
		if !ok {
			C.kprintf(c'virtio-blk: /dev/%.*s is not a readable ext2 volume\n', name_len, name)
			unsafe { path.free() }
			continue
		}
		fs.add_filesystem(filesystem, 'qemu-persist')
		fs.mount_at_root(path, '/root', 'qemu-persist') or {
			C.kprintf(c'virtio-blk: ext2 volume /dev/%.*s could not mount at /root\n', name_len,
				name)
			unsafe { path.free() }
			return false
		}
		unsafe { path.free() }
		C.kprintf(c'virtio-blk: persistent ext2 mounted at /root from /dev/%.*s\n', name_len,
			name)
		return true
	}
	println('virtio-blk: requested persistent ext2 volume was not found')
	return false
}
