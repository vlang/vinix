// SPDX-License-Identifier: GPL-2.0-or-later
// An instrumented private copy tests GCC's real unwinder, not Wine exceptions.
module main

import os
import time

#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>
#include <grp.h>
#include "libgcc.h"
fn C.dup2(i32, i32) i32
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.setgroups(uint, voidptr) i32
fn C.__register_frame(voidptr)
fn C.__deregister_frame(voidptr)
fn C._Unwind_Find_FDE(voidptr, voidptr) voidptr
type C._Unwind_Reason_Code = u32
struct C._Unwind_Context {}
fn C._Unwind_Backtrace(fn (&C._Unwind_Context, voidptr) C._Unwind_Reason_Code, voidptr) C._Unwind_Reason_Code
fn C._Unwind_GetIP(&C._Unwind_Context) u64
fn C._Unwind_GetGR(&C._Unwind_Context, i32) u64

struct Trace {
mut:
	parent u64
	seen bool
	correct bool
}

type Entry = fn ()

fn trace(context &C._Unwind_Context, argument voidptr) C._Unwind_Reason_Code {
	mut state := unsafe { &Trace(argument) }
	if C._Unwind_GetIP(context) != state.parent { return C._Unwind_Reason_Code(0) }
	state.seen = true
	state.correct = true
	for reg in [3, 6, 12, 13, 14, 15]! {
		if C._Unwind_GetGR(context, i32(reg)) != u64(0x13570000 + reg) { state.correct = false }
	}
	return C._Unwind_Reason_Code(4) // Stop before unwinding the test entry further.
}

fn invoke(argument voidptr) { C._Unwind_Backtrace(trace, argument) }

fn value(data string, at int, size int) u64 {
	mut result := u64(0)
	for i in 0 .. size { result |= u64(data[at + i]) << (i * 8) }
	return result
}

fn append64(mut bytes []u8, number u64) {
	for i in 0 .. 8 { bytes << u8(number >> (8 * i)) }
}

fn store32(mut bytes []u8, at int, number u32) {
	for i in 0 .. 4 { bytes[at + i] = u8(number >> (8 * i)) }
}

fn registers(mut code []u8, seed int) {
	for reg in [3, 6, 12, 13, 14, 15]! {
		machine := if reg == 6 { 5 } else { reg } // DWARF RBP=6, opcode RBP=5.
		code << if machine >= 8 { u8(0x49) } else { u8(0x48) }
		code << u8(0xb8 + machine % 8)
		append64(mut code, u64(seed + reg))
	}
}

