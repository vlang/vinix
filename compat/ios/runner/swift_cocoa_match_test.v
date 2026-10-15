// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFError.h>
	#include <CoreFoundation/CFString.h>
	#include <objc/runtime.h>
}

#include <dlfcn.h>

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.CFStringCreateWithBytes(voidptr, &u8, i64, u32, bool) voidptr
fn C.CFErrorCreate(voidptr, voidptr, i64, voidptr) voidptr
fn C.CFGetRetainCount(voidptr) i64
fn C.CFRelease(voidptr)
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr

type MatchMetadata = fn (u64) SwiftAssociatedMetadata
type MatchWitness = fn (u64, u64, u64) u64
type MatchCall = fn (u64, u64, u64, u64) bool
type MatchProbe = fn (u64, u64, u64, u64, u64, &u64)
type MatchSend = fn (u64, u64) u64
type MatchInit = fn (u64, u64, u64, i64, u64) u64
type MatchPoolPush = fn () u64
type MatchPoolPop = fn (u64)

struct MatchApi {
	native    bool
	entry     u64
	metadata  u64
	table     u64
	probe     MatchProbe
	send      u64
	pool_push u64
	pool_pop  u64
}

fn (api MatchApi) text(text string) u64 {
	$if macos {
		if api.native {
			return u64(C.CFStringCreateWithBytes(unsafe { nil }, text.str, i64(text.len), 0x08000100, false))
		}
	}
	return owned_string(text)
}

fn (api MatchApi) drop(owner u64) {
	$if macos {
		if api.native {
			C.CFRelease(unsafe { voidptr(owner) })
			return
		}
	}
	objc_release(owner)
}

fn (api MatchApi) refs(owner u64) i64 {
	$if macos {
		if api.native { return C.CFGetRetainCount(unsafe { voidptr(owner) }) }
	}
	return obj_header(owner).refs
}

fn (api MatchApi) make(kind int, domain u64, code i64) u64 {
	$if macos {
		if api.native {
			if kind == 0 {
				return u64(C.CFErrorCreate(unsafe { nil }, unsafe { voidptr(domain) }, code, unsafe { nil }))
			}
			send := unsafe { MatchSend(voidptr(api.send)) }
			initialize := unsafe { MatchInit(voidptr(api.send)) }
			return initialize(send(u64(C.objc_getClass(c'NSError')), u64(C.sel_registerName(c'alloc'))), u64(C.sel_registerName(c'initWithDomain:code:userInfo:')), domain, code, 0)
		}
	}
	if kind == 0 {
		owner := objc_allocate(cf_error_type_id())
		mut header := obj_header(owner)
		header.fields[0] = objc_retain(domain)
		header.number = code
		return owner
	}
	return ns_error_create(domain, code, 0)
}

fn match_case(api MatchApi, source u64, owner u64, expected bool) {
	mut result := [u64(0xcafe), 0, 0, 0, 0xbeef]!
	before := api.refs(owner)
	api.probe(source, owner, api.metadata, api.table, api.entry, unsafe { &result[1] })
	assert result == [u64(0xcafe), if expected { u64(1) } else { u64(0) }, 0x5020, 0x5021, 0xbeef]!
	assert api.refs(owner) == before
}

fn match_worker(api MatchApi, owner u64) {
	mut pool := u64(0)
	if api.native { pool = unsafe { MatchPoolPush(voidptr(api.pool_push))() } }
	defer { if api.native { unsafe { MatchPoolPop(voidptr(api.pool_pop))(pool) } } }
	entry := unsafe { MatchCall(voidptr(api.entry)) }
	mut code := i64(516)
	for _ in 0 .. 256 {
		assert entry(u64(unsafe { &code }), owner, api.metadata, api.table)
	}
}

