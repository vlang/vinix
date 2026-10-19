// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <signal.h>

fn C.sigprocmask(i32, voidptr, voidptr) i32
fn C.__atomic_compare_exchange_n(&u64, &u64, u64, bool, i32, i32) bool
fn C.__atomic_always_lock_free(usize, voidptr) bool

type DarwinSignalHandler = fn (i32)
type NativeSignalAction = fn (i32, voidptr, voidptr) i32

fn signal_native_action(number i32, action voidptr, output voidptr) i32 {
	// V's os declaration narrows oldact to i32. Call the installed native
	// function through its actual pointer ABI, without changing the compiler.
	function := unsafe { NativeSignalAction(voidptr(C.sigaction)) }
	return function(number, action, output)
}

struct DarwinSignalAction {
mut:
	handler u64
	mask    u32
	flags   i32
}

struct DarwinSignalSlot {
mut:
	gate     u64
	handler  u64
	saved    bool
	original [24]u64
}

// The low word counts running callbacks; the high word permits new entries.
const signal_open = u64(1) << 32

// Native delivery can arrive after disposition replacement. Keep the bridge's
// slots for the process, close entry gates, and drain pins before image unmap.
__global signal_slots = [32]DarwinSignalSlot{}
__global signal_registry_active = false
__global signal_registry_closing = false

fn signal_callback_pin(slot &DarwinSignalSlot) bool {
	mut expected := C.ios_load_pointer(unsafe { &slot.gate })
	for expected >= signal_open {
		if expected & 0xffffffff == 0xffffffff { return false }
		if C.__atomic_compare_exchange_n(unsafe { &slot.gate }, unsafe { &expected }, expected + 1,
			false, 4, 2) {
			return true
		}
	}
	return false
}

fn signal_callback_unpin(slot &DarwinSignalSlot) {
	mut expected := C.ios_load_pointer(unsafe { &slot.gate })
	for expected & 0xffffffff != 0 {
		if C.__atomic_compare_exchange_n(unsafe { &slot.gate }, unsafe { &expected }, expected - 1,
			false, 4, 2) {
			return
		}
	}
}

// No allocation, mutex, runtime registry lookup or non-signal-safe syscall.
fn signal_callback(native i32) {
	if native <= 0 || native > 31 { return }
	number := wait_signal_darwin(native)
	slot := unsafe { &signal_slots[number] }
	if !signal_callback_pin(slot) { return }
	handler := C.ios_load_pointer(unsafe { &slot.handler })
	if handler > 1 {
		callback := unsafe { DarwinSignalHandler(voidptr(handler)) }
		callback(number)
	}
	signal_callback_unpin(slot)
}

fn signal_native_mask(mask u32) ?u64 {
	mut native := u64(0)
	for number in 1 .. 33 {
		if mask & (u32(1) << u32(number - 1)) == 0 { continue }
		if number == 32 { return none }
		mapped := darwin_native_signal(i32(number))
		if mapped < 0 { return none }
		native |= u64(1) << u32(mapped - 1)
	}
	return native
}

fn signal_darwin_mask(native u64) ?u32 {
	mut result := u32(0)
	mut represented := u64(0)
	for number in 1 .. 32 {
		mapped := darwin_native_signal(i32(number))
		if mapped < 0 { continue }
		bit := u64(1) << u32(mapped - 1)
		represented |= bit
		if native & bit != 0 { result |= u32(1) << u32(number - 1) }
	}
	if native & ~represented != 0 { return none }
	return result
}

