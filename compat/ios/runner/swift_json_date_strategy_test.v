// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import strconv

#include <dlfcn.h>

$if macos {
	#include <objc/runtime.h>
	#include <mach/mach.h>
}

fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.mach_task_self() u32
fn C.vm_region_64(u32, &u64, &u64, i32, &i32, &u32, &u32) i32
fn C.mach_port_deallocate(u32, u32) i32

const strategy_ma = '_$s10Foundation11JSONEncoderC20DateEncodingStrategyOMa'
const strategy_mn = '_$s10Foundation11JSONEncoderC20DateEncodingStrategyOMn'

type StrategyAccess = fn (u64) SwiftAssociatedMetadata
type StrategyAccessProbe = fn (u64, u64, &u64)
type StrategyTransfer = fn (u64, u64, u64) u64
type StrategyDestroy = fn (u64, u64)
type StrategyTag = fn (u64, u64) u32
type StrategyInject = fn (u64, u32, u64)
type StrategyGet = fn (u64, u32, u64) u32
type StrategyPut = fn (u64, u32, u32, u64)
type StrategyAllocate = fn (u64, u64, u64) u64
type StrategyDeallocate = fn (u64, u64, u64)
type StrategySign = fn (u64, u64) u64
type StrategyMessage = fn (u64, u64) u64

struct StrategyAPI {
	native           bool
	metadata         u64
	witness          u64
	context_metadata u64
	allocate         StrategyAllocate   = unsafe { nil }
	deallocate       StrategyDeallocate = unsafe { nil }
	message          StrategyMessage    = unsafe { nil }
}

struct StrategyContext {
	api StrategyAPI
mut:
	calls        u64
	destination  u64
	observed_tag u8
}

fn strategy_context_destroy(owner u64) {
	mut state := unsafe { &StrategyContext(read64(owner + 16)) }
	state.calls++
	if state.destination != 0 { state.observed_tag = unsafe { *(&u8(state.destination + 16)) } }
	state.api.deallocate(owner, 24, 7)
}

fn strategy_word(p u64, value u64) {
	unsafe { *(&u64(p)) = value }
}

fn strategy_bytes(p u64) []u8 { return unsafe { (&u8(p)).vbytes(24) }.clone() }

fn strategy_seed(p u64) {
	for i in u64(0) .. 24 {
		unsafe { *(&u8(p + i)) = u8(0xa0 + i) }
	}
}

fn strategy_canary(p u64) {
	for i in u64(17) .. 24 {
		assert unsafe { *(&u8(p + i)) } == u8(0xa0 + i)
	}
}

fn strategy_source_padding(p u64) {
	for i in u64(17) .. 24 {
		unsafe { *(&u8(p + i)) = u8(0xd0 + i) }
	}
}

fn strategy_copied(destination u64, source []u8) {
	actual := strategy_bytes(destination)
	assert actual[..17] == source[..17]
	strategy_canary(destination)
}

fn strategy_owner(api StrategyAPI, which u32, mut state StrategyContext) u64 {
	if which == 0 {
		$if macos {
			if api.native {
				return api.message(u64(C.objc_getClass(c'NSDateFormatter')), u64(C.sel_registerName(c'new')))
			}
		}
		return objc_allocate(ios_runtime.names['NSObject'])
	}
	if which == 1 {
		owner := api.allocate(api.context_metadata, 24, 7)
		strategy_word(owner + 16, u64(unsafe { &state }))
		return owner
	}
	return 0
}

fn strategy_init(api StrategyAPI, p u64, which u32, mut state StrategyContext) u64 {
	strategy_seed(p)
	owner := strategy_owner(api, which, mut state)
	if which == 0 {
		strategy_word(p, owner)
	} else if which == 1 {
		strategy_word(p, 0x123456789abcdef0)
		strategy_word(p + 8, owner)
	}
	inject := unsafe { StrategyInject(voidptr(read64(api.witness + 104) & 0x0000ffffffffffff)) }
	inject(p, which, api.metadata)
	return owner
}

fn strategy_refs(api StrategyAPI, owner u64, which u32) u64 {
	if which == 1 { return (read64(owner + 8) >> 33) + 1 }
	$if macos {
		if api.native { return api.message(owner, u64(C.sel_registerName(c'retainCount'))) }
	}
	return u64(obj_header(owner).refs)
}

