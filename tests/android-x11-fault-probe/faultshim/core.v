// SPDX-License-Identifier: GPL-2.0-or-later
// Diagnostic only: no heap, stdio, symbol lookup or unwinder in the handler.
@[has_globals]
module faultshim

#include <signal.h>
#include <unistd.h>
#include <fcntl.h>
#include <dlfcn.h>
#include <errno.h>
#include <sched.h>
#define vinix_const_action const struct sigaction *

@[typedef]
struct C.vinix_const_action {}

@[typedef]
struct C.sigset_t {}
struct C.sigaction {
mut:
	sa_sigaction fn (i32, voidptr, voidptr)
	sa_handler fn (i32)
	sa_mask C.sigset_t
	sa_flags i32
}

type NativeAction = fn (i32, voidptr, voidptr) i32
type Handler = fn (i32)

struct Record {
mut:
	action C.sigaction
}

struct Line {
mut:
	bytes [2048]u8
	used int
}

__global (
	xfp_native_action NativeAction
	xfp_records [1024]Record
	xfp_next_record int
	xfp_active [65]usize
	xfp_mutation_lock u8
)

@[c_extern]
__global C.errno i32

fn C.dlsym(voidptr, &char) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.write(i32, voidptr, usize) isize
fn C.read(i32, voidptr, usize) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.sigfillset(&C.sigset_t) i32
fn C.sigprocmask(i32, &C.sigset_t, &C.sigset_t) i32
fn C.sched_yield() i32
fn C.__atomic_load_n(&usize, i32) usize
fn C.__atomic_store_n(&usize, usize, i32)
fn C.__atomic_test_and_set(&u8, i32) bool
fn C.__atomic_clear(&u8, i32)

fn watched(number i32) bool {
	return number in [4, 5, 6, 7, 8, 11]
}

// Append-only records allow a concurrently executing signal handler to read
// its complete disposition without taking a lock or observing a partial copy.
// Exhaustion falls through to native sigaction instead of changing its result.
pub fn interposed(number i32, input voidptr, output voidptr) i32 {
	unsafe {
		mut mask := C.sigset_t{}
		mut previous_mask := C.sigset_t{}
		C.sigfillset(&mask)
		if C.sigprocmask(C.SIG_BLOCK, &mask, &previous_mask) != 0 { return -1 }
		for C.__atomic_test_and_set(&xfp_mutation_lock, 2) { C.sched_yield() }
		if voidptr(xfp_native_action) == nil {
			xfp_native_action = NativeAction(C.dlsym(voidptr(usize(-1)), c'sigaction'))
		}
		if voidptr(xfp_native_action) == nil {
			C.__atomic_clear(&xfp_mutation_lock, 3)
			C.sigprocmask(C.SIG_SETMASK, &previous_mask, nil)
			C.errno = C.ENOSYS
			return -1
		}
		old_record := if number > 0 && number < 65 {
			C.__atomic_load_n(&xfp_active[number], 2)
		} else { usize(0) }
		mut requested := C.sigaction{}
		mut installed := C.sigaction{}
		mut candidate := usize(0)
		mut actual_input := input
		if input != nil && watched(number) {
			C.memcpy(&requested, input, sizeof(C.sigaction))
			C.memcpy(&installed, input, sizeof(C.sigaction))
			if usize(voidptr(requested.sa_handler)) > 1 && xfp_next_record < xfp_records.len {
				xfp_records[xfp_next_record].action = requested
				candidate = usize(&xfp_records[xfp_next_record])
				xfp_next_record++
				installed.sa_sigaction = caught
				installed.sa_flags |= C.SA_SIGINFO
				actual_input = &installed
			}
			// Publish before installation: another thread may receive the new
			// handler immediately after the real syscall returns.
			C.__atomic_store_n(&xfp_active[number], candidate, 3)
		}
		result := xfp_native_action(number, actual_input, output)
		saved_errno := C.errno
		if result != 0 && input != nil && watched(number) {
			C.__atomic_store_n(&xfp_active[number], old_record, 3)
		}
		if result == 0 && output != nil && old_record != 0 {
			old := &C.sigaction(output)
			if voidptr(old.sa_sigaction) == voidptr(caught) {
				record := &Record(old_record)
				C.memcpy(output, &record.action, sizeof(C.sigaction))
			}
		}
		C.__atomic_clear(&xfp_mutation_lock, 3)
		C.sigprocmask(C.SIG_SETMASK, &previous_mask, nil)
		C.errno = saved_errno
		return result
	}
}

