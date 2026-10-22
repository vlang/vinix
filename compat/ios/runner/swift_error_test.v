// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFError.h>
	#include <CoreFoundation/CFString.h>
}
#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateMutable(voidptr, i64) voidptr
fn C.CFStringAppendCString(voidptr, &char, u32)
fn C.CFErrorCreate(voidptr, voidptr, i64, voidptr) voidptr
fn C.CFErrorGetCode(voidptr) i64
fn C.CFErrorGetDomain(voidptr) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRetain(voidptr) voidptr
fn C.CFRelease(voidptr)

type ErrorRetain = fn (u64) u64
type ErrorRelease = fn (u64)
type ErrorProbe = fn (u64, u64, &u64)
type ErrorThrowProbe = fn (u64, u64, u64, &u64)

struct ErrorApi {
	native bool
	@[required]
	retain ErrorRetain
	@[required]
	release ErrorRelease
	will_throw u64
}

fn error_api(native bool) ErrorApi {
	mut entries := [3]u64{}
	for i, name in ['_swift_errorRetain', '_swift_errorRelease', '_swift_willThrow']! {
		if native {
			library := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', C.RTLD_NOW)
			assert library != unsafe { nil }
			entries[i] = u64(C.dlsym(library, name[1..].str))
		} else { entries[i] = runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) or { panic(err) } }
		assert entries[i] != 0
	}
	return ErrorApi{ native: native, retain: unsafe { ErrorRetain(voidptr(entries[0])) },
		release: unsafe { ErrorRelease(voidptr(entries[1])) }, will_throw: entries[2] }
}

fn error_throw_call(api ErrorApi, probe ErrorThrowProbe, object u64, guard u64) {
	mut registers := [3]u64{}
	probe(object, api.will_throw, guard, unsafe { &registers[0] })
	assert registers[0] == 0x5020 && registers[1] == object
	assert registers[2] & 15 == 0
}

fn error_throw_worker(api ErrorApi, probe ErrorThrowProbe, object u64, guard u64) {
	for _ in 0 .. 1000 { error_throw_call(api, probe, object, guard) }
}

fn error_throw_suite(api ErrorApi, probe ErrorThrowProbe, guard u64) {
	// A missing debugger handler must not inspect an error or an ordinary x0
	// argument. Neither guard address is readable, even for one byte.
	for object in [u64(0), guard, guard + 1]! { error_throw_call(api, probe, object, guard) }
	object := api.make(42)
	before := api.refs(object)
	domain := api.domain(object)
	domain_refs := api.refs(domain)
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn error_throw_worker(api, probe, object, guard) }
	workers.wait()
	assert api.refs(object) == before && api.refs(domain) == domain_refs
	assert api.code(object) == 42 && api.domain(object) == domain
	api.release(object)
}

fn (api ErrorApi) make(code i64) u64 {
	$if macos {
		if api.native {
			domain := C.CFStringCreateMutable(unsafe { nil }, 0)
			assert domain != unsafe { nil }
			C.CFStringAppendCString(domain, c'Vinix Swift error ownership domain é 🎮', 0x08000100)
			object := C.CFErrorCreate(unsafe { nil }, domain, code, unsafe { nil })
			C.CFRelease(domain)
			assert object != unsafe { nil }
			return u64(object)
		}
	}
	mut object := u64(0)
	security_error(unsafe { &object }, int(code))
	return object
}

fn (api ErrorApi) code(object u64) i64 {
	$if macos { if api.native { return C.CFErrorGetCode(unsafe { voidptr(object) }) } }
	return cf_error_code(object)
}
fn (api ErrorApi) domain(object u64) u64 {
	$if macos { if api.native { return u64(C.CFErrorGetDomain(unsafe { voidptr(object) })) } }
	return cf_error_domain(object)
}
fn (api ErrorApi) refs(object u64) i64 {
	$if macos { if api.native { return C.CFGetRetainCount(unsafe { voidptr(object) }) } }
	return obj_header(object).refs
}
fn (api ErrorApi) hold_domain(domain u64) {
	$if macos { if api.native { assert u64(C.CFRetain(unsafe { voidptr(domain) })) == domain; return } }
	assert objc_retain(domain) == domain
}
fn (api ErrorApi) drop_domain(domain u64) {
	$if macos { if api.native { C.CFRelease(unsafe { voidptr(domain) }); return } }
	objc_release(domain)
}

