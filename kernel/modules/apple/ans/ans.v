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
	offset   u64
}

fn (mut this AnsBlock) read(_handle voidptr, buffer voidptr, loc u64, count u64) ?i64 {
	if loc > this.stat.size {
		errno.set(errno.einval)
		return none
	}
	mut bytes := count
	if bytes > this.stat.size - loc { bytes = this.stat.size - loc }
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

fn (mut this AnsBlock) write(_handle voidptr, _buffer voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.erofs)
	return none
}

fn (mut this AnsBlock) ioctl(_handle voidptr, request u64, argp voidptr) ?int {
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
			value := this.stat.size
			unsafe { C.memcpy(argp, &value, sizeof(value)) }
		}
		0x1260 { // BLKGETSIZE: count of 512-byte sectors, unsigned long on arm64
			value := this.stat.size / 512
			unsafe { C.memcpy(argp, &value, sizeof(value)) }
		}
		0x125e { // BLKROGET
			value := int(1)
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

fn publish(index u32, start u64, blocks u64, name string) {
	sector := u64(C.vinix_ans_sector_size(index))
	mut res := &AnsBlock{ns_index: index, offset: start * sector}
	res.stat.size = blocks * sector
	res.stat.blocks = res.stat.size / 512
	res.stat.blksize = sector
	res.stat.rdev = resource.create_dev_id()
	// Raw storage is not made readable to every unprivileged user.
	res.stat.mode = 0o440 | stat.ifblk
	res.status = file.pollin
	fs.devtmpfs_add_device(res, name)
	println('ans: /dev/${name}: ${res.stat.size} bytes, ${sector}-byte sectors, read-only')
}

// Call once after devtmpfs exists, from the kernel initialization thread.
// No probe, allocation, MMIO, formatting or mounting without explicit opt-in.
pub fn initialise(cmdline string) {
	$if no_apple_ans ? {
		return
	} $else {
		if C.vinix_ans_requested(unsafe { &char(cmdline.str) }, u64(cmdline.len)) == 0 { return }
		ans_lock.acquire()
		defer { ans_lock.release() }
		if ans_attempted { return }
		ans_attempted = true
		if !initialise_hardware() { return }
		for i in 0 .. C.vinix_ans_namespace_count() {
			index := u32(i)
			name := 'ans0n${C.vinix_ans_namespace_id(index)}'
			publish(index, 0, C.vinix_ans_sector_count(index), name)
			parts := C.vinix_ans_partition_count(index)
			for j in 0 .. parts {
				p := u32(j)
				publish(index, C.vinix_ans_partition_start(index, p),
					C.vinix_ans_partition_blocks(index, p),
					'${name}p${C.vinix_ans_partition_number(index, p)}')
			}
			if parts == 0 { println('ans: ${name}: no validated GPT partitions') }
		}
	}
}