fn run() ! {
	if C.setgroups(0, unsafe { nil }) != 0 || C.setgid(1000) != 0 || C.setuid(1000) != 0
		|| os.getuid() != 1000 || os.geteuid() != 1000 { return error('ordinary identity failed') }
	data := os.read_file('/usr/share/wine-unwind/ntdll.so')!
	defer { unsafe { data.free() } }
	if data.len != 0x8f58c || value(data, 0x38, 2) != 12 { return error('unexpected ELF fixture') }
	base := unsafe { C.mmap(nil, 0xc6000, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0) }
	if base == voidptr(-1) { return error('reserve image failed') }
	defer { unsafe { C.munmap(base, 0xc6000) } }
	for i in 0 .. 12 {
		ph := 0x40 + i * 56
		if value(data, ph, 4) != 1 { continue }
		off := value(data, ph + 8, 8)
		va := value(data, ph + 16, 8)
		filesz := value(data, ph + 32, 8)
		memsz := value(data, ph + 40, 8)
		if off > u64(data.len) || filesz > u64(data.len) - off || va > 0xc6000 || memsz > 0xc6000 - va {
			return error('fixture segment exceeds bounds')
		}
		start := va & ~u64(4095)
		length := ((va + memsz + 4095) & ~u64(4095)) - start
		if unsafe { C.mprotect(&u8(base) + start, length, C.PROT_READ | C.PROT_WRITE) } != 0 { return error('populate image failed') }
		unsafe { vmemcpy(&u8(base) + va, data.str + off, int(filesz)) }
	}
	// Instrument only this private in-memory copy. A callback replaces the first
	// move in the trampoline; the original pointer load/metadata OR/return jump
	// still run. The landing code returns through the matching compiler frame.
	call := '\x41\xff\xd3\x90\x90\x90\x90'
	epilogue := '\x48\x81\xc4\xd8\x10\x00\x00\x5b\x5d\x41\x5c\x41\x5d\x41\x5e\x41\x5f\xc3'
	unsafe { vmemcpy(&u8(base) + 0x61ba0, call.str, call.len); vmemcpy(&u8(base) + 0x5a377, epilogue.str, epilogue.len) }
	for i in 0 .. 12 {
		ph := 0x40 + i * 56
		if value(data, ph, 4) != 1 { continue }
		va := value(data, ph + 16, 8)
		end := va + value(data, ph + 40, 8)
		flags := value(data, ph + 4, 4)
		if flags & 3 == 3 { return error('fixture contains WX segment') }
		prot := (if flags & 4 != 0 { C.PROT_READ } else { 0 }) |
			(if flags & 2 != 0 { C.PROT_WRITE } else { 0 }) | (if flags & 1 != 0 { C.PROT_EXEC } else { 0 })
		if unsafe { C.mprotect(&u8(base) + (va & ~u64(4095)),
			((end + 4095) & ~u64(4095)) - (va & ~u64(4095)), prot) } != 0 { return error('seal image permissions failed') }
	}
	scratch := unsafe { C.mmap(nil, 8192, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0) }
	if scratch == voidptr(-1) { return error('allocate entry failed') }
	defer { unsafe { C.munmap(scratch, 8192) } }
	mut state := Trace{}
	mut view := [64]u8{}
	mut code := []u8{cap: 512}
	defer { unsafe { code.free() } }
	pushes := '\x41\x57\x41\x56\x41\x55\x41\x54\x55\x53'
	pops := '\x5b\x5d\x41\x5c\x41\x5d\x41\x5e\x41\x5f'
	for byte in pushes { code << byte }
	registers(mut code, 0x13570000)
	for byte in '\x48\x83\xec\x08' { code << byte }
	code << u8(0xe8)
	call_offset := code.len
	code << [u8(0), 0, 0, 0]
	parent := code.len
	code << u8(0x90)
	for byte in '\x48\x83\xc4\x08' { code << byte }
	for byte in pops { code << byte }
	code << u8(0xc3)
	inner := code.len
	store32(mut code, call_offset, u32(inner - parent))
	for byte in pushes { code << byte }
	for byte in '\x48\x81\xec\xd8\x10\x00\x00' { code << byte }
	// Distinct live values force the unwinder to use all six saved slots.
	registers(mut code, 0x24680000)
	for byte in '\x48\xb8' { code << byte }
	append64(mut code, u64(unsafe { &view[0] }))
	for byte in '\x48\x89\x84\x24\xb8\x00\x00\x00\x49\xbb' { code << byte }
	append64(mut code, u64(unsafe { voidptr(invoke) }))
	for byte in '\x48\xbf' { code << byte }
	append64(mut code, u64(unsafe { &state }))
	for byte in '\x48\xb8' { code << byte }
	append64(mut code, u64(base) + 0x5a368)
	for byte in '\xff\xe0' { code << byte }
	state.parent = u64(scratch) + u64(parent)
	// A test-only caller FDE covers the call return PC and its preceding byte
	// (GCC looks up saved return addresses at PC-1). Its caller state is not used.
	mut frames := []u8{len: 60}
	defer { unsafe { frames.free() } }
	cie := '\x14\x00\x00\x00\x00\x00\x00\x00\x01zR\x00\x01\x78\x10\x01\x1b\x0c\x07\x08\x90\x01\x00\x00'
	unsafe { vmemcpy(frames.data, cie.str, cie.len) }
	store32(mut frames, 24, 28)
	store32(mut frames, 28, 28)
	store32(mut frames, 32, u32(i32(parent - 1 - 4096 - 32)))
	store32(mut frames, 36, 2)
	rules := '\x00\x0e\x40\x8f\x02\x8e\x03\x8d\x04\x8c\x05\x86\x06\x83\x07\x00'
	unsafe { vmemcpy(&frames[40], rules.str, rules.len); vmemcpy(scratch, code.data, code.len); vmemcpy(&u8(scratch) + 4096, frames.data, frames.len) }
	if unsafe { C.mprotect(scratch, 4096, C.PROT_READ | C.PROT_EXEC) } != 0
		|| unsafe { C.mprotect(&u8(scratch) + 4096, 4096, C.PROT_READ) } != 0 { return error('seal entry failed') }
	C.__register_frame(unsafe { &u8(scratch) + 4096 })
	defer { C.__deregister_frame(unsafe { &u8(scratch) + 4096 }) }
	entry := unsafe { Entry(scratch) }
	for positive in [false, true]! {
		println('HWTEST INFO Wine unwind starting positive=' + positive.str())
		state.seen = false
		state.correct = false
		frame := unsafe { &u8(base) + if positive { u64(0xb9060) } else { u64(0x75290) } }
		C.__register_frame(frame)
		mut bases := [3]u64{}
		found := C._Unwind_Find_FDE(unsafe { &u8(base) + 0x61ba3 }, unsafe { voidptr(&bases[0]) })
		entry()
		C.__deregister_frame(frame)
		if C._Unwind_Find_FDE(unsafe { &u8(base) + 0x61ba3 }, unsafe { voidptr(&bases[0]) }) != unsafe { nil } {
			return error('trampoline frame remained registered after retirement')
		}
		if positive {
			if found != unsafe { &u8(base) + 0xc3f58 } || !state.seen || !state.correct || view[0x30] & 4 == 0 {
				return error('GCC failed to recover trampoline caller/registers')
			}
		} else if found != unsafe { nil } || state.seen { return error('missing-FDE control unexpectedly unwound trampoline') }
	}
}

fn main() {
	fd := C.open(c'/dev/com1', C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	run() or { eprintln('HWTEST FAIL Wine unwind: ' + err.msg()); for { time.sleep(time.second) } }
	println('HWTEST PASS Wine unwind: actual GCC trampoline caller and six registers; missing-FDE control refused')
	for { time.sleep(time.second) }
}