fn strategy_values(api StrategyAPI) {
	tag := unsafe { StrategyTag(voidptr(read64(api.witness + 88) & 0x0000ffffffffffff)) }
	project := unsafe { StrategyDestroy(voidptr(read64(api.witness + 96) & 0x0000ffffffffffff)) }
	destroy := unsafe { StrategyDestroy(voidptr(read64(api.witness + 8) & 0x0000ffffffffffff)) }
	// Every copy/take slot, both payload kinds, all empty cases, and exact byte
	// effects. A moved-from value is uninitialized and is never destroyed twice.
	for slot in [u64(0), 16, 32]! {
		for which in u32(0) .. 6 {
			mut state := StrategyContext{ api: api }
			mut storage := [12]u64{}
			s := u64(unsafe { &storage[1] })
			d := u64(unsafe { &storage[7] })
			owner := strategy_init(api, s, which, mut state)
			strategy_source_padding(s)
			strategy_seed(d)
			before := strategy_bytes(s)
			transfer := unsafe { StrategyTransfer(voidptr(read64(api.witness + slot) & 0x0000ffffffffffff)) }
			assert transfer(d, s, api.metadata) == d
			assert strategy_bytes(s) == before && tag(d, api.metadata) == which
			strategy_copied(d, before)
			if which < 2 {
				assert strategy_refs(api, owner, which) == if slot == 32 { u64(1) } else { u64(2) }
			}
			if slot != 32 {
				destroy(s, api.metadata)
				assert strategy_bytes(s) == before
			}
			project(d, api.metadata)
			strategy_copied(d, before)
			destroy(d, api.metadata)
			strategy_copied(d, before)
			assert state.calls == if which == 1 {
				u64(1)
			} else {
				u64(0)
			}
		}
	}
	// All 36 case transitions for both assignment witnesses. The old closure's
	// destructor observes the old tag: native assignment destroys before copy.
	for slot in [u64(24), 40]! {
		for old in u32(0) .. 6 {
			for which in u32(0) .. 6 {
				mut previous := StrategyContext{ api: api }
				mut next := StrategyContext{ api: api }
				mut storage := [12]u64{}
				s := u64(unsafe { &storage[1] })
				d := u64(unsafe { &storage[7] })
				previous.destination = d
				strategy_init(api, d, old, mut previous)
				owner := strategy_init(api, s, which, mut next)
				strategy_source_padding(s)
				before := strategy_bytes(s)
				transfer := unsafe { StrategyTransfer(voidptr(read64(api.witness + slot) & 0x0000ffffffffffff)) }
				assert transfer(d, s, api.metadata) == d
				assert strategy_bytes(s) == before && tag(d, api.metadata) == which
				strategy_copied(d, before)
				assert previous.calls == if old == 1 { u64(1) } else { u64(0) }
				if old == 1 {
					assert previous.observed_tag == 1
				}
				if which < 2 {
					assert strategy_refs(api, owner, which) == if slot == 40 {
						u64(1)
					} else {
						u64(2)
					}
				}
				if slot == 24 { destroy(s, api.metadata) }
				destroy(d, api.metadata)
				assert next.calls == if which == 1 { u64(1) } else { u64(0) }
			}
		}
	}
	// Vinix defensively handles self-copy. The native layout-string assignment
	// witness releases before copying and is tested only with distinct storage.
	if !api.native {
		for which in u32(0) .. 6 {
			mut state := StrategyContext{ api: api }
			mut storage := [4]u64{}
			p := u64(unsafe { &storage[0] })
			owner := strategy_init(api, p, which, mut state)
			before := strategy_bytes(p)
			assign := unsafe { StrategyTransfer(voidptr(read64(api.witness + 24) & 0x0000ffffffffffff)) }
			assert assign(p, p, api.metadata) == p && strategy_bytes(p) == before && state.calls == 0
			if which < 2 {
				assert strategy_refs(api, owner, which) == 1
			}
			destroy(p, api.metadata)
		}
	}
}

