// SPDX-License-Identifier: GPL-2.0-or-later
module faultprobe

import os

#include <signal.h>
$if linux {
	#include <ucontext.h>
}
#include <unistd.h>
#include <string.h>

@[typedef]
struct C.siginfo_t {
	si_code int
	si_addr voidptr
}

@[typedef]
struct C.mcontext_t {
	fault_address u64
	regs [31]u64
	sp u64
	pc u64
	pstate u64
}

@[typedef]
struct C.ucontext_t {
	uc_mcontext C.mcontext_t
}

fn C.write(int, voidptr, usize) isize
fn C._exit(int)
fn C.__builtin_alloca(usize) voidptr

type NativeAction = fn (int, voidptr, voidptr) int

pub struct State {
mut:
	installed int
	original [3][24]u64
}

fn action(number int, input voidptr, output voidptr) int {
	// The frozen V os declaration narrows oldact to int.
	function := unsafe { NativeAction(voidptr(C.sigaction)) }
	return function(number, input, output)
}

fn number(index int) int {
	return match index { 0 { C.SIGSEGV } 1 { C.SIGBUS } else { C.SIGILL } }
}

// Installed only for the explicit diagnostic launch, before Darwin handlers
// can save their native predecessor. Restore after those handlers stop.
pub fn install(enabled bool) !State {
	mut state := &State(C.__builtin_alloca(sizeof(State)))
	unsafe { C.memset(state, 0, sizeof(State)) }
	if !enabled { return *state }
	$if linux && arm64 {
		if sizeof(C.sigaction) > sizeof(state.original[0]) {
			return error('fault probe: native sigaction exceeds saved storage')
		}
		mut native := &C.sigaction(C.__builtin_alloca(sizeof(C.sigaction)))
		unsafe { C.memset(native, 0, sizeof(C.sigaction)) }
		callback := voidptr(report)
		unsafe { C.memcpy(native, &callback, sizeof(callback)) }
		native.sa_flags = C.SA_SIGINFO
		for index in 0 .. 3 {
			if action(number(index), native, unsafe { &state.original[index][0] }) != 0 {
				cause := os.last_error()
				restore(mut state)!
				return error('fault probe: install: ' + cause.msg())
			}
			state.installed++
		}
	}
	return *state
}

pub fn restore(mut state State) ! {
	mut failed := false
	for state.installed > 0 {
		state.installed--
		index := state.installed
		if action(number(index), unsafe { &state.original[index][0] }, unsafe { nil }) != 0 {
			failed = true
		}
	}
	if failed { return error('fault probe: restore native signal disposition') }
}

struct ReportBuffer {
mut:
	bytes [4096]u8
	len int
}

fn (mut buffer ReportBuffer) append(value string) {
	for byte in value {
		unsafe { buffer.bytes[buffer.len] = byte; buffer.len += 1 }
	}
}

fn (mut buffer ReportBuffer) hex(value u64) {
	buffer.append('0x')
	for shift := 60; shift >= 0; shift -= 4 {
		unsafe {
			buffer.bytes[buffer.len] = '0123456789abcdef'[int((value >> u32(shift)) & 15)]
			buffer.len += 1
		}
	}
}

fn (mut buffer ReportBuffer) field(label string, value u64) {
	buffer.append(label)
	buffer.hex(value)
}

// A single bounded stack buffer, constant labels, kernel-supplied context and
// async-signal-safe syscalls only. Never dereference the fault address or PC.
fn report(signal int, info &C.siginfo_t, raw voidptr) {
	$if linux && arm64 {
		// Passing a V local by mutable reference can promote it to the heap.
		mut buffer := &ReportBuffer(C.__builtin_alloca(sizeof(ReportBuffer)))
		buffer.len = 0
		buffer.field('IOS-PROBE-FAULT: signal=', u64(signal))
		if info != unsafe { nil } {
			buffer.field(' code=', u64(i64(info.si_code)))
			buffer.field(' address=', u64(info.si_addr))
		}
		if raw != unsafe { nil } {
			context := unsafe { &C.ucontext_t(raw) }
			buffer.field(' fault_address=', context.uc_mcontext.fault_address)
			buffer.field(' pc=', context.uc_mcontext.pc)
			buffer.field(' sp=', context.uc_mcontext.sp)
			buffer.field(' pstate=', context.uc_mcontext.pstate)
			buffer.append('\nIOS-PROBE-REGS:')
			mut tens := u8(`0`)
			mut ones := u8(`0`)
			for index in 0 .. 31 {
				buffer.append(' x')
				unsafe {
					buffer.bytes[buffer.len] = tens
					buffer.bytes[buffer.len + 1] = ones
					buffer.len += 2
				}
				buffer.field('=', unsafe { context.uc_mcontext.regs[index] })
				ones++
				if ones == `:` { ones = `0`; tens++ }
			}
		}
		buffer.append('\n')
		mut written := isize(0)
		for written < buffer.len {
			count := unsafe { C.write(2, &buffer.bytes[written], usize(buffer.len - written)) }
			if count <= 0 { break }
			written += count
		}
	}
	C._exit(128 + signal)
}
