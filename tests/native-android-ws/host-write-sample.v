// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only macOS process write telemetry; never reads process arguments/files.
module main

import json2
import os
import time

#include <libproc.h>
#include <sys/resource.h>

struct C.rusage_info_v2 {
	ri_proc_start_abstime u64
	ri_diskio_byteswritten u64
}

fn C.proc_listallpids(voidptr, i32) i32
fn C.proc_pid_rusage(i32, i32, voidptr) i32
fn C.proc_name(i32, voidptr, u32) i32

struct Sample {
	pid int
	name string
	started u64
	written u64
}

struct Writer {
	pid int
	name string
	written_bytes u64
}

fn snapshot() !(map[int]Sample, int) {
	// Darwin pid_t is 32-bit; current V int can be wider than C int.
	mut pids := []i32{len: 65536}
	n := int(C.proc_listallpids(pids.data, i32(pids.len * sizeof(i32))))
	if n <= 0 || n >= pids.len { return error('process list unavailable or truncated') }
	mut samples := map[int]Sample{}
	mut unavailable := 0
	for native_pid in pids[..n] {
		pid := int(native_pid)
		if pid <= 0 { continue }
		mut usage := C.rusage_info_v2{}
		if C.proc_pid_rusage(native_pid, C.RUSAGE_INFO_V2, unsafe { &usage }) != 0 {
			unavailable++
			continue
		}
		mut name := []u8{len: 256}
		count := int(C.proc_name(native_pid, name.data, u32(name.len)))
		label := if count > 0 && count < name.len { name[..count].bytestr().clone() } else { '(unavailable)' }
		samples[pid] = Sample{pid: pid, name: label,
			started: usage.ri_proc_start_abstime, written: usage.ri_diskio_byteswritten}
	}
	if os.getpid() !in samples || samples[os.getpid()].started == 0 {
		return error('own process telemetry missing; no trustworthy sample')
	}
	return samples, unavailable
}

fn changes(before map[int]Sample, after map[int]Sample) []Writer {
	mut writers := []Writer{}
	for pid, current in after {
		previous := before[pid] or { continue }
		// PID reuse and counter reset must never become unsigned subtraction.
		if previous.started != current.started || current.written <= previous.written { continue }
		writers << Writer{pid: pid, name: current.name, written_bytes: current.written - previous.written}
	}
	writers.sort(a.written_bytes > b.written_bytes)
	return writers
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		before := {1: Sample{pid: 1, started: 11, written: 100},
			2: Sample{pid: 2, started: 22, written: 200},
			3: Sample{pid: 3, started: 33, written: 300}}
		after := {1: Sample{pid: 1, name: 'same', started: 11, written: 150},
			2: Sample{pid: 2, started: 23, written: 999},
			3: Sample{pid: 3, started: 33, written: 1},
			4: Sample{pid: 4, started: 44, written: 999}}
		assert changes(before, after) == [Writer{pid: 1, name: 'same', written_bytes: 50}]
		println('HOST-WRITE-SAMPLE-PASS PID reuse, reset, new/exited processes')
		return
	}
	if os.args.len != 1 { eprintln('usage: host-write-sample [--self-test]'); exit(2) }
	before, unavailable_before := snapshot() or { eprintln(err); exit(1) }
	started := time.sys_mono_now()
	time.sleep(10 * time.second)
	after, unavailable_after := snapshot() or { eprintln(err); exit(1) }
	writers := changes(before, after)
	println(json2.encode({
		'elapsed_ms': json2.Any((time.sys_mono_now() - started) / 1000000),
		'unavailable_before': json2.Any(unavailable_before),
		'unavailable_after': json2.Any(unavailable_after),
		'sampled_before': json2.Any(before.len), 'sampled_after': json2.Any(after.len),
		'writers': json2.decode[json2.Any](json2.encode(writers[..int_min(writers.len, 20)])) or { panic(err) },
		'limits': json2.Any('Surviving readable processes only; process I/O is not filesystem free-space growth.')
	}, prettify: true))
}