fn match_run(api MatchApi, source u64, guard u64) {
	for domain_text in ['NSCocoaErrorDomain', 'NSPOSIXErrorDomain', 'nscocoaerrordomain', '',
		'NSCocoaErrorDomain\x00suffix', 'Fortnite é 🎮']! {
		domain := api.text(domain_text)
		for kind in 0 .. 2 {
			for code in [i64(0), 516, -1, i64(9223372036854775807), -i64(9223372036854775807) - 1]! {
				owner := api.make(kind, domain, code)
				assert owner != 0
				domain_before := api.refs(domain)
				for pattern in [code, code ^ 1]! {
					assert C.mprotect(unsafe { voidptr(source & ~u64(C.getpagesize() - 1)) }, usize(C.getpagesize()), C.PROT_READ | C.PROT_WRITE) == 0
					unsafe { *(&i64(source)) = pattern }
					assert C.mprotect(unsafe { voidptr(source & ~u64(C.getpagesize() - 1)) }, usize(C.getpagesize()), C.PROT_READ) == 0
					match_case(api, source, owner, domain_text == 'NSCocoaErrorDomain' && pattern == code)
					assert read64(source) == u64(pattern)
				}
				if domain_text != 'NSCocoaErrorDomain' {
					match_case(api, guard, owner, false)
					match_case(api, 0, owner, false)
				}
				assert api.refs(domain) == domain_before
				api.drop(owner)
			}
		}
		api.drop(domain)
	}
	domain := api.text('NSCocoaErrorDomain')
	owner := api.make(0, domain, 516)
	before := api.refs(owner)
	mut workers := []thread{cap: 8}
	for _ in 0 .. 8 { workers << spawn match_worker(api, owner) }
	workers.wait()
	assert api.refs(owner) == before
	api.drop(owner)
	api.drop(domain)
}

fn match_rejections(api MatchApi, source u64, guard u64) {
	for metadata in [u64(0), 1, guard, swift_integer_metadata()]! {
		if _ := swift_cocoa_match_checked(guard, guard, metadata, guard) {
			assert false
		}
	}
	if _ := swift_cocoa_match_checked(guard, guard, api.metadata, guard) {
		assert false
	}
	for owner in [u64(0), 1, guard, 0x8000000000000010]! {
		if _ := swift_cocoa_match_checked(guard, owner, api.metadata, api.table) {
			assert false
		}
	}
	other := objc_allocate(ios_runtime.names['NSObject'])
	if _ := swift_cocoa_match_checked(guard, other, api.metadata, api.table) {
		assert false
	}
	objc_release(other)
	if _ := swift_cocoa_match_checked(guard, other, api.metadata, api.table) {
		assert false
	}
	domain := api.text('NSCocoaErrorDomain')
	owner := api.make(0, domain, 516)
	mut header := obj_header(owner)
	for invalid in [u64(0), 1, source + 1]! {
		if _ := swift_cocoa_match_checked(invalid, owner, api.metadata, api.table) {
			assert false
		}
	}
	for phase in 0 .. 4 {
		header.releasing = phase == 0
		header.destroying = phase == 1
		header.destroyed = phase == 2
		header.refs = if phase == 3 { i64(0) } else { i64(1) }
		if _ := swift_cocoa_match_checked(guard, owner, api.metadata, api.table) {
			assert false
		}
	}
	header.releasing = false
	header.destroying = false
	header.destroyed = false
	header.refs = 1
	for invalid in [u64(0), guard, owner]! {
		header.fields[0] = invalid
		if _ := swift_cocoa_match_checked(guard, owner, api.metadata, api.table) {
			assert false
		}
	}
	header.fields[0] = domain
	original := read64(owner)
	unsafe { *(&u64(owner)) = 0 }
	if _ := swift_cocoa_match_checked(guard, owner, api.metadata, api.table) {
		assert false
	}
	unsafe { *(&u64(owner)) = original }
	api.drop(owner)
	api.drop(domain)
	subclass := objc_allocate_class(ios_runtime.names['NSError'], c'VinixCocoaMatchSubclass', 0)
	objc_register_class(subclass)
	domain2 := api.text('NSCocoaErrorDomain')
	derived := api.make(1, domain2, 516)
	objc_set_class(derived, subclass)
	if _ := swift_cocoa_match_checked(guard, derived, api.metadata, api.table) {
		assert false
	}
	api.drop(derived)
	api.drop(domain2)
	ios_runtime.swift_concurrency_retired = true
	if _ := swift_cocoa_match_checked(guard, guard, api.metadata, api.table) {
		assert false
	}
	if _ := swift_cocoa_error_symbol('_$s10Foundation18_ErrorCodeProtocolPAAE2teoiySbx_s0B0_ptFZ') {
		assert false
	}
	ios_runtime.swift_concurrency_retired = false
}

fn match_publish() u64 {
	mut result := u64(0)
	for _ in 0 .. 128 {
		for library in ['/System/Library/Frameworks/Foundation.framework/Foundation',
			'/usr/lib/swift/libswiftFoundation.dylib']! {
			result = runtime_symbol(library, '_$s10Foundation18_ErrorCodeProtocolPAAE2teoiySbx_s0B0_ptFZ') or { panic(err) }
		}
	}
	return result
}

