// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// /dev/processes — one read, one picture of every process on the machine.
//
// Vinix has no procfs, and a monitor that had to open a file per process would
// race every exit it walked past. This node answers instead with a single
// snapshot taken under the process table's own lock: a short header, then one
// fixed-size record per process. Everything in it is a running total or an
// absolute quantity, never a rate — a reader that wants "percent of a CPU"
// takes two snapshots and divides the difference in `cpu_time_ns` by the
// difference in `sample_ns`, which is the only way to get a figure that means
// anything over an interval the kernel was never told about.
//
// The node is read-only and a read never blocks.
@[has_globals]
module procdev

import resource
import fs
import stat
import klock
import katomic
import errno
import file
import memory
import memory.mmap
import proc
import time
import event.eventstruct

// A process' name here is the path it was executed from with its pid appended,
// so the part worth reading is at the end. The field is sized to hold a whole
// path from this image rather than to be tidy: truncating one would cut off
// exactly the basename a reader is looking for. A longer name is still
// truncated rather than refused.
pub const name_len = 64

// What a reader checks before trusting the layout of everything after it. Any
// change to either struct below bumps the version.
pub const table_version = u32(1)

// A cap on how much of one snapshot a single read can produce, so a reader
// asking for a gigabyte does not get one. Vinix's pid space is far larger than
// the number of processes it will ever run at once.
pub const max_records = 512

// ProcessSample is one process. `memory_bytes` is the sum of its committed
// mapped ranges. Accessible mappings are pre-faulted by this kernel, while a
// PROT_NONE range is only an address-space reservation and owns no pages.
pub struct ProcessSample {
pub mut:
	pid     i32
	ppid    i32
	threads i32
	// Explicit, so that the two u64s below land on an eight byte boundary
	// under any compiler rather than by the good luck of the fields above.
	reserved     i32
	memory_bytes u64
	cpu_time_ns  u64
	name         [name_len]u8
}

// ProcessTable heads every read. `count` is how many records follow and
// `total` how many processes existed when the snapshot was taken; `total`
// being the larger of the two is how a reader learns its buffer was too small
// rather than that processes disappeared.
pub struct ProcessTable {
pub mut:
	version      u32
	record_size  u32
	count        u32
	total        u32
	sample_ns    u64
	total_memory u64
	free_memory  u64
}

struct Processes {
pub mut:
	stat     stat.Stat
	refcount int
	l        klock.Lock
	event    eventstruct.Event
	status   int
	can_mmap bool
}

__global (
	processes_res = &Processes(unsafe { nil })
)

fn (mut this Processes) mmap(_handle voidptr, _page u64, _flags int) voidptr {
	return unsafe { nil }
}

// resident_bytes sums a process' committed mapped ranges. mmap() pre-faults
// every accessible range, so its length is resident; PROT_NONE reservations
// deliberately have no pages and must not be reported as RAM. Allocators use
// those reservations for metadata arenas, and counting them made an idle
// process appear to leak even while its actual allocations were all freed.
//
// The pagemap lock is taken without blocking on purpose. This runs with the
// process table locked, and a process in the middle of an mmap holds its
// pagemap while it goes on to touch the allocator; blocking here would put a
// lock this node holds underneath one the rest of the kernel takes first, and
// that is how a monitor deadlocks the machine it is monitoring. A process that
// is busy remapping itself is reported as 0 for one sample instead.
fn resident_bytes(process &proc.Process) u64 {
	mut pagemap := process.pagemap
	if unsafe { pagemap == nil } {
		return 0
	}
	if !pagemap.l.test_and_acquire() {
		return 0
	}
	mut total := u64(0)
	for i := 0; i < pagemap.mmap_ranges.len; i++ {
		range := unsafe { &mmap.MmapRangeLocal(pagemap.mmap_ranges[i]) }
		if unsafe { range == nil } || range.prot == mmap.prot_none {
			continue
		}
		total += range.length
	}
	pagemap.l.release()
	return total
}

