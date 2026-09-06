// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module ans

import resource
import fs
import stat
import file
import klock
import katomic
import errno
import event.eventstruct

#include "apple_ans.h"

fn C.vinix_ans_requested(cmdline &char, length u64) int
fn C.vinix_ans_boot_flags(cmdline &char, length u64) int
fn C.vinix_ans_apply_policy(cmdline &char, length u64) int
fn C.vinix_ans_partition_writable(index u32, partition u32) int
fn C.vinix_ans_partition_uuid(index u32, partition u32, out &char, capacity u64) int
fn C.vinix_ans_write(index u32, partition u32, buffer voidptr, offset u64, count u64) int
fn C.vinix_ans_flush() int
fn C.vinix_ans_shutdown() int
fn C.vinix_ans_root_ns() int
fn C.vinix_ans_root_part() int
fn C.vinix_ans_init(nvme u64, asc u64, mailbox u64, sart u64, reset u64, dma voidptr, physical u64, bytes u64) int
fn C.vinix_ans_namespace_count() int
fn C.vinix_ans_namespace_id(index u32) u32
fn C.vinix_ans_sector_size(index u32) u32
fn C.vinix_ans_sector_count(index u32) u64
fn C.vinix_ans_partition_count(index u32) int
fn C.vinix_ans_partition_number(index u32, partition u32) u32
fn C.vinix_ans_partition_start(index u32, partition u32) u64
fn C.vinix_ans_partition_blocks(index u32, partition u32) u64
fn C.vinix_ans_read(index u32, buffer voidptr, offset u64, count u64) int
fn C.vinix_ans_stage() u32
fn C.vinix_ans_completion_status() u16

__global (
	ans_lock klock.Lock
	ans_attempted = false
	ans_ready = false
	ans_boot_flags = int(0)
	ans_policy_invalid = false
	ans_read_error_reported = false
)

struct AnsBlock {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
	ns_index u32
	partition int = -1
	offset   u64
}

fn (mut this AnsBlock) read(_handle voidptr, buffer voidptr, loc u64, count u64) ?i64 {
	if loc > u64(this.stat.size) {
		errno.set(errno.einval)
		return none
	}
	mut bytes := count
	if bytes > u64(this.stat.size) - loc { bytes = u64(this.stat.size) - loc }
	// Return a short read for huge requests rather than monopolizing the CPU.
	if bytes > 0x100000 { bytes = 0x100000 }
	if bytes == 0 { return 0 }
	ans_lock.acquire()
	defer { ans_lock.release() }
	result := C.vinix_ans_read(this.ns_index, buffer, this.offset + loc, bytes)
	if result != 0 {
		if !ans_read_error_reported {
			ans_read_error_reported = true
			C.printf(c'ans: read failed error=%d stage=%u nvme_status=0x%x\n',
				result, C.vinix_ans_stage(), C.vinix_ans_completion_status())
		}
		errno.set(errno.eio)
		return none
	}
	return i64(bytes)
}

fn (mut this AnsBlock) write(_handle voidptr, buffer voidptr, loc u64, count u64) ?i64 {
	ans_lock.acquire()
	defer { ans_lock.release() }
	if this.partition < 0 || C.vinix_ans_partition_writable(this.ns_index, u32(this.partition)) == 0 {
		errno.set(errno.erofs)
		return none
	}
	if loc > u64(this.stat.size) || count > u64(this.stat.size) - loc {
		errno.set(errno.einval)
		return none
	}
	bytes := if count > 0x100000 { u64(0x100000) } else { count }
	if bytes == 0 { return 0 }
	// C uses an offset relative to this partition; there is no raw-write API.
	result := C.vinix_ans_write(this.ns_index, u32(this.partition), buffer, loc, bytes)
	if result != 0 {
		C.printf(c'ans: write/flush failed error=%d stage=%u status=0x%x; writes stopped\n',
			result, C.vinix_ans_stage(), C.vinix_ans_completion_status())
		errno.set(u64(if result == -12 { errno.erofs } else { errno.eio }))
		return none
	}
	return i64(bytes)
}

fn (mut this AnsBlock) ioctl(_handle voidptr, request u64, argp voidptr) ?int {
	// BLKFLSBUF has no pointer argument. This driver has no software block
	// cache to invalidate; issue a real NVMe flush and propagate its failure.
	if request == 0x1261 {
		if !flush() { errno.set(errno.eio); return none }
		return 0
	}
	if argp == unsafe { nil } {
		errno.set(errno.efault)
		return none
	}
	// Linux block geometry queries only. No NVMe admin/I/O passthrough or BLKROSET.
	match request {
		0x1268 { // BLKSSZGET
			value := int(this.stat.blksize)
			unsafe { C.memcpy(argp, &value, sizeof(value)) }
		}
		0x80081272 { // BLKGETSIZE64: size of THIS namespace/partition view
			value := u64(this.stat.size)
			unsafe { C.memcpy(argp, &value, sizeof(value)) }
		}
		0x1260 { // BLKGETSIZE: count of 512-byte sectors, unsigned long on arm64
			value := u64(this.stat.size) / 512
			unsafe { C.memcpy(argp, &value, sizeof(value)) }
		}
		0x125e { // BLKROGET
			ans_lock.acquire()
			writable := this.partition >= 0 && C.vinix_ans_partition_writable(this.ns_index, u32(this.partition)) != 0
			ans_lock.release()
			value := if writable { int(0) } else { int(1) }
			unsafe { C.memcpy(argp, &value, sizeof(value)) }
		}
		else {
			errno.set(errno.enotty)
			return none
		}
	}
	return 0
}

