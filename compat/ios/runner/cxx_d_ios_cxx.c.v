// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include "@VMODROOT/abi/cxx-symbols.h"

fn C.ios_cxx_symbol(&char) usize

fn cxx_symbol(symbol string) !u64 {
	if address := cxx_pthread_symbol(symbol) { return address }
	if address := cxx_platform_symbol(symbol) { return address }
	if symbol in ['___cxa_throw', '___cxa_rethrow'] {
		return u64(unsafe { voidptr(cxx_unwind_unsupported) })
	}
	address := C.ios_cxx_symbol(unsafe { &char(symbol.str) })
	if address == 0 { return error('iOS: C++ symbol is not implemented: ${symbol}') }
	return u64(address)
}

fn cxx_platform_symbol(symbol string) ?u64 {
	return match symbol {
		'__ZNSt3__113random_deviceC1ERKNS_12basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEE',
		'__ZNSt3__113random_deviceC2ERKNS_12basic_stringIcNS_11char_traitsIcEENS_9allocatorIcEEEE' { u64(unsafe { voidptr(cxx_random_init) }) }
		'__ZNSt3__113random_deviceD1Ev', '__ZNSt3__113random_deviceD2Ev' { u64(unsafe { voidptr(cxx_random_destroy) }) }
		'__ZNSt3__113random_deviceclEv' { u64(unsafe { voidptr(cxx_random_value) }) }
		'__ZNKSt3__113random_device7entropyEv' { u64(unsafe { voidptr(cxx_random_entropy) }) }
		'__ZNSt3__122__libcpp_verbose_abortEPKcz' { u64(unsafe { voidptr(C.ios_cxx_verbose_abort) }) }
		else { return none }
	}
}

fn cxx_pthread_symbol(symbol string) ?u64 {
	return match symbol {
		'__ZNSt3__15mutex4lockEv', '__ZNSt3__115recursive_mutex4lockEv' { u64(unsafe { voidptr(cxx_mutex_lock) }) }
		'__ZNSt3__15mutex6unlockEv', '__ZNSt3__115recursive_mutex6unlockEv' { u64(unsafe { voidptr(cxx_mutex_unlock) }) }
		'__ZNSt3__15mutex8try_lockEv' { u64(unsafe { voidptr(cxx_mutex_trylock) }) }
		'__ZNSt3__15mutexD1Ev', '__ZNSt3__115recursive_mutexD1Ev' { u64(unsafe { voidptr(cxx_mutex_destroy) }) }
		'__ZNSt3__115recursive_mutexC1Ev' { u64(unsafe { voidptr(cxx_recursive_mutex_init) }) }
		'__ZNSt3__118condition_variable4waitERNS_11unique_lockINS_5mutexEEE' { u64(unsafe { voidptr(cxx_cond_wait) }) }
		'__ZNSt3__118condition_variable10notify_oneEv' { u64(unsafe { voidptr(cxx_cond_signal) }) }
		'__ZNSt3__118condition_variable10notify_allEv' { u64(unsafe { voidptr(cxx_cond_broadcast) }) }
		'__ZNSt3__118condition_variableD1Ev' { u64(unsafe { voidptr(cxx_cond_destroy) }) }
		'__ZNSt3__118condition_variable15__do_timed_waitERNS_11unique_lockINS_5mutexEEENS_6chrono10time_pointINS5_12system_clockENS5_8durationIxNS_5ratioILl1ELl1000000000EEEEEEE' { u64(unsafe { voidptr(cxx_cond_timedwait) }) }
		else { return none }
	}
}

fn cxx_mutex_lock(object u64) { if darwin_mutex_lock(object) != 0 { panic('iOS: C++ mutex unique_lock failed') } }
fn cxx_mutex_unlock(object u64) { if darwin_mutex_unlock(object) != 0 { panic('iOS: C++ mutex unlock failed') } }
fn cxx_mutex_destroy(object u64) { if darwin_mutex_destroy(object) != 0 { panic('iOS: C++ mutex destruction failed') } }
fn cxx_mutex_trylock(object u64) bool {
	result := darwin_mutex_trylock(object)
	if result != 0 && result != 16 { panic('iOS: C++ mutex try_lock failed') }
	return result == 0
}
fn cxx_recursive_mutex_init(object u64) {
	mut attributes := [u64(0x4d545841), 2]!
	if darwin_mutex_init(object, u64(unsafe { &attributes[0] })) != 0 { panic('iOS: C++ recursive mutex initialization failed') }
}
fn cxx_unique_mutex(unique_lock u64) u64 {
	if unique_lock == 0 || unsafe { *(&u8(unique_lock + 8)) } == 0 { panic('iOS: C++ condition wait requires an owned unique_lock') }
	return read64(unique_lock)
}
fn cxx_cond_wait(object u64, unique_lock u64) {
	if darwin_cond_wait(object, cxx_unique_mutex(unique_lock)) != 0 { panic('iOS: C++ condition wait failed') }
}
fn cxx_cond_signal(object u64) { if darwin_cond_signal(object) != 0 { panic('iOS: C++ condition signal failed') } }
fn cxx_cond_broadcast(object u64) { if darwin_cond_broadcast(object) != 0 { panic('iOS: C++ condition broadcast failed') } }
fn cxx_cond_destroy(object u64) { if darwin_cond_destroy(object) != 0 { panic('iOS: C++ condition destruction failed') } }
fn cxx_cond_timedwait(object u64, unique_lock u64, nanoseconds i64) {
	ns := if nanoseconds < 0 { i64(0) } else { nanoseconds }
	mut deadline := [ns / 1000000000, ns % 1000000000]!
	result := darwin_cond_timedwait(object, cxx_unique_mutex(unique_lock), unsafe { &deadline[0] })
	if result != 0 && result != 60 { panic('iOS: C++ timed condition wait failed') }
}

fn cxx_unwind_unsupported() {
	panic('iOS: C++ exception unwinding through Mach-O frames is not implemented')
}
