// SPDX-License-Identifier: GPL-2.0-or-later
// V owns ops/churn observation. The builder includes unchanged C probes in
// this translation unit, with their original main renamed.
@[has_globals]
module main

import os
import perfheap

#include <stdio.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

struct C.sigaction {
mut:
	sa_handler fn (i32)
}
struct C.table {
	version u32
	record_size u32
	count u32
	total u32
	sample_ns u64
	total_memory u64
	free_memory u64
}
struct C.snapshot {
	header C.table
}
// The included legacy C owns this static const-char pointer. A virtual C
// global emits no conflicting extern declaration; stdout/FILE are builtin.
__global C.scratch_dir &char
fn C.printf(&char, ...) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.fflush(&C.FILE) i32
fn C.setvbuf(&C.FILE, &char, i32, usize) i32
fn C.write(i32, voidptr, usize) isize
fn C.open(&char, i32, ...voidptr) i32
fn C.read(i32, voidptr, usize) isize
fn C.close(i32) i32
fn C.sleep(u32) u32
fn C.sync()
fn C.sysconf(i32) i64
fn C.on_signal(i32)
fn C.take(&C.snapshot) i32
fn C.run_program(&&char) i32
fn C.copy_lines(&char, &char, &C.FILE)
fn C.vinix_perf_legacy_main(i32, &&char) i32
fn C.op_stat(i32)
fn C.op_pipe(i32)
fn C.op_socketpair(i32)
fn C.op_inet_socket(i32)
fn C.op_eventfd(i32)
fn C.op_epoll(i32)
fn C.op_timerfd(i32)
fn C.op_poll(i32)
fn C.op_proc_read(i32)
fn C.op_proc_list(i32)
fn C.op_readdir(i32)
fn C.op_dup(i32)
fn C.op_mmap(i32)
fn C.op_thread(i32)
fn C.op_signal(i32)
fn C.op_fault(i32)
fn C.op_fork(i32)
fn C.op_memfd(i32)
fn C.op_tmp_file(i32)
fn C.op_rename(i32)
fn C.op_unlink_open(i32)
fn C.op_rename_over(i32)
fn C.op_hardlink(i32)
fn C.op_mkdir(i32)
fn C.op_symlink(i32)
fn C.op_unix_connect(i32)
fn C.op_unix_datagram(i32)

const general_probes = ['stat', 'pipe', 'socketpair', 'inet_socket', 'eventfd', 'epoll', 'timerfd',
	'poll', 'proc_read', 'proc_list', 'readdir', 'dup', 'mmap', 'thread', 'signal', 'fault', 'fork', 'memfd']!
const file_probes = ['file', 'rename', 'unlink_open', 'rename_over', 'hardlink', 'mkdir', 'symlink',
	'unix_connect', 'unix_datagram']!
const churn_names = ['/bin/true', '/bin/sleep 0', '/usr/bin/curl --version', '/bin/busybox awk BEGIN{}']!

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn chars(text string) &char { return unsafe { &char(text.str) } }
fn grace(seconds u32) {
	mut remaining := seconds
	for remaining > 0 { remaining = C.sleep(remaining) }
}

fn probe(index int, file bool, iteration i32) {
	if file {
		match index {
			0 { C.op_tmp_file(iteration) } 1 { C.op_rename(iteration) }
			2 { C.op_unlink_open(iteration) } 3 { C.op_rename_over(iteration) }
			4 { C.op_hardlink(iteration) } 5 { C.op_mkdir(iteration) }
			6 { C.op_symlink(iteration) } 7 { C.op_unix_connect(iteration) }
			8 { C.op_unix_datagram(iteration) } else {}
		}
	} else {
		match index {
			0 { C.op_stat(iteration) } 1 { C.op_pipe(iteration) } 2 { C.op_socketpair(iteration) }
			3 { C.op_inet_socket(iteration) } 4 { C.op_eventfd(iteration) } 5 { C.op_epoll(iteration) }
			6 { C.op_timerfd(iteration) } 7 { C.op_poll(iteration) } 8 { C.op_proc_read(iteration) }
			9 { C.op_proc_list(iteration) } 10 { C.op_readdir(iteration) } 11 { C.op_dup(iteration) }
			12 { C.op_mmap(iteration) } 13 { C.op_thread(iteration) } 14 { C.op_signal(iteration) }
			15 { C.op_fault(iteration) } 16 { C.op_fork(iteration) } 17 { C.op_memfd(iteration) }
			else {}
		}
	}
}