fn (mut this AnsBlock) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}
fn (mut this AnsBlock) grow(_handle voidptr, _new_size u64) ? {
	errno.set(errno.erofs)
	return none
}
fn (mut this AnsBlock) unref(_handle voidptr) ? { katomic.dec(mut &this.refcount) }
fn (mut this AnsBlock) link(_handle voidptr) ? { katomic.inc(mut &this.stat.nlink) }
fn (mut this AnsBlock) unlink(_handle voidptr) ? { katomic.dec(mut &this.stat.nlink) }

fn publish(index u32, partition int, start u64, blocks u64, name string) {
	sector := u64(C.vinix_ans_sector_size(index))
	mut res := &AnsBlock{ns_index: index, partition: partition, offset: start * sector}
	res.stat.size = i64(blocks * sector)
	res.stat.blocks = res.stat.size / 512
	res.stat.blksize = i64(sector)
	res.stat.rdev = resource.create_dev_id()
	// Raw storage is not made readable to every unprivileged user.
	writable := partition >= 0 && C.vinix_ans_partition_writable(index, u32(partition)) != 0
	res.stat.mode = (if writable { u32(0o600) } else { u32(0o440) }) | stat.ifblk
	res.status = file.pollin | (if writable { file.pollout } else { 0 })
	fs.devtmpfs_add_device(res, name)
	access := if writable { 'writable (FUA + flush)' } else { 'read-only' }
	println('ans: /dev/${name}: ${res.stat.size} bytes, ${sector}-byte sectors, ${access}')
	if partition >= 0 {
		mut uuid := [37]u8{}
		if C.vinix_ans_partition_uuid(index, u32(partition), unsafe { &char(&uuid[0]) }, 37) == 0 {
			C.printf(c'ans: %s PARTUUID=%s\n', name.str, &uuid[0])
		}
	}
}

// Call once after devtmpfs exists, from the kernel initialization thread.
// No probe, allocation, MMIO, formatting or mounting without explicit opt-in.
pub fn initialise(cmdline string) {
	ans_boot_flags = C.vinix_ans_boot_flags(unsafe { &char(cmdline.str) }, u64(cmdline.len))
	if ans_boot_flags < 0 {
		ans_policy_invalid = true
		println('ans: invalid/contradictory boot policy; no hardware probed')
		return
	}
	$if no_apple_ans ? {
		return
	} $else {
		if ans_boot_flags & 1 == 0 { return }
		ans_lock.acquire()
		defer { ans_lock.release() }
		if ans_attempted { return }
		ans_attempted = true
		if !initialise_hardware() { return }
		if C.vinix_ans_apply_policy(unsafe { &char(cmdline.str) }, u64(cmdline.len)) != 0 {
			println('ans: PARTUUID policy could not be resolved safely; no block devices published')
			return
		}
		ans_ready = true
		for i in 0 .. C.vinix_ans_namespace_count() {
			index := u32(i)
			name := 'ans0n${C.vinix_ans_namespace_id(index)}'
			publish(index, -1, 0, C.vinix_ans_sector_count(index), name)
			parts := C.vinix_ans_partition_count(index)
			for j in 0 .. parts {
				p := u32(j)
				publish(index, int(p), C.vinix_ans_partition_start(index, p),
					C.vinix_ans_partition_blocks(index, p),
					'${name}p${C.vinix_ans_partition_number(index, p)}')
			}
			if parts == 0 { println('ans: ${name}: no validated GPT partitions') }
		}
	}
}

// These operations serialize with the complete RMW operation, not just with
// its doorbell. A timed-out controller remains pinned and returns failure.
pub fn flush() bool {
	ans_lock.acquire()
	defer { ans_lock.release() }
	return C.vinix_ans_flush() == 0
}

pub fn shutdown() bool {
	ans_lock.acquire()
	defer { ans_lock.release() }
	result := C.vinix_ans_shutdown()
	if result != 0 {
		C.printf(c'ans: shutdown refused error=%d stage=%u status=0x%x\n',
			result, C.vinix_ans_stage(), C.vinix_ans_completion_status())
		return false
	}
	ans_ready = false
	return true
}