fn strategy_copy_worker(api StrategyAPI, source u64, which u32) {
	copy_value := unsafe { StrategyTransfer(voidptr(read64(api.witness + 16) & 0x0000ffffffffffff)) }
	destroy := unsafe { StrategyDestroy(voidptr(read64(api.witness + 8) & 0x0000ffffffffffff)) }
	tag := unsafe { StrategyTag(voidptr(read64(api.witness + 88) & 0x0000ffffffffffff)) }
	for _ in 0 .. 128 {
		mut storage := [4]u64{}
		p := u64(unsafe { &storage[0] })
		strategy_seed(p)
		assert copy_value(p, source, api.metadata) == p && tag(p, api.metadata) == which
		strategy_canary(p)
		destroy(p, api.metadata)
	}
}

fn strategy_readers(api StrategyAPI) {
	page := usize(C.getpagesize())
	base := u64(C.mmap(unsafe { nil }, page * 3, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert base != u64(-1)
	destroy := unsafe { StrategyDestroy(voidptr(read64(api.witness + 8) & 0x0000ffffffffffff)) }
	for which in u32(0) .. 6 {
		assert C.mprotect(voidptr(base + u64(page)), page, C.PROT_READ | C.PROT_WRITE) == 0
		source := base + u64(page) * 2 - 24
		mut state := StrategyContext{ api: api }
		owner := strategy_init(api, source, which, mut state)
		strategy_source_padding(source)
		before := strategy_bytes(source)
		assert C.mprotect(voidptr(base + u64(page)), page, C.PROT_READ) == 0
		mut workers := []thread{}
		for _ in 0 .. 8 { workers << spawn strategy_copy_worker(api, source, which) }
		workers.wait()
		assert strategy_bytes(source) == before && state.calls == 0
		if which < 2 {
			assert strategy_refs(api, owner, which) == 1
		}
		destroy(source, api.metadata)
		assert strategy_bytes(source) == before && state.calls == if which == 1 {
			u64(1)
		} else {
			u64(0)
		}
	}
	assert C.munmap(voidptr(base), page * 3) == 0
}

fn strategy_tags(api StrategyAPI) {
	inject := unsafe { StrategyInject(voidptr(read64(api.witness + 104) & 0x0000ffffffffffff)) }
	tag := unsafe { StrategyTag(voidptr(read64(api.witness + 88) & 0x0000ffffffffffff)) }
	get := unsafe { StrategyGet(voidptr(read64(api.witness + 48) & 0x0000ffffffffffff)) }
	put := unsafe { StrategyPut(voidptr(read64(api.witness + 56) & 0x0000ffffffffffff)) }
	for which in u32(0) .. 6 {
		mut storage := [4]u64{}
		p := u64(unsafe { &storage[0] })
		strategy_seed(p)
		inject(p, which, api.metadata)
		assert tag(p, api.metadata) == which
		strategy_canary(p)
		if which >= 2 {
			assert read64(p) == u64(which - 2) && read64(p + 8) == 0 && unsafe { *(&u8(p + 16)) } == 2
		} else {
			assert read64(p) == 0xa7a6a5a4a3a2a1a0 && read64(p + 8) == 0xafaeadacabaaa9a8
		}
	}
	for count in [u32(0), 1, 252, 253, 254, 255, 256, 65535, 0xffffffff]! {
		for which in [u32(0), 1, 2, 252, 253, 254, 255, 256, 65535, 0xffffffff]! {
			if which > count { continue }
			mut storage := [4]u64{}
			p := u64(unsafe { &storage[0] })
			strategy_seed(p)
			put(p, which, count, api.metadata)
			assert get(p, count, api.metadata) == if count == 0 {
				u32(0)
			} else if which == 0 {
				u32(80)
			} else {
				which
			}
			for i in u64(0) .. 24 {
				mut expected := u8(0xa0 + i)
				if which > 253 {
					expected = if i < 4 {
						u8((which - 254) >> (i * 8))
					} else if i <= 16 {
						u8(0)
					} else if i == 17 {
						u8(1)
					} else {
						expected
					}
				} else if i == 16 && which != 0 {
					expected = u8(u32(0) - which)
				} else if i == 17 && count >= 254 {
					expected = 0
				}
				assert unsafe { *(&u8(p + i)) } == expected
			}
		}
	}
	// No tag-byte read at all for a zero population. The enum's tail byte is
	// sufficient through 253 optional cases; 254 adds exactly one tag byte.
	page := usize(C.getpagesize())
	base := u64(C.mmap(unsafe { nil }, page * 2, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert base != u64(-1)
	guard := base + u64(page)
	assert C.mprotect(voidptr(guard), page, C.PROT_NONE) == 0
	assert get(guard, 0, guard) == 0
	put(guard, 0, 0, guard)
	for count in [u32(253), 254, 0xffffffff]! {
		p := guard - if count < 254 { u64(17) } else { u64(18) }
		for which in [u32(0), 1, 253]! {
			unsafe { *(&u8(p + 16)) = 0 }
			put(p, which, count, guard)
			assert get(p, count, guard) == which
		}
	}
	assert C.munmap(voidptr(base), page * 2) == 0
}

fn strategy_publication(framework bool) u64 {
	library := if framework {
		'/System/Library/Frameworks/Foundation.framework/Foundation'
	} else {
		'/usr/lib/swift/libswiftFoundation.dylib'
	}
	mut entry := u64(0)
	for _ in 0 .. 128 { entry = runtime_symbol(library, strategy_ma) or { panic(err) } }
	return entry
}

fn strategy_mapping(address u64, mapped bool, executable bool) {
	$if macos {
		mut start := address
		mut size := u64(0)
		mut info := [16]i32{}
		mut count := u32(C.VM_REGION_BASIC_INFO_COUNT_64)
		mut object := u32(0)
		task := C.mach_task_self()
		status := C.vm_region_64(task, &start, &size, C.VM_REGION_BASIC_INFO_64, unsafe { &info[0] }, &count, &object)
		if mapped {
			assert status == 0 && start <= address && address < start + size && info[0] == (C.PROT_READ | if executable {
				C.PROT_EXEC
			} else {
				0
			})
		} else {
			assert status != 0 || start > address
		}
		if object != 0 {
			assert C.mach_port_deallocate(task, object) == 0
		}
	} $else {
		mut found := false
		for line in (os.read_file('/proc/self/maps') or { panic(err) }).split_into_lines() {
			f := line.fields()
			if f.len < 2 { continue }
			r := f[0].split('-')
			if r.len != 2 { continue }
			a := strconv.parse_uint(r[0], 16, 64) or { panic(err) }
			b := strconv.parse_uint(r[1], 16, 64) or { panic(err) }
			if address >= a && address < b {
				assert mapped && f[1] == if executable { 'r-xp' } else { 'r--p' }
				found = true
			}
		}
		assert found == mapped
	}
}

fn strategy_suite(native bool, code u64, context_metadata u64, entry u64, descriptor u64) {
	access := unsafe { StrategyAccess(voidptr(entry)) }
	response := access(0)
	md := response.metadata
	assert response.state == 0 && read64(md) == 0x201 && read64(md + 8) == descriptor
	wt := read64(md - 8) & 0x0000ffffffffffff
	assert read64(wt + 64) == 17 && read64(wt + 72) == 24 && read32(wt + 84) == 253
	assert read32(wt + 80) == if native { u32(0x02210007) } else { u32(0x00210007) }
	probe := unsafe { StrategyAccessProbe(voidptr(code + 64)) }
	for request in [u64(0), 0xff, 0x100, 0x1ff, ~u64(0)]! {
		mut result := [u64(0xcafe), 0, 0, 0, 0, 0xbeef]!
		probe(request, entry, unsafe { &result[1] })
		assert result == [u64(0xcafe), md, 0, 0x5020, 0x5021, 0xbeef]!
	}
	mut allocate := u64(unsafe { voidptr(swift_heap_allocate) })
	mut deallocate := u64(unsafe { voidptr(swift_heap_deallocate) })
	mut message := u64(0)
	$if macos {
		if native {
			core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
			objc := C.dlopen(c'/usr/lib/libobjc.A.dylib', 2)
			allocate = u64(C.dlsym(core, c'swift_allocObject'))
			deallocate = u64(C.dlsym(core, c'swift_deallocObject'))
			message = u64(C.dlsym(objc, c'objc_msgSend'))
		}
	}
	api := StrategyAPI{ native: native, metadata: md, witness: wt, context_metadata: context_metadata, allocate: unsafe { StrategyAllocate(voidptr(allocate)) }, deallocate: unsafe { StrategyDeallocate(voidptr(deallocate)) }, message: unsafe { StrategyMessage(voidptr(message)) } }
	strategy_tags(api)
	strategy_values(api)
	strategy_readers(api)
	if !native {
		strategy_mapping(entry, true, true)
		strategy_mapping(md, true, false)
		assert read32(descriptor) == 0x52 && read32(descriptor + 16) == 0 && read32(descriptor + 20) == 2 && read32(descriptor + 24) == 4
		// Exercise non-POD enum ownership through the existing Array machinery.
		mut state := StrategyContext{ api: api }
		array := swift_array_allocate(3, md)
		for i in u64(0) .. 3 { strategy_init(api, array.bytes + i * 24, u32(i), mut state) }
		swift_bridge_release(array.owner)
		assert state.calls == 1 && ios_runtime.swift_arrays.len == 0
	}
}

fn test_swift_json_date_strategy() {
	$if !arm64 {
		return
	}
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	for i, op in [u32(0xaa1403e0), 0x58000070, 0xd61f0200, 0xd503201f, 0, 0, 0, 0, 0xdac10020,
		0xd65f03c0]! {
		write32(code + u64(i * 4), op)
	}
	strategy_word(code + 16, u64(unsafe { voidptr(strategy_context_destroy) }))
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0203f3, 0xaa0103f0, 0xd28a0414,
		0xd28a0435, 0xd63f0200, 0xa9000660, 0xa9015674, 0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! {
		write32(code + 64 + u64(i * 4), op)
	}
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 120))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	for native in [true, false, false]! {
		$if !macos {
			if native { continue }
		}
		words := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
		assert words != u64(-1)
		context_metadata := words + 24
		strategy_word(context_metadata, 0x400)
		strategy_word(context_metadata - 16, code)
		mut entry := u64(0)
		mut descriptor := u64(0)
		if native {
			$if macos {
				sign := unsafe { StrategySign(voidptr(code + 32)) }
				strategy_word(context_metadata - 16, sign(code, (context_metadata - 16) | (u64(0xbbbf) << 48)))
				h := C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation', 2)
				entry = u64(C.dlsym(h, strategy_ma[1..].str))
				descriptor = u64(C.dlsym(h, strategy_mn[1..].str))
			}
		} else {
			if _ := swift_json_date_arena() {
				assert false
			}
			objc_start()
			mut workers := []thread u64{}
			for i in 0 .. 8 { workers << spawn strategy_publication(i % 2 == 0) }
			entries := workers.wait()
			entry = entries[0]
			for value in entries {
				assert value == entry
			}
			descriptor = runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', strategy_mn) or { panic(err) }
		}
		assert entry != 0 && descriptor != 0
		assert C.mprotect(voidptr(words), page, C.PROT_READ) == 0
		strategy_suite(native, code, context_metadata, entry, descriptor)
		if native {
			println('IOS-JSON-DATE-STRATEGY-NATIVE: complete metadata, exact enum/optional tags, all ownership transfers and distinct-storage assignment transitions, guarded tag spans, closure destruction and formatter ARC measured')
		} else {
			assert ios_runtime.swift_heap.len == 0
			if _ := framework_symbol('/System/Library/Frameworks/UIKit.framework/UIKit', strategy_ma) {
				assert false
			}
			if _ := swift_foundation_symbol('_$s10Foundation11JSONEncoderCACycfc') {
				assert false
			}
			arena := ios_runtime.swift_json_date_arena
			objc_stop()
			assert ios_runtime.swift_json_date_arena == 0 && ios_runtime.swift_json_date_retired
			strategy_mapping(arena, false, false)
			strategy_mapping(arena + u64(page), false, false)
			if _ := swift_json_date_arena() {
				assert false
			}
		}
		assert C.munmap(voidptr(words), page) == 0
	}
	assert C.munmap(voidptr(code), page) == 0
	println('IOS-JSON-DATE-STRATEGY: native-matched 17-byte enum witnesses, payload ownership, optional spare tags, complete metadata, non-POD Array destruction, concurrent aliases and two unmapped retirements; encoding backend unsupported')
}
