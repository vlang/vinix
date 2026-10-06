// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.rand

#include <math.h>
#include <strings.h>

fn C.acos(f64) f64
fn C.asin(f64) f64
fn C.atan(f64) f64
fn C.cos(f64) f64
fn C.cosh(f64) f64
fn C.exp(f64) f64
fn C.fabs(f64) f64
fn C.log(f64) f64
fn C.sin(f64) f64
fn C.sinh(f64) f64
fn C.tan(f64) f64
fn C.tanh(f64) f64
fn C.strcasecmp(&char, &char) int
fn C.ios_host_stdio(int) voidptr

struct SystemData {
mut:
	guard u64
	page_size u64
	task_self u32
	main_queue [8]u64
	main_jobs []u64
	in6_any [16]u8
	standard [3]u64
	streams map[u64]voidptr
	runes voidptr
	mutexes map[u64]voidptr
	conditions map[u64]voidptr
	once map[u64]voidptr
	dl_error string
	dl_error_pending bool
	dispatch_once map[u64]voidptr
}

__global system_data = unsafe { &SystemData(nil) }

fn system_data_start() ! {
	system_data = &SystemData{page_size: u64(C.getpagesize()), task_self: 1}
	system_data.main_jobs.flags |= .noslices
	bytes := rand.bytes(8)!
	unsafe { C.memcpy(&system_data.guard, bytes.data, 8); bytes.free() }
	// Darwin FILE's public ARM64 ABI is 152 bytes. Zero-sized read/write
	// buffers force compiler-inlined getc/putc through the exported adapters.
	for i in 0 .. 3 {
		file := C.calloc(1, 152)
		if file == unsafe { nil } { return error('iOS: cannot allocate standard stream') }
		system_data.standard[i] = u64(file)
		system_data.streams[u64(file)] = C.ios_host_stdio(i)
		unsafe { *(&u16(u64(file) + 16)) = if i == 0 { u16(4) } else { u16(8) }
			*(&u16(u64(file) + 18)) = u16(i) }
	}
	system_data.runes = C.calloc(1, 3184)
	if system_data.runes == unsafe { nil } { return error('iOS: cannot allocate rune locale') }
	base := u64(system_data.runes)
	C.memcpy(system_data.runes, c'RuneMagA', 8)
	unsafe { C.memcpy(voidptr(base + 8), c'NONE', 5) }
	write32(base + 56, 0xfffd)
	for i in 0 .. 256 {
		mut flags := u32(0)
		if i < 32 || i == 127 { flags |= 0x200 }
		if i == 32 || (i >= 9 && i <= 13) { flags |= 0x4000 }
		if i == 32 || i == 9 { flags |= 0x20000 }
		if i >= 32 && i <= 126 { flags |= 0x40000 | 0x40000000 }
		if i >= 33 && i <= 126 { flags |= 0x800 }
		if i >= 48 && i <= 57 { flags |= 0x400 | 0x10000 | u32(i - 48) }
		if i >= 65 && i <= 90 { flags |= 0x100 | 0x8000 }
		if i >= 97 && i <= 122 { flags |= 0x100 | 0x1000 }
		if (i >= 65 && i <= 70) || (i >= 97 && i <= 102) { flags |= 0x10000 | u32((i & ~32) - 65 + 10) }
		if flags & 0x800 != 0 && flags & 0x500 == 0 { flags |= 0x2000 }
		write32(base + 60 + u64(i) * 4, flags)
		write32(base + 1084 + u64(i) * 4, u32(if i >= 65 && i <= 90 { i + 32 } else { i }))
		write32(base + 2108 + u64(i) * 4, u32(if i >= 97 && i <= 122 { i - 32 } else { i }))
	}
}

fn system_data_stop() {
	if system_data == unsafe { nil } { return }
	for _, pointer in system_data.mutexes {
		if C.pthread_mutex_destroy(pointer) != 0 { panic('iOS: active mutex at image shutdown') }
		C.free(pointer)
	}
	for _, pointer in system_data.conditions {
		if C.pthread_cond_destroy(pointer) != 0 { panic('iOS: active condition at image shutdown') }
		C.free(pointer)
	}
	for _, pointer in system_data.once { C.free(pointer) }
	for _, pointer in system_data.dispatch_once {
		if C.pthread_mutex_destroy(pointer) != 0 { panic('iOS: active dispatch_once at image shutdown') }
		C.free(pointer)
	}
	for file, native in system_data.streams {
		if native != C.ios_host_stdio(0) && native != C.ios_host_stdio(1) && native != C.ios_host_stdio(2) { C.fclose(native) }
		C.free(unsafe { voidptr(file) })
	}
	C.free(system_data.runes)
	unsafe { system_data.dl_error.free() }
	unsafe { system_data.streams.free(); system_data.mutexes.free(); system_data.conditions.free(); system_data.once.free(); system_data.dispatch_once.free(); free(system_data) }
	system_data = unsafe { nil }
}

fn system_data_symbol(symbol string) ?u64 {
	return match symbol {
		'___stack_chk_guard' { u64(unsafe { &system_data.guard }) }
		'___stdinp' { u64(unsafe { &system_data.standard[0] }) }
		'___stdoutp' { u64(unsafe { &system_data.standard[1] }) }
		'___stderrp' { u64(unsafe { &system_data.standard[2] }) }
		'__DefaultRuneLocale' { u64(system_data.runes) }
		'__dispatch_main_q' { u64(unsafe { &system_data.main_queue[0] }) }
		'_in6addr_any' { u64(unsafe { &system_data.in6_any[0] }) }
		'_mach_task_self_' { u64(unsafe { &system_data.task_self }) }
		'_vm_page_size' { u64(unsafe { &system_data.page_size }) }
		'_acos' { u64(unsafe { voidptr(C.acos) }) }
		'_asin' { u64(unsafe { voidptr(C.asin) }) }
		'_atan' { u64(unsafe { voidptr(C.atan) }) }
		'_cos' { u64(unsafe { voidptr(C.cos) }) }
		'_cosh' { u64(unsafe { voidptr(C.cosh) }) }
		'_exp' { u64(unsafe { voidptr(C.exp) }) }
		'_fabs' { u64(unsafe { voidptr(C.fabs) }) }
		'_log' { u64(unsafe { voidptr(C.log) }) }
		'_sin' { u64(unsafe { voidptr(C.sin) }) }
		'_sinh' { u64(unsafe { voidptr(C.sinh) }) }
		'_tan' { u64(unsafe { voidptr(C.tan) }) }
		'_tanh' { u64(unsafe { voidptr(C.tanh) }) }
		'_strcasecmp' { u64(unsafe { voidptr(C.strcasecmp) }) }
		else { return none }
	}
}
