// SPDX-License-Identifier: GPL-2.0-or-later
module main

import sync.stdatomic

$if linux {
	#include <sys/syscall.h>
	#include <unistd.h>
	fn C.syscall(i64, ...i64) i64
}

type UnfairNativeWait = fn (u32, voidptr, u64, u32) i32
type UnfairNativeWake = fn (u32, voidptr, u64) i32

__global unfair_macos_once = u64(0)
__global unfair_macos_wait = unsafe { UnfairNativeWait(nil) }
__global unfair_macos_wake = unsafe { UnfairNativeWake(nil) }

fn unfair_macos_initialize() {
	$if macos {
		unfair_macos_wait = unsafe { UnfairNativeWait(C.dlsym(voidptr(-2), c'__ulock_wait')) }
		unfair_macos_wake = unsafe { UnfairNativeWake(C.dlsym(voidptr(-2), c'__ulock_wake')) }
		if unfair_macos_wait == unsafe { nil } || unfair_macos_wake == unsafe { nil } { panic('iOS: native address waits unavailable') }
	}
}

fn unfair_atomic(pointer &u32) &stdatomic.AtomicVal[u32] {
	if pointer == unsafe { nil } || u64(pointer) & 3 != 0 { panic('iOS: unfair lock requires an aligned four-byte word') }
	return unsafe { &stdatomic.AtomicVal[u32](pointer) }
}

fn unfair_load(pointer &u32) u32 {
	return C.atomic_load_u32(unfair_atomic(pointer))
}

fn unfair_compare(pointer &u32, expected u32, desired u32) bool {
	mut observed := expected
	// Use the installed V atomic primitive with a stack expected-value slot;
	// AtomicVal's generic CAS method can promote its temporary to the heap.
	return C.atomic_compare_exchange_strong_u32(unfair_atomic(pointer), unsafe { voidptr(&observed) }, desired)
}

fn unfair_owner() u32 {
	$if macos { return C.ios_native_thread_port(u64(C.pthread_self())) }
	$if linux {
		identity := C.syscall(i64(C.SYS_gettid))
		if identity <= 0 || u64(identity) > u64(0xffffffff) { panic('iOS: invalid native unfair-lock owner') }
		return u32(identity)
	}
	panic('iOS: unfair locks require a supported native thread identity')
	return 0
}

fn unfair_wait(pointer &u32, observed u32) {
	$if macos {
		if C.pthread_once(unsafe { voidptr(&unfair_macos_once) }, unsafe { voidptr(unfair_macos_initialize) }) != 0 { panic('iOS: cannot initialize address waits') }
		if unfair_macos_wait(1, pointer, u64(observed), 0) >= 0 { return }
		if unsafe { *C.ios_errno_address() } == C.EINTR { return }
		panic('iOS: native unfair-lock wait failed')
	}
	$if linux {
		// FUTEX_WAIT_PRIVATE atomically checks this exact four-byte word before
		// parking. A release between the failed CAS and this call cannot lose
		// its wake: the changed value makes the kernel return EAGAIN instead.
		if C.syscall(i64(C.SYS_futex), i64(u64(pointer)), i64(128), i64(observed), i64(0), i64(0), i64(0)) >= 0 { return }
		failure := unsafe { *C.ios_errno_address() }
		if failure == C.EAGAIN || failure == C.EINTR { return }
		panic('iOS: native unfair-lock wait failed')
	}
}

fn unfair_wake(pointer &u32) {
	$if macos {
		if C.pthread_once(unsafe { voidptr(&unfair_macos_once) }, unsafe { voidptr(unfair_macos_initialize) }) != 0 { panic('iOS: cannot initialize address waits') }
		if unfair_macos_wake(1, pointer, 0) >= 0 || unsafe { *C.ios_errno_address() } == C.ENOENT { return }
		panic('iOS: native unfair-lock wake failed')
	}
	$if linux {
		if C.syscall(i64(C.SYS_futex), i64(u64(pointer)), i64(129), i64(1), i64(0), i64(0), i64(0)) < 0 { panic('iOS: native unfair-lock wake failed') }
	}
}

fn darwin_unfair_lock(pointer &u32) {
	previous := unsafe { *C.ios_errno_address() }; defer { darwin_set_errno(previous) }
	owner := unfair_owner()
	for {
		if unfair_compare(pointer, 0, owner) { return }
		observed := unfair_load(pointer)
		if observed == owner { panic('iOS: recursive unfair-lock acquisition') }
		if observed != 0 { unfair_wait(pointer, observed) }
	}
}

fn darwin_unfair_trylock(pointer &u32) bool {
	previous := unsafe { *C.ios_errno_address() }; defer { darwin_set_errno(previous) }
	return unfair_compare(pointer, 0, unfair_owner())
}

fn darwin_unfair_unlock(pointer &u32) {
	previous := unsafe { *C.ios_errno_address() }; defer { darwin_set_errno(previous) }
	if !unfair_compare(pointer, unfair_owner(), 0) { panic('iOS: unfair-lock unlock requires its owner') }
	// Always wake one waiter after publishing zero. No waiter count, native
	// mutex, address registry or cached thread identity survives this call.
	unfair_wake(pointer)
}

fn darwin_unfair_lock_flags(pointer &u32, flags u32) {
	if flags & ~u32(0x40000) != 0 { panic('iOS: unsupported unfair-lock flags') }
	// Adaptive spinning is a scheduling hint. The blocking path supplies the
	// same exclusion and ownership semantics without promising priority boosts.
	darwin_unfair_lock(pointer)
}

fn darwin_unfair_assert_owner(pointer &u32) {
	previous := unsafe { *C.ios_errno_address() }; defer { darwin_set_errno(previous) }
	if unfair_load(pointer) != unfair_owner() { panic('iOS: unfair lock is not owned by this thread') }
}

fn darwin_unfair_assert_not_owner(pointer &u32) {
	previous := unsafe { *C.ios_errno_address() }; defer { darwin_set_errno(previous) }
	if unfair_load(pointer) == unfair_owner() { panic('iOS: unfair lock is owned by this thread') }
}

fn unfair_lock_symbol(symbol string) ?u64 {
	return match symbol {
		'_os_unfair_lock_lock' { u64(unsafe { voidptr(darwin_unfair_lock) }) }
		'_os_unfair_lock_trylock' { u64(unsafe { voidptr(darwin_unfair_trylock) }) }
		'_os_unfair_lock_unlock' { u64(unsafe { voidptr(darwin_unfair_unlock) }) }
		'_os_unfair_lock_lock_with_flags' { u64(unsafe { voidptr(darwin_unfair_lock_flags) }) }
		'_os_unfair_lock_assert_owner' { u64(unsafe { voidptr(darwin_unfair_assert_owner) }) }
		'_os_unfair_lock_assert_not_owner' { u64(unsafe { voidptr(darwin_unfair_assert_not_owner) }) }
		else { return none }
	}
}
