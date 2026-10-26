// SPDX-License-Identifier: GPL-2.0-or-later
module probefault

import faultprobe
import os
import strconv

#include <signal.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C.pipe(&i32) i32
fn C.dup2(int, int) int
fn C.close(int) int
fn C.read(int, voidptr, usize) isize
fn C.mmap(voidptr, usize, int, int, int, i64) voidptr
fn C._exit(int)

type NativeAction = fn (int, voidptr, voidptr) int

fn action(number int, input voidptr, output voidptr) int {
	function := unsafe { NativeAction(voidptr(C.sigaction)) }
	return function(number, input, output)
}

fn disposition(number int) ![24]u64 {
	mut storage := [24]u64{}
	if sizeof(C.sigaction) > sizeof(storage) { return error('native sigaction too large') }
	if action(number, unsafe { nil }, &storage[0]) != 0 { return error('read native disposition') }
	return storage
}

pub fn verify() ! {
	for signal in [C.SIGSEGV, C.SIGBUS, C.SIGILL] {
		before := disposition(signal)!
		mut disabled := faultprobe.install(false)!
		faultprobe.restore(mut disabled)!
		if disposition(signal)! != before { return error('disabled probe changed disposition') }
		mut enabled := faultprobe.install(true)!
		if disposition(signal)! == before { return error('probe did not install handler') }
		faultprobe.restore(mut enabled)!
		if disposition(signal)! != before { return error('probe did not restore disposition') }
		faultprobe.restore(mut enabled)!
	}
	mut pipes := [2]i32{}
	if C.pipe(&pipes[0]) != 0 { return error('fault check pipe') }
	child := C.fork()
	if child < 0 { C.close(pipes[0]); C.close(pipes[1]); return error('fault check fork') }
	if child == 0 {
		C.close(pipes[0])
		if C.dup2(pipes[1], 2) != 2 { C._exit(125) }
		C.close(pipes[1])
		_ := faultprobe.install(true) or { C._exit(125); return }
		page := unsafe { C.mmap(nil, 4096, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0) }
		if page == voidptr(-1) { C._exit(125) }
		// A real protection fault; the reported address must match this mapping.
		eprintln('IOS-PROBE-EXPECTED: address=0x' + u64(page).hex())
		unsafe { C.memset(page, 0x5a, 4096) }
		C._exit(125)
	}
	C.close(pipes[1])
	mut bytes := []u8{}
	mut buffer := [4096]u8{}
	for {
		count := C.read(pipes[0], &buffer[0], sizeof(buffer))
		if count <= 0 { break }
		bytes << buffer[..count]
	}
	C.close(pipes[0])
	mut status := i32(0)
	if C.waitpid(child, &status, 0) != child || status != 139 << 8 {
		return error('fault check unexpected wait status ${status}')
	}
	text := bytes.bytestr()
	address := strconv.parse_uint(text.all_after('IOS-PROBE-EXPECTED: address=0x').all_before('\n'), 16, 64)!
	if address == 0 { return error('fault check missing expected address') }
	expected := '${address:016x}'
	for marker in ['IOS-PROBE-FAULT: signal=0x000000000000000b code=0x0000000000000002',
		' address=0x' + expected,
		' fault_address=0x' + expected,
		' pc=0x', ' sp=0x', ' pstate=0x', '\nIOS-PROBE-REGS: x00=', ' x30='] {
		if !text.contains(marker) { return error('fault check missing ' + marker + ': ' + text) }
	}
	for label in ['pc', 'sp'] {
		if strconv.parse_uint(text.all_after(' ' + label + '=0x').all_before(' '), 16, 64)! == 0 {
			return error('fault check zero ' + label)
		}
	}
	if text.count(' x') != 31 || !text.ends_with('\n') { return error('incomplete register dump') }
	print(text)
	println('IOS-PROBE-FAULT: signal context and restoration PASS')
}