fn reset_tracker() ! {
	fd := unsafe { C.open(c'/proc/allocstart', C.O_RDONLY) }
	require(fd >= 0, 'allocation tracker reset is unavailable')!
	mut closed := false
	defer { if !closed { C.close(fd) } }
	mut buffer := [4096]u8{}
	mut total := 0
	for {
		got := C.read(fd, unsafe { &buffer[0] }, buffer.len)
		if got < 0 && C.errno == C.EINTR { continue }
		require(got >= 0 && got <= buffer.len, 'allocation tracker reset read failed')!
		if got == 0 {
			closed = true
			require(C.close(fd) == 0, 'allocation tracker reset close failed')!
			return
		}
		total += int(got)
		require(total <= 65536, 'allocation tracker reset exceeded its bound')!
	}
}

fn raw_snapshot(snapshot &perfheap.Snapshot, label string, operation string, directory string, phase string) ! {
	require(snapshot.valid, 'attempt to print an invalid full snapshot')!
	C.printf(c'PERF-HEAP-BEGIN %s op="%s" dir=%s phase=%s schema=vinix-slab-14-4k-v1 bytes=%ld\n',
		chars(label), chars(operation), chars(directory), chars(phase), i64(snapshot.raw_len))
	require(C.fflush(C.stdout) == 0, 'snapshot prefix flush failed')!
	mut offset := 0
	for offset < snapshot.raw_len {
		got := C.write(1, unsafe { &snapshot.raw[offset] }, usize(snapshot.raw_len - offset))
		if got < 0 && C.errno == C.EINTR { continue }
		require(got > 0 && got <= snapshot.raw_len - offset, 'raw snapshot write failed')!
		offset += int(got)
	}
	C.printf(c'PERF-HEAP-END %s op="%s" dir=%s phase=%s\n', chars(label), chars(operation), chars(directory), chars(phase))
}

fn full_delta(before &perfheap.Snapshot, after &perfheap.Snapshot, delta &perfheap.Delta,
	label string, operation string, directory string) ! {
	require(delta.valid, 'attempt to print an invalid delta')!
	for item in delta.classes {
		C.printf(c'PERF-HEAP-DELTA %s op="%s" dir=%s class=size-%lu objects=%+ld pages=%+ld\n',
			chars(label), chars(operation), chars(directory), item.size, item.objects, item.pages)
	}
	C.printf(c'PERF-HEAP-DELTA %s op="%s" dir=%s class=large pages=%+ld\n', chars(label), chars(operation), chars(directory), delta.large_pages)
	C.printf(c'PERF-HEAP-DELTA %s op="%s" dir=%s written_before=%lu written_after=%lu written_after_free=%+ld\n',
		chars(label), chars(operation), chars(directory), before.written_after_free, after.written_after_free, delta.written_after_free)
}