fn error_case(api ErrorApi, code i64, probe ErrorProbe) {
	object := api.make(code)
	assert api.code(object) == code
	before := api.refs(object)
	assert api.retain(object) == object && api.refs(object) == before + 1
	api.release(object)
	assert api.refs(object) == before && api.code(object) == code
	mut registers := [3]u64{}
	probe(object, u64(unsafe { voidptr(api.retain) }), unsafe { &registers[0] })
	assert registers[0] == object && registers[1] == 0x5020 && registers[2] == 0x5021
	assert api.refs(object) == before + 1
	probe(object, u64(unsafe { voidptr(api.release) }), unsafe { &registers[0] })
	assert registers[1] == 0x5020 && registers[2] == 0x5021 && api.refs(object) == before
	domain := api.domain(object)
	api.hold_domain(domain)
	domain_refs := api.refs(domain)
	// Final release must dispose the error's owned domain. Only the separately
	// retained domain is accessed after destruction, never the freed error.
	probe(object, u64(unsafe { voidptr(api.release) }), unsafe { &registers[0] })
	assert registers[1] == 0x5020 && registers[2] == 0x5021
	assert api.refs(domain) == domain_refs - 1
	api.drop_domain(domain)
}

fn error_alias_worker(api ErrorApi, object u64) {
	for _ in 0 .. 1000 { assert api.retain(object) == object; api.release(object) }
}
fn error_creation_worker(api ErrorApi, probe ErrorProbe) {
	for code in 0 .. 100 { error_case(api, i64(code), probe) }
}
fn error_resolve_worker(object u64) {
	api := error_api(false)
	// Retaining a live child takes the ownership registry lock. Resolving the
	// error aliases alone, or applying them to nil, would not exercise it.
	assert api.retain(object) == object
	api.release(object)
}

struct ErrorDeinit {
	weak &u64
mut:
	calls int
}
fn error_dealloc(object u64, selector &char) {
	_ = selector
	header := obj_header(object)
	mut state := unsafe { &ErrorDeinit(header.tag) }
	assert state.calls == 0 && unsafe { *state.weak } == 0
	state.calls++
	assert cf_error_code(header.fields[0]) == -26275
	// Waiting for a second resolver proves dealloc runs outside the registry
	// lock. Reentrant error creation and destruction use the same exports.
	worker := spawn error_resolve_worker(header.fields[0])
	worker.wait()
	api := error_api(false)
	child := api.make(42)
	api.release(child)
}

fn error_reentrant(api ErrorApi, probe ErrorProbe) {
	cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixSwiftErrorOwnerTest', 0)
	assert cls != 0
	objc_register_class(cls)
	objc_replace_method(cls, objc_selector(c'dealloc'), u64(unsafe { voidptr(error_dealloc) }), c'v16@0:8')
	mut weak := u64(0)
	mut state := unsafe { &ErrorDeinit(C.__builtin_alloca(sizeof(ErrorDeinit))) }
	unsafe { *state = ErrorDeinit{ weak: &weak } }
	object := objc_allocate(cls)
	mut header := obj_header(object)
	header.tag = i64(state)
	child := api.make(-26275)
	header.fields[0] = child
	domain := api.domain(child)
	api.hold_domain(domain)
	refs := api.refs(domain)
	objc_store_weak(unsafe { &weak }, object)
	assert weak == object && api.retain(object) == object
	api.release(object)
	assert state.calls == 0 && weak == object
	mut registers := [3]u64{}
	probe(object, u64(unsafe { voidptr(api.release) }), unsafe { &registers[0] })
	assert registers[1] == 0x5020 && registers[2] == 0x5021
	assert state.calls == 1 && weak == 0 && api.refs(domain) == refs - 1
	objc_destroy_weak(unsafe { &weak })
	api.drop_domain(domain)
}