// copy_name writes a process' name into a record, truncated to fit and always
// left NUL-terminated so a reader can treat it as a C string.
fn copy_name(mut sample ProcessSample, name string) {
	mut length := name.len
	if length > name_len - 1 {
		length = name_len - 1
	}
	for i := 0; i < length; i++ {
		sample.name[i] = unsafe { name.str[i] }
	}
	for i := length; i < name_len; i++ {
		sample.name[i] = 0
	}
}

fn (mut this Processes) read(_handle voidptr, buf voidptr, _loc u64, count u64) ?i64 {
	if count < u64(sizeof(ProcessTable)) {
		errno.set(errno.einval)
		return none
	}

	// How many records the caller's buffer has room for after the header.
	mut capacity := (count - u64(sizeof(ProcessTable))) / u64(sizeof(ProcessSample))
	if capacity > max_records {
		capacity = max_records
	}

	mut header := ProcessTable{
		version: table_version
		record_size: u32(sizeof(ProcessSample))
		sample_ns: time.monotonic_ns()
		total_memory: memory.total_bytes()
		free_memory: memory.free_bytes()
	}

	records := unsafe { &ProcessSample(voidptr(&u8(buf) + sizeof(ProcessTable))) }

	// The whole walk happens with the table locked: a `&Process` taken out of
	// it is only valid while the lock is held, and copying the pointers out to
	// read them afterwards would be reading memory an exit had already freed.
	proc.lock_table()
	for pid := 1; pid < proc.max_pid; pid++ {
		process := proc.process_at(pid)
		if unsafe { process == nil } {
			continue
		}
		header.total++
		if u64(header.count) >= capacity {
			continue
		}
		mut sample := unsafe { &records[header.count] }
		sample.pid = i32(process.pid)
		sample.ppid = i32(process.ppid)
		sample.threads = i32(process.threads.len)
		sample.reserved = 0
		sample.memory_bytes = resident_bytes(process)
		sample.cpu_time_ns = process.cpu_time_ns
		copy_name(mut sample, process.name)
		header.count++
	}
	proc.unlock_table()

	unsafe {
		C.memcpy(buf, &header, sizeof(ProcessTable))
	}

	return i64(u64(sizeof(ProcessTable)) + u64(header.count) * u64(sizeof(ProcessSample)))
}

fn (mut this Processes) write(_handle voidptr, _buf voidptr, _loc u64, _count u64) ?i64 {
	errno.set(errno.eperm)
	return none
}

fn (mut this Processes) ioctl(handle voidptr, request u64, argp voidptr) ?int {
	return resource.default_ioctl(handle, request, argp)
}

fn (mut this Processes) unref(_handle voidptr) ? {
	katomic.dec(mut &this.refcount)
}

fn (mut this Processes) link(_handle voidptr) ? {
	katomic.inc(mut &this.stat.nlink)
}

fn (mut this Processes) unlink(_handle voidptr) ? {
	katomic.dec(mut &this.stat.nlink)
}

fn (mut this Processes) grow(_handle voidptr, _new_size u64) ? {
	return none
}

// initialise publishes /dev/processes. A snapshot is built on demand, so there
// is no sampling thread behind this and nothing to start.
pub fn initialise() {
	mut res := &Processes{}

	// A whole table's worth, which is what a reader should size its buffer at
	// to be sure of getting every process in one read.
	res.stat.size = u64(sizeof(ProcessTable)) + u64(max_records) * u64(sizeof(ProcessSample))
	res.stat.blocks = 0
	res.stat.blksize = u64(sizeof(ProcessSample))
	res.stat.rdev = resource.create_dev_id()
	// Read-only to everyone: this says who is running what, and nothing here
	// is writable in the first place.
	res.stat.mode = 0o444 | stat.ifchr

	// A read never blocks, so the node is always ready.
	res.status |= file.pollin

	processes_res = res

	fs.devtmpfs_add_device(res, 'processes')
}