fn signal_decode(number i32, native &C.sigaction) ?DarwinSignalAction {
	mut handler := u64(0)
	// Both native layouts begin with the handler union. V treats &fn_field
	// as the function value, so copy the pointer bytes from the record itself.
	C.memcpy(unsafe { &handler }, native, 8)
	if handler == u64(unsafe { voidptr(signal_callback) }) {
		handler = C.ios_load_pointer(unsafe { &signal_slots[number].handler })
	}
	mut bits := u64(0)
	$if macos {
		C.memcpy(unsafe { &bits }, unsafe { &native.sa_mask }, 4)
		return DarwinSignalAction{ handler: handler, mask: u32(bits), flags: i32(native.sa_flags) }
	} $else {
		C.memcpy(unsafe { &bits }, unsafe { &native.sa_mask }, 8)
		mask := signal_darwin_mask(bits) or { return none }
		mut flags := i32(0)
		for entry in [[u32(C.SA_ONSTACK), u32(1)]!, [u32(C.SA_RESTART), u32(2)]!,
			[u32(C.SA_RESETHAND), u32(4)]!, [u32(C.SA_NOCLDSTOP), u32(8)]!,
			[u32(C.SA_NODEFER), u32(16)]!, [u32(C.SA_NOCLDWAIT), u32(32)]!,
			[u32(C.SA_SIGINFO), u32(64)]!]! {
			if u32(native.sa_flags) & entry[0] != 0 { flags |= i32(entry[1]) }
		}
		return DarwinSignalAction{ handler: handler, mask: mask, flags: flags }
	}
}

fn darwin_sigaction(number i32, action &DarwinSignalAction, output &DarwinSignalAction) i32 {
	if number <= 0 || number > 31 || number in [i32(9), 17] {
		darwin_set_errno(22)
		return -1
	}
	mapped := darwin_native_signal(number)
	if mapped < 0 {
		darwin_set_errno(45)
		return -1
	}
	// Registry operations from a callback are outside this subset. Reject
	// before any mutex, including when delivery interrupted its owner.
	for signal in 1 .. 32 {
		if C.ios_load_pointer(unsafe { &signal_slots[signal].gate }) & 0xffffffff != 0 {
			darwin_set_errno(11)
			return -1
		}
	}
	previous := unsafe { *C.ios_errno_address() }
	// Read before writing: act and oldact may name the same 16-byte record.
	mut incoming := DarwinSignalAction{}
	mut mask := u64(0)
	if action != unsafe { nil } {
		incoming = unsafe { *action }
		// One-argument handlers, alternate stacks, restart and nodefer are verified.
		// Never give an app Linux's siginfo/ucontext bytes as Darwin objects.
		if incoming.flags & ~i32(0x13) != 0 {
			darwin_set_errno(45)
			return -1
		}
		$if macos {
			mask = u64(incoming.mask)
		} $else {
			mask = signal_native_mask(incoming.mask) or {
				darwin_set_errno(45)
				return -1
			}
		}
	}
	C.ios_mach_threads_lock()
	defer { C.ios_mach_threads_unlock() }
	if !signal_registry_active {
		darwin_set_errno(22)
		return -1
	}
	mut slot := unsafe { &signal_slots[number] }
	old := unsafe { &C.sigaction(C.__builtin_alloca(sizeof(C.sigaction))) }
	C.memset(old, 0, sizeof(C.sigaction))
	if signal_native_action(mapped, unsafe { nil }, old) != 0 {
		return darwin_process_result(-1, previous)
	}
	decoded := signal_decode(number, old) or {
		darwin_set_errno(45)
		return -1
	}
	if action != unsafe { nil } {
		mut native := unsafe { &C.sigaction(C.__builtin_alloca(sizeof(C.sigaction))) }
		C.memset(native, 0, sizeof(C.sigaction))
		pointer := if incoming.handler > 1 {
			u64(unsafe { voidptr(signal_callback) })
		} else {
			incoming.handler
		}
		C.memcpy(native, unsafe { &pointer }, 8)
		$if macos {
			C.memcpy(unsafe { &native.sa_mask }, unsafe { &mask }, 4)
			native.sa_flags = int(incoming.flags)
		} $else {
			C.memcpy(unsafe { &native.sa_mask }, unsafe { &mask }, 8)
			native.sa_flags = 0
			if incoming.flags & 1 != 0 { native.sa_flags |= int(C.SA_ONSTACK) }
			if incoming.flags & 2 != 0 { native.sa_flags |= int(C.SA_RESTART) }
			if incoming.flags & 16 != 0 { native.sa_flags |= int(C.SA_NODEFER) }
		}
		old_handler := C.ios_load_pointer(unsafe { &slot.handler })
		C.ios_store_pointer(unsafe { &slot.handler }, incoming.handler)
		if signal_native_action(mapped, native, unsafe { nil }) != 0 {
			C.ios_store_pointer(unsafe { &slot.handler }, old_handler)
			return darwin_process_result(-1, previous)
		}
		if !slot.saved {
			C.memcpy(unsafe { &slot.original[0] }, old, sizeof(C.sigaction))
			slot.saved = true
		}
	}
	if output != unsafe { nil } { unsafe { *output = decoded } }
	darwin_set_errno(previous)
	return 0
}