fn error_suite(api ErrorApi, probe ErrorProbe) {
	assert api.retain(0) == 0
	api.release(0)
	for code in [i64(-26275), 0, 1, 0x7fffffff]! { error_case(api, code, probe) }
	mut creations := []thread{}
	for _ in 0 .. 8 { creations << spawn error_creation_worker(api, probe) }
	creations.wait()
	owner := api.make(-1)
	before := api.refs(owner)
	mut aliases := []thread{}
	for _ in 0 .. 8 { aliases << spawn error_alias_worker(api, owner) }
	aliases.wait()
	assert api.refs(owner) == before && api.code(owner) == -1
	api.release(owner)
	if !api.native { error_reentrant(api, probe) }
}

fn test_swift_error() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	// Ordinary C call: x0 is the owner; x20/x21 are callee-saved Swift context.
	for i, word in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0203f3, 0xaa0103f0,
		0xd28a0414, 0xd28a0435, 0xd63f0200, 0xa9005260, 0xf9000a75,
		0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i) * 4, word) }
	// Swift call: x21 is the error, x20 is context, x0 is deliberately unrelated.
	// Save the enclosing C caller's registers and keep a 16-byte-aligned stack.
	for i, word in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5,
		0xaa0303f3, 0xaa0003f5, 0xaa0103f0, 0xaa0203e0, 0xd28a0414,
		0xd63f0200, 0xa9005674, 0x910003e0, 0xf9000a60,
		0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + 64 + u64(i) * 4, word)
	}
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 128) })
	assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { ErrorProbe(voidptr(code)) }
	throw_probe := unsafe { ErrorThrowProbe(voidptr(code + 64)) }
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert guard != u64(-1)
	$if macos {
		error_suite(error_api(true), probe)
		error_throw_suite(error_api(true), throw_probe, guard)
		println('IOS-SWIFT-WILL-THROW-NATIVE: returning debugger notification, borrowed errors, guarded pointers, preserved x20/x21 and eight concurrent workers')
		println('IOS-SWIFT-ERROR-NATIVE: ordinary C error ARC, genuine CFError owners, exact ObjC reference counts, final domain disposal, preserved x20/x21 and eight creation/shared-owner workers')
	}
	for _ in 0 .. 2 {
		api := error_api(false)
		assert api.retain(0) == 0
		api.release(0)
		error_throw_call(api, throw_probe, guard, guard)
		objc_start()
		live := ios_runtime.live
		error_suite(api, probe)
		error_throw_suite(api, throw_probe, guard)
		assert ios_runtime.live == live && ios_runtime.swift_arc_code == 0 && ios_runtime.swift_heap.len == 0
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		assert api.retain(0) == 0
		api.release(0)
		error_throw_call(api, throw_probe, guard, guard)
	}
	// Do not advertise handler installation, a handler data slot or typed throws.
	for symbol in ['__swift_willThrow', '__swift_setWillThrowHandler', '_swift_willThrowTypedImpl']! {
		if _ := swift_core_symbol(symbol) { panic('unsupported throw hook resolved: ' + symbol) }
	}
	assert C.munmap(unsafe { voidptr(guard) }, page) == 0
	assert C.munmap(unsafe { voidptr(code) }, page) == 0
	println('IOS-SWIFT-WILL-THROW: native default-hook differential, borrowed ownership, inaccessible errors/x0, preserved Swift context/error, concurrency and calls before/after two drained runtime lifetimes')
	println('IOS-SWIFT-ERROR: native error ARC differential, final owned-field cleanup, nil before/after runtime, preserved Swift context through dealloc, weak zeroing, unlocked reentrant destruction, eight creation/shared-owner workers and two drained cycles without Swift allocations or thunks')
}