fn test_swift_cocoa_match() {
	$if !arm64 {
		return
	}
	page := usize(C.getpagesize())
	mapping := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert mapping != u64(-1)
	source := mapping + u64(page * 2) - 8
	guard := mapping + u64(page * 2)
	assert C.mprotect(unsafe { voidptr(guard) }, page, C.PROT_NONE) == 0
	// Ordinary C caller -> native Swift generic entry; preserve caller Swift
	// context/error registers and record the Bool with adjacent output guards.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0503f3, 0xaa0403f0, 0xd28a0414,
		0xd28a0435, 0xd63f0200, 0xa9005260, 0xf9000a75, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! {
		write32(mapping + u64(i * 4), op)
	}
	C.__builtin___clear_cache(unsafe { voidptr(mapping) }, unsafe { voidptr(mapping + 56) })
	assert C.mprotect(unsafe { voidptr(mapping) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { MatchProbe(voidptr(mapping)) }
	$if macos {
		foundation := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		objc := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)
		access := unsafe { MatchMetadata(C.dlsym(foundation, c'$s10Foundation10CocoaErrorV4CodeVMa')) }
		response := access(0)
		lookup := unsafe { MatchWitness(C.dlsym(core, c'swift_getWitnessTable')) }
		table := lookup(u64(C.dlsym(foundation, c'$s10Foundation10CocoaErrorV4CodeVAA01_cD8ProtocolAAMc')), response.metadata, 0)
		api := MatchApi{ native: true, entry: u64(C.dlsym(foundation, c'$s10Foundation18_ErrorCodeProtocolPAAE2teoiySbx_s0B0_ptFZ')), metadata: response.metadata, table: table, probe: probe, send: u64(C.dlsym(objc, c'objc_msgSend')), pool_push: u64(C.dlsym(objc, c'objc_autoreleasePoolPush')), pool_pop: u64(C.dlsym(objc, c'objc_autoreleasePoolPop')) }
		assert api.entry != 0 && api.table != 0 && api.pool_push != 0 && api.pool_pop != 0
		alias := C.dlopen(c'/usr/lib/swift/libswiftFoundation.dylib', 2)
		assert u64(C.dlsym(alias, c'$s10Foundation18_ErrorCodeProtocolPAAE2teoiySbx_s0B0_ptFZ')) == api.entry
		pool := unsafe { MatchPoolPush(voidptr(api.pool_push))() }
		match_run(api, source, guard)
		unsafe { MatchPoolPop(voidptr(api.pool_pop))(pool) }
		println('IOS-COCOA-MATCH-NATIVE: generic x0/x1/x2/x3 ABI, Cocoa domain and full-width code matching for CFError/NSError, wrong-domain protected match bytes unread, readonly edge input, x20/x21 and borrowed ARC, eight workers')
	}
	if _ := swift_cocoa_match_checked(guard, guard, guard, guard) {
		assert false
	}
	for _ in 0 .. 2 {
		objc_start()
		mut workers := []thread u64{}
		for _ in 0 .. 8 { workers << spawn match_publish() }
		entries := workers.wait()
		for candidate in entries {
			assert candidate == entries[0]
		}
		arena := swift_cocoa_error_arena_checked() or { panic(err) }
		metadata := arena + u64(page) + 16
		table := swift_cocoa_error_table_checked(metadata) or { panic(err) }
		api := MatchApi{ entry: entries[0], metadata: metadata, table: table, probe: probe }
		for library in ['/System/Library/Frameworks/UIKit.framework/UIKit',
			'/usr/lib/swift/libswiftCore.dylib']! {
			if _ := runtime_symbol(library, '_$s10Foundation18_ErrorCodeProtocolPAAE2teoiySbx_s0B0_ptFZ') {
				assert false
			}
		}
		match_run(api, source, guard)
		match_rejections(api, source, guard)
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_arrays.len == 0 && ios_runtime.swift_strings.len == 0
		objc_stop()
		if _ := swift_cocoa_match_checked(guard, guard, metadata, table) {
			assert false
		}
		if _ := runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', '_$s10Foundation18_ErrorCodeProtocolPAAE2teoiySbx_s0B0_ptFZ') {
			assert false
		}
	}
	assert C.munmap(unsafe { voidptr(mapping) }, page * 3) == 0
	println('IOS-COCOA-MATCH: canonical Cocoa Code specialization, content domain/code equality, borrowed CFError/NSError ownership and Swift registers, guard-edge/protected input, exact aliases, concurrent calls/publication, unsupported metadata/tables/owners/subclasses/invalid fields rejected, two drained lifetimes')
}