// Match libc's const-qualified prototype exactly while keeping the ABI shim
// declarative. All behavior lives in V above.
$if fault_probe_preload ? {
	@[export: 'vinix_x11_fault_probe_version']
	pub fn version() i32 { return 1 }

	@[export: 'sigaction']
	pub fn native_interposed(number i32, input C.vinix_const_action, output &C.sigaction) i32 {
		unsafe {
			mut pointer := voidptr(0)
			C.memcpy(&pointer, &input, sizeof(voidptr))
			return interposed(number, pointer, output)
		}
	}
}

fn write_all(data &u8, size int) {
	unsafe {
		mut offset := 0
		for offset < size {
			n := C.write(2, data + offset, usize(size - offset))
			if n <= 0 { return }
			offset += int(n)
		}
	}
}

fn (mut line Line) literal(text &char) {
	unsafe {
		mut i := 0
		for text[i] != 0 && line.used < line.bytes.len {
			line.bytes[line.used] = u8(text[i]); line.used++; i++
		}
	}
}

fn (mut line Line) hexadecimal(value u64) {
	unsafe {
		for i in 0 .. 16 {
			if line.used >= line.bytes.len { return }
			nibble := u8((value >> u32((15 - i) * 4)) & 15)
			line.bytes[line.used] = if nibble < 10 { `0` + nibble } else { `a` + nibble - 10 }
			line.used++
		}
	}
}

fn (mut line Line) field(label &char, value u64) {
	line.literal(label)
	line.hexadecimal(value)
}

// Linux AArch64 musl ucontext_t. Keep these offsets aligned with the native
// kernel ABI, not V struct packing. Synthetic context tests cover every field.
pub fn report(info voidptr, context voidptr) {
	unsafe {
		mut line := Line{}
		line.literal(c'X11-FAULT')
		if info != nil {
			line.field(c' signal=0x', u64(*&u32(info)))
			line.field(c' code=0x', u64(*&u32(&u8(info) + 8)))
			line.field(c' address=0x', *&u64(&u8(info) + 16))
		}
		if context != nil {
			line.field(c' pc=0x', *&u64(&u8(context) + 440))
			line.field(c' sp=0x', *&u64(&u8(context) + 432))
			line.field(c' pstate=0x', *&u64(&u8(context) + 448))
			line.literal(c'\nX11-REGS')
			for i in 0 .. 31 {
				line.literal(c' x')
				line.bytes[line.used] = `0` + u8(i / 10); line.used++
				line.bytes[line.used] = `0` + u8(i % 10); line.used++
				line.field(c'=0x', *&u64(&u8(context) + 184 + i * 8))
			}
		}
		line.literal(c'\n')
		write_all(&line.bytes[0], line.used)
	}
}

fn maps() {
	unsafe {
		fd := C.open(c'/proc/self/maps', C.O_RDONLY | C.O_CLOEXEC)
		if fd < 0 { return }
		mut buffer := [4096]u8{}
		write_all(c'X11-MAPS-BEGIN\n', 15)
		for _ in 0 .. 32 {
			n := C.read(fd, &buffer[0], sizeof(buffer))
			if n <= 0 { break }
			write_all(&buffer[0], int(n))
		}
		C.close(fd)
		write_all(c'X11-MAPS-END\n', 13)
	}
}

fn caught(number i32, info voidptr, context voidptr) {
	unsafe {
		if number < 1 || number >= 65 { return }
		record := C.__atomic_load_n(&xfp_active[number], 2)
		if record == 0 { return }
		saved := &Record(record)
		action := &saved.action
		saved_errno := C.errno
		// A reset disposition is already reset by the kernel on entry. Keep
		// queries/restores faithful before chaining a handler that changes it.
		if action.sa_flags & C.SA_RESETHAND != 0 {
			C.__atomic_store_n(&xfp_active[number], 0, 3)
		}
		report(info, context)
		maps()
		C.errno = saved_errno
		if action.sa_flags & C.SA_SIGINFO != 0 {
			action.sa_sigaction(number, info, context)
		} else { action.sa_handler(number) }
	}
}