fn darwin_signal(number i32, handler voidptr) voidptr {
	mut action := DarwinSignalAction{ handler: u64(handler), flags: 2 }
	mut previous := DarwinSignalAction{}
	if darwin_sigaction(number, unsafe { &action }, unsafe { &previous }) != 0 {
		return unsafe { voidptr(-1) }
	}
	return unsafe { voidptr(previous.handler) }
}

fn signals_start() ! {
	if !C.__atomic_always_lock_free(8, unsafe { nil }) || sizeof(C.sigaction) > 192 {
		return error('iOS: native signal bridge requires lock-free 64-bit atomics and bounded actions')
	}
	C.ios_mach_threads_lock()
	defer { C.ios_mach_threads_unlock() }
	if signal_registry_active || signal_registry_closing {
		return error('iOS: signal registry already active or draining')
	}
	sigaltstack_start()!
	for number in 1 .. 32 {
		C.ios_store_pointer(unsafe { &signal_slots[number].gate }, signal_open)
		C.ios_store_pointer(unsafe { &signal_slots[number].handler }, 0)
		signal_slots[number].saved = false
	}
	signal_registry_active = true
}

fn signals_stop() {
	for {
		C.ios_mach_threads_lock()
		if signal_registry_closing {
			C.ios_mach_threads_unlock()
			C.sched_yield()
			continue
		}
		if !signal_registry_active {
			C.ios_mach_threads_unlock()
			return
		}
		break
	}
	signal_registry_active = false
	signal_registry_closing = true
	for number in 1 .. 32 {
		mut slot := unsafe { &signal_slots[number] }
		mut expected := C.ios_load_pointer(unsafe { &slot.gate })
		for expected >= signal_open {
			if C.__atomic_compare_exchange_n(unsafe { &slot.gate }, unsafe { &expected },
				expected - signal_open, false, 4, 2) {
				break
			}
		}
		if slot.saved {
			mapped := darwin_native_signal(i32(number))
			if signal_native_action(mapped, unsafe { &slot.original[0] }, unsafe { nil }) != 0 {
				panic('iOS: cannot restore native signal action')
			}
			slot.saved = false
		}
	}
	// A callback may itself query/change dispositions. Release the namespace
	// before draining; new registrations now fail instead of reopening gates.
	C.ios_mach_threads_unlock()
	for number in 1 .. 32 {
		for C.ios_load_pointer(unsafe { &signal_slots[number].gate }) != 0 { C.sched_yield() }
		C.ios_store_pointer(unsafe { &signal_slots[number].handler }, 0)
	}
	C.ios_mach_threads_lock()
	signal_registry_closing = false
	C.ios_mach_threads_unlock()
}

// Called with the namespace pinned by atfork. Only the calling thread survives.
// Fork from within a signal callback is outside the verified subset.
fn signals_fork_child() {
	sigaltstack_fork_child()
	signal_registry_closing = false
	for number in 1 .. 32 {
		C.ios_store_pointer(unsafe { &signal_slots[number].gate },
			if signal_registry_active { signal_open } else { u64(0) })
	}
}

fn signals_symbol(symbol string) ?u64 {
	return match symbol {
		'_sigaltstack' { u64(unsafe { voidptr(darwin_sigaltstack) }) }
		'_raise' { u64(unsafe { voidptr(darwin_raise) }) }
		'_pause' { u64(unsafe { voidptr(darwin_pause) }) }
		'_sigaction' { u64(unsafe { voidptr(darwin_sigaction) }) }
		else { return none }
	}
}
