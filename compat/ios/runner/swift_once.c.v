// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Darwin-compiled Swift callers use a barrier-free load to skip this entry
// only for -1. Keep a different opaque completed word so every caller acquires
// our release before reading initialized data. Darwin's global quiescence
// protocol permits its eventual -1 publication; Vinix does not implement it.
const swift_once_done = u64(2)

// Swift's C entry orders the callback before its borrowed context. The token
// must be an aligned, initially zero word with static extent. Reuse dispatch's
// per-token mutexes and acquire/release publication, including their teardown.
fn swift_once_checked(predicate u64, function u64, context u64) ! {
	if predicate == 0 || predicate & 7 != 0 || predicate > ~u64(0) - 7 {
		return error('iOS: invalid Swift once token')
	}
	token := unsafe { &u64(predicate) }
	// Like the native entry, a completed token never inspects the callback or
	// context. This path needs neither a running runtime nor a writable token.
	completed := C.ios_load_pointer(token)
	if completed == swift_once_done || completed == ~u64(0) { return }
	if function == 0 { return error('iOS: missing Swift once callback') }
	if system_data == unsafe { nil } { return error('iOS: Swift once outside runtime lifetime') }
	dispatch_once_run(token, unsafe { voidptr(context) }, unsafe { DispatchFunction(voidptr(function)) }, swift_once_done)
}

fn swift_once(predicate u64, function u64, context u64) {
	swift_once_checked(predicate, function, context) or { panic(err) }
}

fn swift_once_symbol(symbol string) ?u64 {
	if symbol == '_swift_once' { return u64(unsafe { voidptr(swift_once) }) }
	return none
}
