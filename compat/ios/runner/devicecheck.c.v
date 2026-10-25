// SPDX-License-Identifier: GPL-2.0-or-later
module main

// The export is an NSString pointer cell, not the string object itself.
fn devicecheck_symbol(symbol string) ?u64 {
	if ios_runtime != unsafe { nil } {
		if value := app_attest_symbol(symbol) { return value }
	}
	if symbol!='_DCErrorDomain' || ios_runtime==unsafe{nil} { return none }
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.devicecheck_arena==0 {
		if ios_runtime.swift_concurrency_retired { return none }
		page:=usize(C.getpagesize())
		arena:=C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0)
		if arena==voidptr(-1) { panic('iOS: cannot allocate DeviceCheck error domain') }
		base:=u64(arena);object:=base+32;text:='com.apple.devicecheck.error'
		unsafe {
			*(&u64(base))=object
			*(&u64(object))=ios_runtime.names['NSString']
			*(&u64(object+8))=0x7c8
			*(&u64(object+16))=base+64
			*(&u64(object+24))=u64(text.len)
			C.memcpy(voidptr(base+64),text.str,usize(text.len))
		}
		ios_runtime.constants[object]=true
		if C.mprotect(arena,page,C.PROT_READ)!=0 { panic('iOS: cannot seal DeviceCheck error domain') }
		ios_runtime.devicecheck_arena=base
	}
	return ios_runtime.devicecheck_arena
}

// NSError, pool callbacks and Swift contexts can still borrow the domain.
// Its page retires only after those owners have drained at image shutdown.
fn devicecheck_stop() {
	arena:=ios_runtime.devicecheck_arena
	if arena==0 { return }
	ios_runtime.constants.delete(read64(arena))
	if C.munmap(unsafe{voidptr(arena)},usize(C.getpagesize()))!=0 { panic('iOS: cannot retire DeviceCheck error domain') }
	ios_runtime.devicecheck_arena=0
}