fn measure_probe(index int, file bool, label string, directory string) ! {
	name := if file { file_probes[index] } else { general_probes[index] }
	mut before := perfheap.Snapshot{}
	mut after := perfheap.Snapshot{}
	mut delta := perfheap.Delta{}
	// Touch both raw buffers, all parsed fields and comparison storage before
	// the warm cohort. Proof output happens only after both measured reads.
	perfheap.read_snapshot('/proc/slabinfo', unsafe { &before })!
	perfheap.read_snapshot('/proc/slabinfo', unsafe { &after })!
	perfheap.compare(unsafe { &before }, unsafe { &after }, unsafe { &delta })!
	reset_tracker()!
	for iteration in 0 .. 200 { probe(index, file, i32(iteration)) }
	grace(13)
	perfheap.read_snapshot('/proc/slabinfo', unsafe { &before })!
	reset_tracker()!
	for iteration in 0 .. 200 { probe(index, file, i32(iteration)) }
	grace(13)
	perfheap.read_snapshot('/proc/slabinfo', unsafe { &after })!
	perfheap.compare(unsafe { &before }, unsafe { &after }, unsafe { &delta })!
	raw_snapshot(unsafe { &before }, label, name, directory, 'before')!
	raw_snapshot(unsafe { &after }, label, name, directory, 'after')!
	full_delta(unsafe { &before }, unsafe { &after }, unsafe { &delta }, label, name, directory)!
	mut prefix := [640]char{}
	C.snprintf(unsafe { &prefix[0] }, prefix.len, c'PERF-SITE %s op=%s dir=%s', chars(label), chars(name), chars(directory))
	C.copy_lines(c'/proc/allocsites', unsafe { &prefix[0] }, C.stdout)
	C.printf(c'PERF-OPS %s op=%s dir=%s count=200 bytes_per_op=%ld', chars(label), chars(name), chars(directory), delta.bytes / 200)
	for item in delta.classes { if item.objects != 0 { C.printf(c' size-%lu:%+ld', item.size, item.objects) } }
	if delta.large_pages != 0 { C.printf(c' large_pages:%+ld', delta.large_pages) }
	C.printf(c'\n')
}

fn operations(label string) ! {
	mut action := C.sigaction{sa_handler: C.on_signal}
	require(C.sigaction(C.SIGUSR1, unsafe { &action }, 0) == 0, 'SIGUSR1 probe setup failed')!
	unsafe { C.scratch_dir = &char(c'/tmp') }
	for index in 0 .. general_probes.len { measure_probe(index, false, label, '/tmp')! }
	for directory in ['/tmp', '/root']! {
		unsafe { C.scratch_dir = &char(directory.str) }
		for index in 0 .. file_probes.len { measure_probe(index, true, label, directory)! }
	}
}

fn physical(snapshot &C.snapshot) !u64 {
	require(C.take(snapshot) == 0, 'physical snapshot read failed')!
	require(snapshot.header.version == 1 && snapshot.header.total_memory > 0
		&& snapshot.header.free_memory <= snapshot.header.total_memory, 'invalid physical memory header')!
	return snapshot.header.total_memory - snapshot.header.free_memory
}

fn physical_delta(before u64, after u64) !i64 {
	if after >= before {
		require(after - before <= u64(max_i64), 'physical memory delta overflow')!
		return i64(after - before)
	}
	require(before - after <= u64(max_i64), 'physical memory delta overflow')!
	return -i64(before - after)
}

