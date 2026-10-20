// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlclose(voidptr) int

type ImpBlockMake = fn (u64) u64
type ImpBlockGet = fn (u64) u64
type ImpBlockRemove = fn (u64) bool
type ImpBlockRelease = fn (u64)
type ImpBlockProbe = fn (&u64, u64, &u64)
type ImpBlockSimple = fn (u64, u64, u64) u64

struct ImpBlockApi {
	native bool
	stack_isa u64
	global_isa u64
	@[required]
	make_imp ImpBlockMake
	@[required]
	get_block ImpBlockGet
	@[required]
	remove_imp ImpBlockRemove
	@[required]
	copy_block ImpBlockMake
	@[required]
	release_block ImpBlockRelease
}

struct ImpBlockState {
mut:
	copies i64
	disposals i64
	reenter bool
	imp u64
	checks i64
	object u64
}

fn imp_block_reader(imp u64) {
	assert objc_imp_get_block(imp) == 0
	assert !objc_imp_remove_block(imp)
	C.ios_objc_initialize_lock()
	C.ios_objc_initialize_unlock()
}
fn imp_block_copy_helper(destination u64, source u64) {
	assert read64(destination + 32) == read64(source + 32)
	state := unsafe { &ImpBlockState(read64(destination + 40)) }
	C.ios_ref_change(unsafe { &state.copies }, 1)
	if state.object != 0 { objc_retain(state.object) }
	if state.reenter {
		worker := spawn imp_block_reader(0)
		worker.wait() // Cross-thread progress proves the registry lock is dropped.
		C.ios_ref_change(unsafe { &state.checks }, 1)
	}
}
fn imp_block_dispose_helper(block u64) {
	state := unsafe { &ImpBlockState(read64(block + 40)) }
	C.ios_ref_change(unsafe { &state.disposals }, 1)
	if state.object != 0 { objc_release(state.object) }
	if state.reenter {
		worker := spawn imp_block_reader(state.imp)
		worker.wait()
		assert ios_runtime.names['NSObject'] != 0
		C.ios_ref_change(unsafe { &state.checks }, 1)
	}
}

fn imp_block_simple(block u64, object u64, value u64) u64 {
	return read64(block + 32) + object + value
}

// Raw ARM64 caller/callee: observe integer, SIMD, indirect-result and original
// stack bits without relying on the host C compiler's aggregate conventions.
fn imp_block_code() u64 {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE,
		C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	mut caller := [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, // save 48 bytes
		0xaa0003f1, 0xaa0103f0, 0xaa0203f3, 0xd10083ff, // input/target/output, SP-32
		0xa94d2a29, 0xa9002be9, 0xa94e2a29, 0xa9012be9, // four stack words
		0xa9400620, 0xa9410e22, 0xa9421624, 0xa9431e26, 0xf9402228]
	for i in 0 .. 4 { caller << u32(0xad400000 | (u32(5 + i * 2) << 15) | (u32(i * 2 + 1) << 10) | (17 << 5) | u32(i * 2)) }
	caller << [u32(0xd63f0200), 0xa9000660, 0xa9010e62]
	for i in 0 .. 4 { caller << u32(0xad000000 | (u32(2 + i * 2) << 15) | (u32(i * 2 + 1) << 10) | (19 << 5) | u32(i * 2)) }
	caller << [u32(0x910083ff), 0xa9425bf5, 0xa94153f3, 0xa8c37bfd, 0xd65f03c0]
	for i, op in caller { write32(code + u64(i * 4), op) }
	mut callee := [u32(0xf9401011)] // ldr x17,[x0,#32] capture buffer
	for i in 0 .. 4 { callee << u32(0xa9000000 | (u32(i * 2) << 15) | (u32(i * 2 + 1) << 10) | (17 << 5) | u32(i * 2)) }
	callee << u32(0xf9002228) // str x8,[x17,#64]
	for i in 0 .. 4 { callee << u32(0xad000000 | (u32(5 + i * 2) << 15) | (u32(i * 2 + 1) << 10) | (17 << 5) | u32(i * 2)) }
	callee << [u32(0xa9402be9), 0xa90d2a29, 0xa9412be9, 0xa90e2a29, 0xaa0803e0, 0xd65f03c0]
	for i, op in callee { write32(code + 256 + u64(i * 4), op) }
	unsafe { caller.free(); callee.free() }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 384))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	return code
}

