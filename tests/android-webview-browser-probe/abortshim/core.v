// SPDX-License-Identifier: GPL-2.0-or-later
// Separate credential-free diagnostic. Forward the exported abort call once.
@[has_globals]
module main

#include <unistd.h>
#include <dlfcn.h>
#include <errno.h>
#define vinix_browser_abort abort
// V's Darwin shared-library export list still names the V source export.
// Retain that name as an alias to the same entry without adding a call frame.
#flag darwin -Wl,-alias,_abort,_vinix_browser_abort
#flag darwin -Wl,-exported_symbol,_abort

@[typedef]
struct C.Dl_info {
mut:
	dli_fbase voidptr
}

type NativeAbort = fn ()

struct Line {
mut:
	bytes [192]u8
	used int
}

__global (
	ap_reported u8
	ap_active u8
)

@[c_extern]
__global C.errno i32

fn C.dlsym(voidptr, &char) voidptr
fn C.dladdr(voidptr, &C.Dl_info) i32
fn C.write(i32, voidptr, uint) int
fn C._exit(i32)
fn C.__atomic_test_and_set(&u8, i32) bool
fn C.__builtin_return_address(i32) voidptr
fn C.__builtin_extract_return_addr(voidptr) voidptr

fn (mut line Line) literal(value &char) {
	unsafe {
		mut i := 0
		for value[i] != 0 && line.used < line.bytes.len {
			line.bytes[line.used] = u8(value[i]); line.used++; i++
		}
	}
}

fn (mut line Line) number(value u64) {
	unsafe {
		mut magnitude := value
		mut digits := [20]u8{}
		mut count := 0
		for {
			digits[count] = `0` + u8(magnitude % 10)
			count++; magnitude /= 10
			if magnitude == 0 { break }
		}
		for count > 0 && line.used < line.bytes.len {
			count--; line.bytes[line.used] = digits[count]; line.used++
		}
	}
}

fn report(caller uint, native uint) {
	unsafe {
		// No lock is held across symbol lookup, reporting or native abort.
		// Repeated/concurrent abort calls can emit at most this one record.
		if C.__atomic_test_and_set(&ap_reported, 2) { return }
		mut info := C.Dl_info{}
		resolved := C.dladdr(voidptr(caller), &info) != 0 && info.dli_fbase != nil
		base := if resolved { uint(info.dli_fbase) } else { uint(0) }
		offset := if resolved && caller >= base { caller - base } else { uint(0) }
		mut line := Line{}
		line.literal(c'BROWSER-ABORT caller='); line.number(u64(caller))
		line.literal(c' module-base='); line.number(u64(base))
		line.literal(c' offset='); line.number(u64(offset))
		line.literal(c' resolved='); line.number(u64(resolved))
		line.literal(c' native='); line.number(u64(native != 0))
		line.literal(c'\n')
		// One bounded write, no path/argv/account data or retry on failure.
		C.write(2, &line.bytes[0], uint(line.used))
	}
}

// Split forwarding from lookup so host tests can use a returning stub without
// calling the real abort in the parent. Production's exported entry is fatal.
pub fn forward(caller uint, native uint, incoming_errno i32) {
	unsafe {
		report(caller, native)
		C.errno = incoming_errno
		if native == 0 { C._exit(127) }
		NativeAbort(native)()
	}
}

@[noreturn]
pub fn dispatch(caller uint, native uint, incoming_errno i32) {
	forward(caller, native, incoming_errno)
	C._exit(127)
	for {}
}

pub fn interposed(caller uint) {
	unsafe {
		incoming_errno := C.errno
		// An abort reentered during loader lookup/reporting cannot safely
		// repeat those operations. Keep this diagnostic failure fatal.
		if C.__atomic_test_and_set(&ap_active, 2) { C._exit(127) }
		// RTLD_NEXT resolves from this DSO to libc, never the public wrapper.
		address := uint(C.dlsym(voidptr(uint(-1)), c'abort'))
		dispatch(caller, address, incoming_errno)
	}
}

$if abort_probe_preload ? {
	// The natural V export name avoids a generated forwarding frame. The
	// native preprocessor name alias binds that same body to libc's symbol.
	// Capture here before calling any helper; inlining changes frame meaning.
	@[export: 'vinix_browser_abort'; noreturn; noinline]
	pub fn vinix_browser_abort() {
		unsafe {
			caller := uint(C.__builtin_extract_return_addr(C.__builtin_return_address(0)))
			interposed(caller)
			// A missing or unexpectedly returning backend remains fatal without
			// recursing into abort or substituting a successful process exit.
			C._exit(127)
		}
		for {}
	}
}
