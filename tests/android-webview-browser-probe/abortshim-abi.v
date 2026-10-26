// SPDX-License-Identifier: GPL-2.0-or-later
// Host ABI check: only a forked child calls the separately loaded abort DSO.
@[has_globals]
module main

import os
import strconv

#include <dlfcn.h>
#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <errno.h>

@[typedef]
struct C.Dl_info {
mut:
	dli_fbase voidptr
}

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dladdr(voidptr, &C.Dl_info) i32
fn C.dlclose(voidptr) i32
fn C.pipe(&i32) i32
fn C.close(i32) i32
fn C.dup2(i32, i32) i32
fn C.read(i32, voidptr, uint) int
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)

@[c_extern]
__global C.errno i32

type NativeAbort = fn ()

@[noinline]
fn call_abort(target voidptr) {
	unsafe { NativeAbort(target)() }
	// Keep a real return point in this frame; do not tail-call the DSO.
	C._exit(99)
}

fn check(path string) ! {
	handle := C.dlopen(path.str, C.RTLD_NOW | C.RTLD_LOCAL)
	if handle == unsafe { nil } { return error('cannot load diagnostic DSO') }
	defer { C.dlclose(handle) }
	target := C.dlsym(handle, c'abort')
	if target == unsafe { nil } { return error('native abort export missing') }
	mut shim := C.Dl_info{}
	mut main_image := C.Dl_info{}
	if C.dladdr(target, &shim) == 0 || C.dladdr(voidptr(call_abort), &main_image) == 0
		|| shim.dli_fbase == main_image.dli_fbase {
		return error('fixture and diagnostic must be different native images')
	}
	mut pipes := [2]i32{}
	if C.pipe(&pipes[0]) != 0 { return error('capture pipe failed') }
	pid := C.fork()
	if pid < 0 { C.close(pipes[0]); C.close(pipes[1]); return error('fork failed') }
	if pid == 0 {
		C.close(pipes[0])
		if C.dup2(pipes[1], 2) != 2 { C._exit(98) }
		C.close(pipes[1])
		call_abort(target)
		C._exit(99)
	}
	C.close(pipes[1])
	mut bytes := [1024]u8{}
	mut used := 0
	mut read_failed := false
	for used < bytes.len {
		n := C.read(pipes[0], unsafe { &bytes[used] }, uint(bytes.len - used))
		if n < 0 {
			if unsafe { C.errno == C.EINTR } { continue }
			read_failed = true
			break
		}
		if n == 0 { break }
		used += int(n)
	}
	C.close(pipes[0])
	mut status := i32(0)
	mut reaped := C.waitpid(pid, &status, 0)
	for reaped < 0 && unsafe { C.errno == C.EINTR } { reaped = C.waitpid(pid, &status, 0) }
	if read_failed { return error('diagnostic record read failed') }
	if reaped != pid || status & 127 != C.SIGABRT {
		return error('diagnostic did not forward native SIGABRT')
	}
	text := bytes[..used].bytestr()
	if !text.ends_with('\n') || text.count('\n') != 1 {
		return error('exactly one bounded record required')
	}
	fields := text.trim_space().split(' ')
	if fields.len != 6 || fields[0] != 'BROWSER-ABORT' { return error('record format differs') }
	mut values := []u64{}
	for index, name in ['caller', 'module-base', 'offset', 'resolved', 'native'] {
		field := fields[index + 1]
		value := field.all_after('=')
		if !field.starts_with(name + '=') || value == '' || !value.bytes().all(it >= `0` && it <= `9`) {
			return error('record is not numeric')
		}
		values << strconv.parse_uint(value, 10, 64)!
	}
	mut caller := C.Dl_info{}
	if values[3] != 1 || values[4] != 1 || values[0] < values[1]
		|| values[0] - values[1] != values[2]
		|| C.dladdr(voidptr(values[0]), &caller) == 0
		|| caller.dli_fbase != main_image.dli_fbase || caller.dli_fbase == shim.dli_fbase
		|| values[1] != u64(main_image.dli_fbase) {
		return error('captured PC does not belong to original caller image')
	}
	println('BROWSER-ABORT-ABI PASS native-export original-caller-image numeric-module-offset one-record native-SIGABRT child-only')
}

fn main() {
	if os.args.len != 2 { eprintln('usage: abortshim-abi NATIVE_DSO'); exit(1) }
	check(os.real_path(os.args[1])) or { eprintln(err); exit(1) }
}
