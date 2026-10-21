// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr

type StructInit = fn (u64, u64, u64, u64, u64)
type StructProbe = fn (u64, u64, u64, u64, u64, u64, &u64)
type StructCopy = fn (u64, u64, u64) u64
type StructDestroy = fn (u64, u64)
type StructTag = fn (u64, u32, u64) u32
type StructStore = fn (u64, u32, u32, u64)

struct StructField {
	size u64
	stride u64
	flags u32
	extra u32
}
struct StructInput {
	base u64
	page u64
	metadata u64
	witness u64
	types u64
	offsets u64
}
fn struct_write(address u64, value u64) { unsafe { *(&u64(address)) = value } }
fn struct_sentinel() {}
fn struct_input(fields []StructField) StructInput {
	page := u64(C.getpagesize())
	base := u64(C.mmap(unsafe { nil }, usize(page * 3), C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert base != ~u64(0)
	assert C.mprotect(voidptr(base + page), usize(page), C.PROT_READ | C.PROT_WRITE) == 0
	m := base + page + 8
	w := base + page * 2 - 88
	types := base + page + 2560
	struct_write(m - 8, w)
	struct_write(m, 0x200)
	struct_write(m + 8, 0x12345678)
	write32(m + 16 + u64(fields.len * 4), 0xcafef00d)
	write32(m + 20 + u64(fields.len * 4), 0xfeedface)
	for i in 0 .. 8 { struct_write(w + u64(i * 8), u64(unsafe { voidptr(struct_sentinel) })) }
	struct_write(w + 64, 0x9911)
	struct_write(w + 72, 0x9922)
	write32(w + 80, 0x400000)
	write32(w + 84, 0x9933)
	for i, f in fields {
		layout := base + page + 512 + u64(i * 24)
		struct_write(types + u64(i * 8), layout)
		struct_write(layout, f.size)
		struct_write(layout + 8, f.stride)
		write32(layout + 16, f.flags)
		write32(layout + 20, f.extra)
		write32(m + 16 + u64(i * 4), 0xffffffff)
	}
	return StructInput{base, page, m, w, types, m + 16}
}
fn struct_free(input StructInput) { assert C.munmap(voidptr(input.base), usize(input.page * 3)) == 0 }
fn struct_check(input StructInput, positions []u32, size u64, stride u64, flags u32, extra u32, native bool) {
	assert read64(input.metadata) == 0x200 && read64(input.metadata + 8) == 0x12345678
	assert read64(input.metadata - 8) == input.witness
	for i, position in positions { assert read32(input.offsets + u64(i * 4)) == position }
	assert read32(input.offsets + u64(positions.len * 4)) == 0xcafef00d
	assert read32(input.offsets + u64(positions.len * 4) + 4) == 0xfeedface
	assert read64(input.witness + 64) == size && read64(input.witness + 72) == stride
	mut actual_flags := read32(input.witness + 80)
	// Swift 6 additionally marks non-bitwise-takable layouts as non-bitwise-
	// borrowable. Compare the Swift 5 flags while checking that new trait.
	if native && actual_flags & 0x01000000 != 0 {
		assert flags & 0x100000 != 0
		actual_flags &= ~u32(0x01000000)
	}
	assert actual_flags == flags && read32(input.witness + 84) == extra, 'size=${size} flags=${actual_flags.hex()}/${flags.hex()} extra=${read32(input.witness + 84)}/${extra}'
}
fn struct_case(entry u64, probe StructProbe, fields []StructField, positions []u32, size u64, stride u64, flags u32, extra u32, native bool) {
	input := struct_input(fields)
	defer { struct_free(input) }
	mut preserved := [u64(0xcafe), 0, 0, 0xbeef]!
	probe(input.metadata, 0x100, u64(fields.len), input.types, input.offsets, entry, unsafe { &preserved[1] })
	assert preserved == [u64(0xcafe), 0x5020, 0x5021, 0xbeef]!
	struct_check(input, positions, size, stride, flags, extra, native)
	common := flags & 0x10000 == 0 && extra == 0 && size in [u64(1), 2, 4, 8]! && u64(flags & 255) == size - 1
	for slot in 0 .. 8 {
		replaced := if flags & 0x10000 == 0 { slot < 6 || common } else { flags & 0x100000 == 0 && slot == 4 }
		assert (read64(input.witness + u64(slot * 8)) != u64(unsafe { voidptr(struct_sentinel) })) == replaced
	}
	if !native && flags & 0x10000 == 0 {
		mut source := []u8{len: 64}
		mut destination := []u8{len: 64, init: u8(0xa5)}
		for i in 0 .. 64 { source[i] = u8(i + 1) }
		for slot in [0, 2, 3, 4, 5]! {
			C.memset(destination.data, 0xa5, 64)
			witness_copy := unsafe { StructCopy(voidptr(read64(input.witness + u64(slot * 8)))) }
			assert witness_copy(u64(destination.data) + 1, u64(source.data) + 1, input.metadata) == u64(destination.data) + 1
			for i in 0 .. 64 { assert destination[i] == if i > 0 && u64(i) <= size { source[i] } else { u8(0xa5) } }
		}
		unsafe { StructDestroy(voidptr(read64(input.witness + 8)))(u64(destination.data) + 1, input.metadata) }
		unsafe { source.free(); destination.free() }
	}
}
fn struct_matrix(entry u64, probe StructProbe, native bool) {
	struct_case(entry, probe, []StructField{}, []u32{}, 0, 1, 0, 0, native)
	for size in [u64(1), 2, 4, 8]! {
		struct_case(entry, probe, [StructField{size, size, u32(size - 1), 0}], [u32(0)], size, size, u32(size - 1), 0, native)
	}
	struct_case(entry, probe, [StructField{3, 4, 3, 0}, StructField{1, 1, 0, 0}], [u32(0), 3], 4, 4, 3, 0, native)
	struct_case(entry, probe, [StructField{1, 1, 0, 0}, StructField{8, 8, 7, 0}, StructField{2, 2, 1, 0}], [u32(0), 8, 16], 18, 24, 7, 0, native)
	struct_case(entry, probe, [StructField{17, 17, 0, 0}], [u32(0)], 17, 17, 0, 0, native)
	struct_case(entry, probe, [StructField{8, 8, 7, 4}, StructField{8, 8, 7, 7}, StructField{8, 8, 7, 7}], [u32(0), 8, 16], 24, 24, 7, 7, native)
	// Synthetic four-field shape matching the observed Date/Int64/BridgeObject call.
	struct_case(entry, probe, [StructField{16, 16, 7, 0}, StructField{8, 8, 7, 0}, StructField{8, 8, 7, 0}, StructField{8, 8, 0x10007, 0x7fffffff}], [u32(0), 16, 24, 32], 40, 40, 0x30007, 0x7fffffff, native)
	struct_case(entry, probe, [StructField{8, 8, 0x110007, 0}], [u32(0)], 8, 8, 0x130007, 0, native)
	struct_case(entry, probe, [StructField{1, 1, 0x280000, 9}], [u32(0)], 1, 1, 0, 9, native)
	mut many := []StructField{}
	mut positions := []u32{}
	for _ in 0 .. 64 { many << StructField{0, 1, 0, 0}; positions << u32(0) }
	struct_case(entry, probe, many, positions, 0, 1, 0, 0, native)
	unsafe { many.free(); positions.free() }
}
fn struct_scalar_enums(entry u64, native bool) {
	initialize := unsafe { StructInit(voidptr(entry)) }
	for size in [u64(1), 2, 4, 8]! {
		input := struct_input([StructField{size, size, u32(size - 1), 0}])
		initialize(input.metadata, 0x100, 1, input.types, input.offsets)
		// Native arm64e witness pointers carry PAC bits on this host.
		mask := if native { u64(0x0000ffffffffffff) } else { ~u64(0) }
		get := unsafe { StructTag(voidptr(read64(input.witness + 48) & mask)) }
		store := unsafe { StructStore(voidptr(read64(input.witness + 56) & mask)) }
		for cases in [u32(0), 1, 255, 256, 65535, 65536, 16777216, 0x7fffffff, 0xffffffff]! {
			width := swift_optional_extra_width(size, 0, cases)
			for tag in [u32(0), 1, cases / 2, cases]! {
				if tag > cases { continue }
				mut bytes := []u8{len: 32, init: u8(0xa5)}
				value := u64(bytes.data) + 1
				store(value, tag, cases, input.metadata)
				// The native UInt32 width calculation wraps at extreme counts.
				assert get(value, cases, input.metadata) == if width == 0 { u32(0) } else { tag }, 'native=${native} size=${size} cases=${cases} tag=${tag} width=${width}'
				assert bytes[0] == 0xa5
				for i in int(size + width + 1) .. 32 { assert bytes[i] == 0xa5 }
				if tag == 0 { for i in 1 .. int(size + 1) { assert bytes[i] == 0xa5 } }
				unsafe { bytes.free() }
			}
		}
		struct_free(input)
	}
}
fn struct_bad(metadata u64, algorithm u64, count u64, types u64, offsets u64) {
	if _ := swift_struct_initialize_checked(metadata, algorithm, count, types, offsets) { assert false, 'unsupported layout accepted' }
}
fn struct_invalid(guard u64) {
	input := struct_input([StructField{8, 8, 7, 0}])
	defer { struct_free(input) }
	m := input.metadata; w := input.witness; layout := read64(input.types)
	for flags in [u64(0), 1, 0x101, 0x200, ~u64(0)]! { struct_bad(guard, flags, 1, guard, guard) }
	struct_bad(guard, 0x100, 65, guard, guard)
	for metadata in [u64(0), 1, 7, 9, ~u64(7)]! { struct_bad(metadata, 0x100, 1, guard, guard) }
	for pointer in [u64(0), 1, ~u64(3)]! {
		struct_bad(m, 0x100, 1, pointer, input.offsets)
		struct_bad(m, 0x100, 1, input.types, pointer)
	}
	struct_write(m, 0x201); struct_bad(m, 0x100, 1, input.types, input.offsets); struct_write(m, 0x200)
	for pointer in [u64(0), 1, ~u64(7)]! {
		struct_write(m - 8, pointer); struct_bad(m, 0x100, 1, input.types, input.offsets)
		struct_write(m - 8, w); struct_write(input.types, pointer); struct_bad(m, 0x100, 1, input.types, input.offsets)
		struct_write(input.types, layout)
	}
	for f in [StructField{1048577, 1048584, 7, 0}, StructField{8, 0, 7, 0}, StructField{8, 7, 7, 0}, StructField{8, 9, 7, 0}, StructField{8, 8, 2, 0}, StructField{8, 8, 0x400007, 0}, StructField{8, 8, 0x800007, 0}, StructField{8, 8, 0x40000007, 0}, StructField{8, 8, 7, 0x80000000}, StructField{32, 32, 7, 0}, StructField{8, 16, 15, 0}]! {
		struct_write(layout, f.size); struct_write(layout + 8, f.stride); write32(layout + 16, f.flags); write32(layout + 20, f.extra)
		struct_bad(m, 0x100, 1, input.types, input.offsets)
	}
	struct_write(layout, 8); struct_write(layout + 8, 8); write32(layout + 16, 0x110007); write32(layout + 20, 0)
	for slot in 0 .. 8 {
		for callback in [u64(0), 1, ~u64(3)]! {
			struct_write(w + u64(slot * 8), callback); struct_bad(m, 0x100, 1, input.types, input.offsets)
			struct_write(w + u64(slot * 8), u64(unsafe { voidptr(struct_sentinel) }))
		}
	}
	assert read32(input.offsets) == 0xffffffff && read32(input.offsets + 4) == 0xcafef00d && read32(input.offsets + 8) == 0xfeedface
	assert read64(w + 64) == 0x9911 && read64(w + 72) == 0x9922 && read32(w + 80) == 0x400000 && read32(w + 84) == 0x9933
	ios_runtime.swift_generic_metadata_retired = true
	struct_bad(guard, 0x100, 1, guard, guard)
	ios_runtime.swift_generic_metadata_retired = false
}
fn struct_repeat(entry u64, guard u64) {
	input := struct_input([StructField{8, 8, 7, 0}])
	initialize := unsafe { StructInit(voidptr(entry)) }
	page := u64(C.mmap(unsafe { nil }, usize(input.page), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert page != ~u64(0)
	assert C.mprotect(voidptr(page), usize(input.page), C.PROT_READ) == 0
	for _ in 0 .. 512 { initialize(input.metadata, 0x100, 1, input.types, page) }
	initialize(input.metadata, 0x100, 0, guard, guard)
	assert read64(input.witness + 64) == 0 && read64(input.witness + 72) == 1
	// Borrowed image storage can become inaccessible before shutdown: there
	// is no deferred callback, owned table or registry entry to dereference.
	assert C.mprotect(voidptr(input.base + input.page), usize(input.page), C.PROT_NONE) == 0
	objc_stop()
	struct_bad(guard, 0x100, 1, guard, guard)
	assert C.munmap(voidptr(page), usize(input.page)) == 0
	struct_free(input)
}
fn test_swift_struct_metadata() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	guard := u64(C.mmap(unsafe { nil }, page, C.PROT_NONE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != ~u64(0) && guard != ~u64(0)
	defer { assert C.munmap(voidptr(code), page) == 0 && C.munmap(voidptr(guard), page) == 0 }
	// C ABI x0..x4 arguments, void result, and preserved Swift context registers.
	for i, op in [u32(0xa9bc7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0603f3, 0xaa0503f0, u32(0xd2800000 | (0x5020 << 5) | 20), u32(0xd2800000 | (0x5021 << 5) | 21), 0xd63f0200, 0xa9005674, 0xa9425bf5, 0xa94153f3, 0xa8c47bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	C.__builtin___clear_cache(voidptr(code), voidptr(code + 64))
	assert C.mprotect(voidptr(code), page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { StructProbe(voidptr(code)) }
	$if macos {
		core := C.dlopen(c'/usr/lib/swift/libswiftCore.dylib', 2)
		entry := u64(C.dlsym(core, c'swift_initStructMetadata'))
		assert entry != 0
		struct_matrix(entry, probe, true)
		struct_scalar_enums(entry, true)
		println('NATIVE-STRUCT-METADATA: five-argument C ABI, void result, preserved x20/x21; field size/tail padding, alignment, stride, inline/POD/bitwise traits, maximum extra inhabitants, callback installation and scalar enum round trips')
	}
	struct_bad(guard, 0x100, 1, guard, guard)
	for _ in 0 .. 2 {
		objc_start()
		entry := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '_swift_initStructMetadata') or { panic(err) }
		struct_matrix(entry, probe, false)
		struct_scalar_enums(entry, false)
		struct_invalid(guard)
		if _ := runtime_symbol('/usr/lib/swift/libswiftFoundation.dylib', '_swift_initStructMetadata') { assert false }
		if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', '__swift_initStructMetadata') { assert false }
		assert ios_runtime.swift_generic_metadata_count == 0 && ios_runtime.swift_heap.len == 0 && ios_runtime.live == 0
		struct_repeat(entry, guard)
	}
	println('IOS-STRUCT-METADATA: mutable Swift 5 struct layout, UInt32 offsets, inherited enum/destruction witnesses, bounded inline POD copies and non-POD bitwise take, fail-before-write validation, guard pages, read-only unchanged offsets, zero/64 fields, 512 repeats and two retired borrowed-storage lifetimes')
}
