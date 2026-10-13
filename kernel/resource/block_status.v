// SPDX-License-Identifier: GPL-2.0-or-later
module resource

import klock
import errno

pub const block_status_ioctl = u64(0x56560004)
pub const block_readonly = u64(1)
pub const block_offline = u64(2)
pub const block_flush = u64(4)
pub const block_volume = u64(8)
pub const block_parent_counters = u64(16)
pub const block_encrypted = u64(64)

// Version-one userspace ABI: sixteen native little-endian 64-bit words.
pub struct BlockStatus {
pub mut:
	version     u64 = 1
	bytes       u64
	sector      u64
	flags       u64
	reads       u64
	writes      u64
	read_bytes  u64
	write_bytes u64
	flushes     u64
	errors      u64
	last_error  u64
	disk_id     u64
	start       u64
	slot        u64 = u64(-1)
	generation  u64
	reserved    u64
}

pub struct BlockMetrics {
mut:
	l           klock.Lock
	reads       u64
	writes      u64
	read_bytes  u64
	write_bytes u64
	flushes     u64
	errors      u64
	last_error  u64
}

pub fn (mut metrics BlockMetrics) completed(bytes u64, writing bool) {
	metrics.l.acquire()
	defer { metrics.l.release() }
	if writing {
		metrics.writes++
		metrics.write_bytes += bytes
	} else {
		metrics.reads++
		metrics.read_bytes += bytes
	}
}

pub fn (mut metrics BlockMetrics) flushed() {
	metrics.l.acquire()
	metrics.flushes++
	metrics.l.release()
}

pub fn (mut metrics BlockMetrics) failed() {
	code := errno.get()
	metrics.l.acquire()
	metrics.errors++
	metrics.last_error = u64(if code != 0 { code } else { errno.eio })
	metrics.l.release()
}

pub fn (mut metrics BlockMetrics) snapshot(bytes u64, sector u64, flags u64,
	identity BlockIdentity) BlockStatus {
	metrics.l.acquire()
	defer { metrics.l.release() }
	return BlockStatus{
		bytes:       bytes
		sector:      sector
		flags:       flags
		reads:       metrics.reads
		writes:      metrics.writes
		read_bytes:  metrics.read_bytes
		write_bytes: metrics.write_bytes
		flushes:     metrics.flushes
		errors:      metrics.errors
		last_error:  metrics.last_error
		disk_id:     identity.disk_id
		start:       identity.start
	}
}

pub interface BlockStatusResource {
mut:
	block_status() BlockStatus
}

struct BlockStatusCall {
mut:
	device BlockStatusResource
}

pub fn block_status(mut device Resource) ?BlockStatus {
	if mut device is BlockStatusResource {
		mut call := unsafe { &BlockStatusCall(C.vinix_stack_alloc(sizeof(BlockStatusCall))) }
		unsafe { call.device = BlockStatusResource(device) }
		snapshot := call.device.block_status()
		if snapshot.version == 1 { return snapshot }
	}
	errno.set(errno.enotty)
	return none
}
