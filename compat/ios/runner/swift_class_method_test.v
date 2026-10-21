// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type LmProbe = fn (u64, u64, u64, u64, u64, &u64, u64)
struct LmApi { native bool entry u64 code u64 guard u64 }

fn lm_call(api LmApi, metadata u64, method u64, description u64) u64 {
	mut words := [u64(0xcafe), 0, 0, 0, 0, 0, 0xbeef]!
	unsafe { LmProbe(voidptr(api.code))(metadata, method, description, api.guard, api.entry, &words[1], api.guard) }
	assert words[0] == 0xcafe && words[6] == 0xbeef && words[3] == api.guard && words[4] == 0x5121 && words[5] == 0x5222
	return words[1]
}
fn lm_worker(api LmApi, metadata u64, description u64, count u64, expected u64) {
	for _ in 0 .. 128 { for i in 0 .. count { assert lm_call(api, metadata, description + 52 + i * 8, description) == expected + i * 16 } }
}
fn lm_readers(api LmApi, metadata u64, description u64, count u64, expected u64) {
	mut workers := []thread{}
	for _ in 0 .. 8 { workers << spawn lm_worker(api, metadata, description, count, expected) }; workers.wait(); unsafe { workers.free() }
}
fn lm_bad(metadata u64, method u64, description u64) {
	if _ := swift_class_method_checked(metadata, method, description) { assert false, 'unsupported class method accepted' }
}
fn lm_metadata(metadata u64, description u64, words u64, parent u64, expected u64) {
	for i in 0 .. words { unsafe { *(&u64(metadata + i * 8)) = expected } }
	unsafe {
		*(&u64(metadata)) = 0; *(&u64(metadata + 8)) = parent; *(&u64(metadata + 32)) = 2
		*(&u64(metadata + 56)) = (u64(24) << 32) | (words * 8 + 24)
		*(&u64(metadata + 64)) = description
	}
}
fn lm_suite(api LmApi) {
	page := u64(C.getpagesize())
	md := u64(C.mmap(unsafe { nil }, usize(page * 3), C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	dd := u64(C.mmap(unsafe { nil }, usize(page * 3), C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert md != ~u64(0) && dd != ~u64(0)
	defer { assert C.munmap(voidptr(md), usize(page * 3)) == 0; assert C.munmap(voidptr(dd), usize(page * 3)) == 0 }
	assert C.mprotect(voidptr(md + page), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
	assert C.mprotect(voidptr(dd + page), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
	// All six measured Fortnite descriptor shapes. Method implementations are
	// zero and descriptor/name/accessor pointers are inaccessible: only the
	// metadata vtable may supply the answer, without invoking the target.
	for shape in [[u64(13), 12, 1]!, [u64(13), 12, 1]!, [u64(15), 14, 1]!, [u64(15), 11, 4]!, [u64(14), 11, 3]!, [u64(14), 13, 1]!]! {
		words := shape[0]; offset := shape[1]; count := shape[2]
		for edge in [false, true]! {
			metadata := if edge { md + page * 2 - words * 8 } else { md + page }
			description := if edge { dd + page * 2 - 52 - count * 8 } else { dd + page }
			for i in 0 .. 13 + count * 2 { write32(description + i * 4, 0) }
			write32(description, 0x80000050); write32(description + 8, u32(api.guard)); write32(description + 12, u32(api.guard))
			write32(description + 24, 3); write32(description + 28, u32(words)); write32(description + 32, u32(words - 10))
			write32(description + 44, u32(offset)); write32(description + 48, u32(count))
			lm_metadata(metadata, description, words, 0, api.guard)
			for i in 0 .. count { write32(description + 52 + i * 8, if i == 0 { u32(1) } else { u32(0x10) }); unsafe { *(&u64(metadata + (offset + i) * 8)) = api.guard + i * 16 } }
			assert C.mprotect(voidptr(md + page), usize(page), C.PROT_READ) == 0 && C.mprotect(voidptr(dd + page), usize(page), C.PROT_READ) == 0
			lm_readers(api, metadata, description, count, api.guard)
			assert C.mprotect(voidptr(md + page), usize(page), C.PROT_READ | C.PROT_WRITE) == 0 && C.mprotect(voidptr(dd + page), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
			// The descendant overrides each inherited slot. Its own descriptor
			// is intentionally inaccessible; lookup only compares its identity.
			parent := md + page + 512; child := metadata
			lm_metadata(parent, description, words, 0, api.guard)
			lm_metadata(child, api.guard, words, parent, api.guard)
			for i in 0 .. count { unsafe { *(&u64(child + (offset + i) * 8)) = api.guard + 128 + i * 16 } }
			assert C.mprotect(voidptr(md + page), usize(page), C.PROT_READ) == 0 && C.mprotect(voidptr(dd + page), usize(page), C.PROT_READ) == 0
			lm_readers(api, child, description, count, api.guard + 128)
			assert C.mprotect(voidptr(md + page), usize(page), C.PROT_READ | C.PROT_WRITE) == 0 && C.mprotect(voidptr(dd + page), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
			// A null vtable entry is returned unchanged, as native Swift does.
			unsafe { *(&u64(child + offset * 8)) = 0 }; assert lm_call(api, child, description + 52, description) == 0
		}
	}
	if api.native { return }
	metadata := md + page; description := dd + page; method := description + 52
	lm_metadata(metadata, description, 16, 0, api.guard)
	write32(description, 0x80000050); write32(description + 28, 16); write32(description + 44, 12); write32(description + 48, 2)
	for pointer in [u64(0), 1, ~u64(0), ~u64(7)]! { lm_bad(pointer, method, description); lm_bad(metadata, method, pointer) }
	for pointer in [u64(0), method - 1, method + 1, method + 4, method + 16, ~u64(0)]! { lm_bad(metadata, pointer, description) }
	// Unsupported descriptor profiles fail with only their flags readable.
	header := dd + page * 2 - 4
	for flags in [u32(0), 0x80000051, 0x800000d0, 0x80000150, 0xa0000050, 0x80010050, 0x80020050, 0x80030050]! { write32(header, flags); lm_bad(api.guard, api.guard, header) }
	for count in [u32(0), 0xffffffff]! { write32(description + 48, count); lm_bad(metadata, method, description) }; write32(description + 48, 2)
	for offset in [u32(0), 9, 15, 0xffffffff]! { write32(description + 44, offset); lm_bad(metadata, method, description) }; write32(description + 44, 12)
	write32(description + 28, 13); lm_bad(metadata, method, description); write32(description + 28, 16)
	// Nonclass kinds are rejected before any class-prefix reads.
	for kind in [u64(1), 0x200, 0x305, 0x7ff]! { unsafe { *(&u64(md + page * 2 - 8)) = kind }; lm_bad(md + page * 2 - 8, method, description) }
	unsafe { *(&u64(metadata + 32)) = 0 }; lm_bad(metadata, method, description); unsafe { *(&u64(metadata + 32)) = 2 }
	for size in [u64(0), 79, 127, u64(24) << 32 | 24, u64(25) << 32 | 160, u64(160) << 32 | 24]! { unsafe { *(&u64(metadata + 56)) = size }; lm_bad(metadata, method, description) }
	lm_metadata(metadata, api.guard, 16, 0, api.guard); lm_bad(metadata, method, description)
	unsafe { *(&u64(metadata + 8)) = metadata }; lm_bad(metadata, method, description)
	lm_metadata(metadata, description, 16, 0, api.guard)
	assert ios_runtime.live == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.swift_heap_sequence == 0
	ios_runtime.swift_concurrency_retired = true; lm_bad(api.guard, api.guard, api.guard); ios_runtime.swift_concurrency_retired = false
	assert C.mprotect(voidptr(md + page), usize(page), C.PROT_READ) == 0 && C.mprotect(voidptr(dd + page), usize(page), C.PROT_READ) == 0
	objc_stop(); lm_bad(api.guard, api.guard, api.guard)
	assert read64(metadata + 64) == description && read32(description) == 0x80000050
}

fn test_swift_class_method() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0)); assert code != ~u64(0) && guard != ~u64(0)
	defer { assert C.munmap(voidptr(code), page) == 0; assert C.munmap(voidptr(guard), page) == 0 }
	// Exercise the public three-argument C entry with inaccessible x8 and
	// saved-register canaries, matching Fortnite's tail-forwarding ABI.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0503f3, 0xaa0403f0, 0xaa0603f4, u32(0xd2800000 | (0x5121 << 5) | 21), u32(0xd2800000 | (0x5222 << 5) | 22), 0xaa0603e8, 0xd63f0200, 0xa9000660, 0xa9015674, 0xf9001276, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 68)); assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2); assert core != unsafe { nil }
		entry := u64(C.dlsym(core, c'swift_lookUpClassMethod')); assert entry != 0
		lm_suite(LmApi{true, entry, code, guard})
		println('NATIVE-CLASS-METHOD: six Fortnite vtable shapes, direct and inherited overridden slots, exact guarded readonly metadata/descriptors, null entries, eight readers, x0/x1/x2 input and x0 return preserving x20/x21/x22 with inaccessible x8')
	}
	for _ in 0 .. 2 {
		objc_start()
		entry := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_lookUpClassMethod') or { panic(err) }
		if _ := runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', '_swift_lookUpClassMethod') { assert false }
		lm_suite(LmApi{false, entry, code, guard})
	}
	println('IOS-CLASS-METHOD: native C ABI and inherited override parity, borrowed readonly class/vtable descriptors, no method/accessor invocation or ARC/allocation, bounds/profile/ancestry/retirement rejection, eight readers and two drained runtime lifetimes')
}
