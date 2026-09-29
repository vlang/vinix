// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module ans

import resource
import fs
import stat
import file
import klock
import lib
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
fn C.vinix_ans_data_close() int
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
fn C.vinix_ans_error() int

// The C driver's error codes (enum ANS_*), by name.
fn error_name(code int) string {
	value := if code < 0 { -code } else { code }
	return match value {
		0 { 'none' }
		1 { 'config' }
		2 { 'handoff' }
		3 { 'timeout' }
		4 { 'protocol' }
		5 { 'firmware' }
		6 { 'sart' }
		7 { 'completion' }
		8 { 'capability' }
		9 { 'namespace' }
		10 { 'gpt' }
		11 { 'range' }
		12 { 'read-only' }
		13 { 'stopped' }
		else { 'unknown' }
	}
}

// How far a_start() had got.
fn stage_name(stage u32) string {
	return match stage {
		0 { 'not started' }
		1 { 'taking the controller over from the loader' }
		2 { 'booting the ANS firmware' }
		3 { 'waiting for the firmware' }
		4 { 'enabling NVMe' }
		5 { 'reading namespaces' }
		6 { 'reading the GPT' }
		else { 'running' }
	}
}

// One line that says where the SSD driver stopped and why. These used to be
// C.printf, which a production kernel compiles out: an M1 whose persistent
// volume failed showed only the panic, with nothing to say what had failed.
fn report(what string, result int) {
	code := if result != 0 { result } else { C.vinix_ans_error() }
	name := error_name(code)
	stage := C.vinix_ans_stage()
	phase := stage_name(stage)
	status := u64(C.vinix_ans_completion_status())
	C.kprintf(c'ans: %.*s: error %lld (%.*s) at stage %llu (%.*s), NVMe status 0x%llx\n',
		i32(what.len), what.str, i64(code), i32(name.len), name.str, u64(stage),
		i32(phase.len), phase.str, status)
}

__global (
	ans_lock klock.Lock
	ans_attempted = false
	ans_ready = false
	ans_boot_flags = int(0)
	ans_policy_invalid = false
	ans_read_error_reported = false
	ans_data_mounted = false
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
			report('read failed', result)
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
		report('write or flush failed; writes stopped', result)
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
			value := i32(this.stat.blksize)
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
			value := i32(if writable { 0 } else { 1 })
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
	access := if writable { c'writable (FUA + flush)' } else { c'read-only' }
	C.kprintf(c'ans: /dev/%.*s: %lld bytes, %llu-byte sectors, %s\n', i32(name.len), name.str,
		i64(res.stat.size), u64(sector), access)
	if partition >= 0 {
		mut uuid := [37]u8{}
		if C.vinix_ans_partition_uuid(index, u32(partition), unsafe { &char(&uuid[0]) }, 37) == 0 {
			C.kprintf(c'ans: %.*s PARTUUID=%s\n', i32(name.len), name.str, &uuid[0])
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
		policy := C.vinix_ans_apply_policy(unsafe { &char(cmdline.str) }, u64(cmdline.len))
		if policy != 0 {
			report('PARTUUID policy could not be resolved safely; no block devices published',
				policy)
			return
		}
		ans_ready = true
		for i in 0 .. C.vinix_ans_namespace_count() {
			index := u32(i)
			// The device nodes keep these names.
			mut namespace := lib.new_text(16)
			namespace.add('ans0n')
			namespace.add_unsigned(u64(C.vinix_ans_namespace_id(index)))
			name := namespace.str()
			publish(index, -1, 0, C.vinix_ans_sector_count(index), name)
			parts := C.vinix_ans_partition_count(index)
			for j in 0 .. parts {
				p := u32(j)
				mut partition := lib.new_text(name.len + 4)
				partition.add(name)
				partition.add_byte(`p`)
				partition.add_unsigned(u64(C.vinix_ans_partition_number(index, p)))
				publish(index, int(p), C.vinix_ans_partition_start(index, p),
					C.vinix_ans_partition_blocks(index, p), partition.str())
			}
			if parts == 0 {
				C.kprintf(c'ans: %.*s: no validated GPT partitions\n', i32(name.len), name.str)
			}
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
	if ans_data_mounted && C.vinix_ans_data_close() != 0 {
		println('ans-data: could not mark ext2 clean; shutdown refused')
		return false
	}
	result := C.vinix_ans_shutdown()
	if result != 0 {
		report('shutdown refused', result)
		return false
	}
	ans_ready = false
	return true
}
