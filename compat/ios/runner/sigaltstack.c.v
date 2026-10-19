// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <signal.h>

fn C.sigaltstack(voidptr, voidptr) i32

@[typedef]
struct C.stack_t {
mut:
	ss_sp voidptr
	ss_size usize
	ss_flags i32
}

// Darwin retains the last descriptor while disabled; Linux clears it. These
// two process-lifetime native TSD slots preserve scalar values, with no stack
// ownership, per-call allocation or registry lock in a signal callback.
__global sigaltstack_sp_key = u64(0)
__global sigaltstack_size_key = u64(0)
__global sigaltstack_keys_ready = u64(0)

// Called under the signal namespace lock before any bridge callback can run.
fn sigaltstack_start() ! {
	$if linux {
		if C.ios_load_pointer(unsafe { &sigaltstack_keys_ready }) != 0 { return }
		mut sp := u64(0); mut size := u64(0)
		if C.pthread_key_create(unsafe { voidptr(&sp) }, unsafe { nil }) != 0 { return error('iOS: cannot reserve alternate-stack pointer slot') }
		if C.pthread_key_create(unsafe { voidptr(&size) }, unsafe { nil }) != 0 {
			C.pthread_key_delete(sp); return error('iOS: cannot reserve alternate-stack size slot')
		}
		sigaltstack_sp_key = sp; sigaltstack_size_key = size
		C.ios_store_pointer(unsafe { &sigaltstack_keys_ready }, 1)
	}
}

fn sigaltstack_fork_child() {
	$if linux {
		if C.ios_load_pointer(unsafe { &sigaltstack_keys_ready }) != 0 {
			C.pthread_setspecific(sigaltstack_sp_key, unsafe { nil })
			C.pthread_setspecific(sigaltstack_size_key, unsafe { nil })
		}
	}
}

fn darwin_sigaltstack(input voidptr, output voidptr) i32 {
	previous := unsafe { *C.ios_errno_address() }
	$if macos { return darwin_process_result(C.sigaltstack(input, output), previous) }
	// Darwin libc checks the original size before the kernel writes old_ss,
	// even for SS_DISABLE and for overlapping input/output records.
	if input != unsafe { nil } {
		mut size := u64(0)
		unsafe { C.memcpy(voidptr(&size), voidptr(u64(input) + 8), 8) }
		if size < 32768 { darwin_set_errno(12); return -1 }
	}
	if C.ios_load_pointer(unsafe { &sigaltstack_keys_ready }) == 0 { darwin_set_errno(22); return -1 }
	mut old := C.stack_t{}
	if C.sigaltstack(unsafe { nil }, unsafe { voidptr(&old) }) != 0 { return darwin_process_result(-1, previous) }
	if old.ss_flags & ~i32(C.SS_ONSTACK | C.SS_DISABLE) != 0 { darwin_set_errno(45); return -1 }
	mut words := [3]u64{}
	if old.ss_flags & i32(C.SS_DISABLE) != 0 {
		words = [u64(C.pthread_getspecific(sigaltstack_sp_key)), u64(C.pthread_getspecific(sigaltstack_size_key)), u64(4)]!
	} else {
		for pair in [[sigaltstack_sp_key, u64(old.ss_sp)]!, [sigaltstack_size_key, u64(old.ss_size)]!]! {
			result := C.pthread_setspecific(pair[0], voidptr(pair[1]))
			if result != 0 { darwin_set_errno(i32(darwin_native_error(result))); return -1 }
		}
		words = [u64(old.ss_sp), u64(old.ss_size), u64(old.ss_flags & i32(C.SS_ONSTACK) != 0)]!
	}
	// Native Darwin writes the old descriptor before validating flags or
	// applying the update. Re-read input afterwards to preserve alias behavior.
	if output != unsafe { nil } { unsafe { C.memcpy(output, voidptr(&words[0]), 24) } }
	if input == unsafe { nil } { darwin_set_errno(previous); return 0 }
	unsafe { C.memcpy(voidptr(&words[0]), input, 24) }
	flags := i32(u32(words[2]))
	if flags != 0 && flags != 4 { darwin_set_errno(22); return -1 }
	if old.ss_flags & i32(C.SS_ONSTACK) != 0 {
		darwin_set_errno(if flags == 4 { i32(22) } else { i32(1) }); return -1
	}
	mut native := C.stack_t{ss_sp: voidptr(words[0]), ss_size: usize(words[1]), ss_flags: if flags == 4 { i32(C.SS_DISABLE) } else { i32(0) }}
	return darwin_process_result(C.sigaltstack(unsafe { voidptr(&native) }, unsafe { nil }), previous)
}