fn imp_block_arguments(api ImpBlockApi, code u64) {
	probe := unsafe { ImpBlockProbe(voidptr(code)) }
	mut descriptor := [u64(0), 48, u64(unsafe { voidptr(imp_block_copy_helper) }),
		u64(unsafe { voidptr(imp_block_dispose_helper) })]!
	mut state := ImpBlockState{}
	mut captured := [32]u64{init: 0xa5a5a5a5a5a5a5a5}
	mut literal := [api.stack_isa, u64(1) << 25, code + 256, u64(unsafe { &descriptor[0] }),
		u64(unsafe { &captured[0] }), u64(unsafe { &state })]!
	imp := api.make_imp(u64(unsafe { &literal[0] }))
	block := api.get_block(imp)
	assert block != 0 && block != u64(unsafe { &literal[0] }) && state.copies == 1
	mut input := [30]u64{}
	for i in 0 .. input.len { input[i] = 0x1234000000000000 + u64(i * 0x101 + 7) }
	input[1] = ~u64(0) // Must be discarded, never interpreted as a selector.
	mut result := [20]u64{}
	probe(unsafe { &input[0] }, imp, unsafe { &result[0] })
	assert captured[0] == block && captured[1] == input[0]
	for i in 2 .. 9 { assert captured[i] == input[i] }
	for i in 10 .. 30 { assert captured[i] == input[i] }
	assert captured[9] == 0xa5a5a5a5a5a5a5a5 && captured[30] == 0xa5a5a5a5a5a5a5a5 && captured[31] == 0xa5a5a5a5a5a5a5a5
	assert result[0] == input[8] && result[1] == input[0] && result[2] == input[2] && result[3] == input[3]
	for i in 4 .. 20 { assert result[i] == input[i + 6] }
	assert api.remove_imp(imp) && state.disposals == 1
	assert api.get_block(imp) == 0
}

fn imp_block_lifetime(api ImpBlockApi) {
	mut descriptor := [u64(0), 48, u64(unsafe { voidptr(imp_block_copy_helper) }), u64(unsafe { voidptr(imp_block_dispose_helper) })]!
	for _ in 0 .. 100 {
		mut state := ImpBlockState{}
		mut literal := [api.stack_isa, u64(1) << 25, u64(unsafe { voidptr(imp_block_simple) }),
			u64(unsafe { &descriptor[0] }), u64(11), u64(unsafe { &state })]!
		copied := api.copy_block(u64(unsafe { &literal[0] }))
		first := api.make_imp(copied); second := api.make_imp(copied)
		assert first != second && state.copies == 1 && api.get_block(first) == copied && api.get_block(second) == copied
		api.release_block(copied)
		call := unsafe { ImpBlockSimple(voidptr(first)) }
		assert call(20, ~u64(0), 30) == 61
		assert api.remove_imp(first) && state.disposals == 0
		assert api.remove_imp(second) && state.disposals == 1
	}
	mut global_descriptor := [u64(0), 40]!
	mut global := [api.global_isa, u64(1) << 28, u64(unsafe { voidptr(imp_block_simple) }),
		u64(unsafe { &global_descriptor[0] }), u64(41)]!
	imp := api.make_imp(u64(unsafe { &global[0] }))
	assert api.get_block(imp) == u64(unsafe { &global[0] })
	call := unsafe { ImpBlockSimple(voidptr(imp)) }
	assert call(1, 0, 2) == 44 && api.remove_imp(imp)
	assert api.get_block(0) == 0 && !api.remove_imp(0)
	assert api.get_block(u64(unsafe { voidptr(imp_block_simple) })) == 0
	assert !api.remove_imp(u64(unsafe { voidptr(imp_block_simple) }))
}

fn imp_block_worker(api ImpBlockApi) {
	imp_block_lifetime(api)
}

fn imp_block_runtime_api() ImpBlockApi {
	return ImpBlockApi{stack_isa: block_isa(0), global_isa: block_isa(1),
		make_imp: unsafe { ImpBlockMake(voidptr(runtime_symbol('/usr/lib/libobjc.A.dylib', '_imp_implementationWithBlock') or { panic(err) })) },
		get_block: unsafe { ImpBlockGet(voidptr(runtime_symbol('/usr/lib/libobjc.A.dylib', '_imp_getBlock') or { panic(err) })) },
		remove_imp: unsafe { ImpBlockRemove(voidptr(runtime_symbol('/usr/lib/libobjc.A.dylib', '_imp_removeBlock') or { panic(err) })) },
		copy_block: block_copy, release_block: block_release}
}