fn heap_churn(label string) ! {
	mut before := perfheap.Snapshot{}
	mut after := perfheap.Snapshot{}
	mut delta := perfheap.Delta{}
	mut memory := C.snapshot{}
	_ := physical(unsafe { &memory })!
	perfheap.read_snapshot('/proc/slabinfo', unsafe { &before })!
	perfheap.read_snapshot('/proc/slabinfo', unsafe { &after })!
	perfheap.compare(unsafe { &before }, unsafe { &after }, unsafe { &delta })!
	// Fixed char pointers are prepared before any legacy fork/exec helper.
	programs := [[&char(c'/bin/true'), unsafe { &char(nil) }, unsafe { &char(nil) }, unsafe { &char(nil) }]!,
		[&char(c'/bin/sleep'), &char(c'0'), unsafe { &char(nil) }, unsafe { &char(nil) }]!,
		[&char(c'/usr/bin/curl'), &char(c'--version'), unsafe { &char(nil) }, unsafe { &char(nil) }]!,
		[&char(c'/bin/busybox'), &char(c'awk'), &char(c'BEGIN{}'), unsafe { &char(nil) }]!]!
	for index, name in churn_names {
		reset_tracker()!
		for _ in 0 .. 300 { require(C.run_program(unsafe { &programs[index][0] }) == 1, 'churn warm child failed')! }
		C.sync(); grace(7)
		_ := physical(unsafe { &memory })!
		perfheap.read_snapshot('/proc/slabinfo', unsafe { &before })!
		used := physical(unsafe { &memory })!
		reset_tracker()!
		for _ in 0 .. 300 { require(C.run_program(unsafe { &programs[index][0] }) == 1, 'churn measured child failed')! }
		C.sync(); grace(7)
		_ := physical(unsafe { &memory })!
		perfheap.read_snapshot('/proc/slabinfo', unsafe { &after })!
		used_after := physical(unsafe { &memory })!
		retained := physical_delta(used, used_after)!
		perfheap.compare(unsafe { &before }, unsafe { &after }, unsafe { &delta })!
		raw_snapshot(unsafe { &before }, label, name, '-', 'before')!
		raw_snapshot(unsafe { &after }, label, name, '-', 'after')!
		full_delta(unsafe { &before }, unsafe { &after }, unsafe { &delta }, label, name, '-')!
		C.printf(c'PERF-CHURN %s program="%s" runs=300 retained_kb=%ld per_run_bytes=%ld\n', chars(label), chars(name), retained / 1024, retained / 300)
		for item in delta.classes {
			if item.objects != 0 || item.pages != 0 {
				C.printf(c'PERF-SLAB %s program="%s" class=size-%lu objects=%+ld pages=%+ld\n', chars(label), chars(name), item.size, item.objects, item.pages)
			}
		}
		if delta.large_pages != 0 { C.printf(c'PERF-SLAB %s program="%s" class=large pages=%+ld\n', chars(label), chars(name), delta.large_pages) }
		mut prefix := [640]char{}
		C.snprintf(unsafe { &prefix[0] }, prefix.len, c'PERF-SITE %s program="%s"', chars(label), chars(name))
		C.copy_lines(c'/proc/allocsites', unsafe { &prefix[0] }, C.stdout)
	}
}

fn valid_label(label string, mode string) bool {
	if label.len > 256 || !label.starts_with('variant=') { return false }
	mut cursor := 8
	start := cursor
	for cursor < label.len && label[cursor] != ` ` {
		byte := label[cursor]
		if !((byte >= `a` && byte <= `z`) || (byte >= `A` && byte <= `Z`)
			|| (byte >= `0` && byte <= `9`) || byte in [`_`, `-`]!) { return false }
		cursor++
	}
	if cursor == start { return false }
	tail := if mode == 'ops' { ' scenario=ops round=' } else { ' scenario=churn round=' }
	for byte in tail {
		if cursor >= label.len || label[cursor] != byte { return false }
		cursor++
	}
	if cursor >= label.len || label[cursor] < `1` || label[cursor] > `9` { return false }
	mut round := u64(0)
	for cursor < label.len {
		byte := label[cursor]
		if byte < `0` || byte > `9` { return false }
		round = round * 10 + u64(byte - `0`)
		if round > u64(max_i32) { return false }
		cursor++
	}
	return true
}

fn run() !int {
	if os.args.len >= 2 && os.args[1] in ['ops', 'churn']! {
		mode := os.args[1]
		require(os.args.len >= 4 && os.args[2] == if mode == 'ops' { '200' } else { '300' }, 'fixed operation count required')!
		label := os.args[3..].join(' ')
		defer { unsafe { label.free() } }
		require(valid_label(label, mode), 'invalid perf label')!
		require(C.sysconf(C._SC_PAGESIZE) == 4096, 'slab schema requires 4096-byte pages')!
		require(C.setvbuf(C.stdout, unsafe { nil }, C._IOLBF, 0) == 0, 'line buffering failed')!
		if mode == 'ops' { operations(label)! } else { heap_churn(label)! }
		return 0
	}
	mut pointers := []&char{len: os.args.len + 1, init: unsafe { nil }}
	defer { unsafe { pointers.free() } }
	for index, argument in os.args { pointers[index] = unsafe { &char(argument.str) } }
	return int(C.vinix_perf_legacy_main(i32(os.args.len), pointers.data))
}

fn main() {
	status := run() or { eprintln('PERF-ERROR full V observer: ' + err.msg()); exit(1) }
	exit(status)
}