fn test_objc_block_imp() {
	code := imp_block_code()
	$if macos {
		objc := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2); system := C.dlopen(c'/usr/lib/libSystem.B.dylib', 2)
		assert objc != unsafe { nil } && system != unsafe { nil }
		api := ImpBlockApi{native: true,
			stack_isa: u64(C.dlsym(system, c'_NSConcreteStackBlock')), global_isa: u64(C.dlsym(system, c'_NSConcreteGlobalBlock')),
			make_imp: unsafe { ImpBlockMake(C.dlsym(objc, c'imp_implementationWithBlock')) },
			get_block: unsafe { ImpBlockGet(C.dlsym(objc, c'imp_getBlock')) },
			remove_imp: unsafe { ImpBlockRemove(C.dlsym(objc, c'imp_removeBlock')) },
			copy_block: unsafe { ImpBlockMake(C.dlsym(system, c'_Block_copy')) },
			release_block: unsafe { ImpBlockRelease(C.dlsym(system, c'_Block_release')) }}
		imp_block_arguments(api, code); imp_block_lifetime(api)
		assert C.dlclose(objc) == 0 && C.dlclose(system) == 0
		println('NATIVE-OBJC-BLOCK-IMP: raw ARM64 register/stack forwarding and copied/global/shared heap Block ownership matched')
	}
	for _ in 0 .. 2 {
		objc_start(); api := imp_block_runtime_api()
		imp_block_arguments(api, code); imp_block_lifetime(api)
		mut workers := []thread{}
		for _ in 0 .. 4 { workers << spawn imp_block_worker(api) }
		workers.wait(); unsafe { workers.free() }
		assert ios_runtime.block_refs.len == 0 && ios_runtime.block_imps.len == 0
		for bad in [u64(0), 1, ~u64(0), code + 4]! { assert api.get_block(bad) == 0 && !api.remove_imp(bad) }
		for symbol in ['imp_implementationWithBlock', '_imp_implementationWithBlockExtra', '_imp_getBlockExtra', '_imp_removeBlockExtra']! { if _ := objc_runtime_symbol(symbol) { assert false } }
		for library in ['/usr/lib/libSystem.B.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation']! {
			for symbol in ['_imp_implementationWithBlock', '_imp_getBlock', '_imp_removeBlock']! { if _ := runtime_symbol(library, symbol) { assert false } }
		}
		mut descriptor := [u64(0), 48, u64(unsafe { voidptr(imp_block_copy_helper) }), u64(unsafe { voidptr(imp_block_dispose_helper) })]!
		captured_object := objc_new(ios_runtime.names['NSObject'])
		mut weak := u64(0)
		objc_store_weak(unsafe { &weak }, captured_object)
		mut state := ImpBlockState{reenter: true, object: captured_object}
		mut literal := [api.stack_isa, u64(1) << 25, u64(unsafe { voidptr(imp_block_simple) }), u64(unsafe { &descriptor[0] }), u64(10), u64(unsafe { &state })]!
		first := api.make_imp(u64(unsafe { &literal[0] })); state.imp = first
		cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixBlockImpMethod', 0)
		selector := objc_selector(c'calculate:')
		assert objc_add_method(cls, selector, first, c'Q24@0:8Q16'); objc_register_class(cls)
		object := objc_allocate(cls); send := unsafe { ImpBlockSimple(voidptr(C.ios_objc_msgsend)) }
		assert send(object, selector, 7) == object + 17
		second := api.make_imp(u64(unsafe { &literal[0] }))
		objc_release(captured_object)
		assert objc_method_set_imp(objc_instance_method(cls, selector), second) == first
		assert api.remove_imp(first) && state.disposals == 1 && state.checks == 3
		assert weak == captured_object && obj_header(captured_object).refs == 1
		assert send(object, selector, 9) == object + 19
		objc_release(object)
		state.imp = second
		objc_stop() // The remaining IMP owns its copy until quiescent teardown.
		assert state.disposals == 2 && state.copies == 2 && state.checks == 4
		assert weak == 0
		objc_destroy_weak(unsafe { &weak })
		assert ios_runtime.weak.len == 0
		assert ios_runtime.block_imps_retired && ios_runtime.block_refs.len == 0 && ios_runtime.live == 0
		assert api.get_block(second) == 0 && !api.remove_imp(second)
	}
	assert C.munmap(voidptr(code), usize(C.getpagesize())) == 0
	println('IOS-OBJC-BLOCK-IMP: native-matched x0-x8/q0-q7/four stack words and result bits, selector omission, copied/global/shared heap ownership, four concurrent creators, real method install/replacement, cross-thread copy/dispose reentry outside locks, invalid identities and two quiescent runtime drains')
}
