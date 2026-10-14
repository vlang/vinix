// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char, i32) voidptr
fn C.dlsym(voidptr, &char) voidptr
type ObjcBoolConvert = fn (u64) u64
type ObjcBoolProbe = fn (u64, u64, &u64)

fn objc_bool_case(convert ObjcBoolConvert, probe ObjcBoolProbe) {
	// Valid Boolean values are 0/1. Sweep ignored register bits without treating
	// malformed byte patterns as additional valid values of Swift Bool.
	for upper in 0 .. 256 {
		for bit in [u64(0), 1]! {
			value := u64(upper) << 8 | u64(upper ^ 0xff) << 56 | bit
			assert convert(value) == bit
			mut output := [u64(0x1234), 0, 0, 0, 0x5678]!
			probe(value, u64(unsafe { voidptr(convert) }), unsafe { &output[1] })
			assert output[0] == 0x1234 && output[4] == 0x5678
			assert output[1] == bit && output[2] == 0x5020 && output[3] == 0x5021
			assert convert(convert(value)) == bit
		}
	}
}

fn objc_bool_native(probe ObjcBoolProbe) {
	$if macos {
		library := C.dlopen(c'/usr/lib/swift/libswiftObjectiveC.dylib', C.RTLD_NOW)
		assert library != unsafe { nil }
		for name in ['$s10ObjectiveC22_convertBoolToObjCBoolyAA0eF0VSbF',
			'$s10ObjectiveC22_convertObjCBoolToBoolySbAA0cD0VF']! {
			address := C.dlsym(library, name.str)
			assert address != unsafe { nil }
			objc_bool_case(unsafe { ObjcBoolConvert(address) }, probe)
		}
		println('IOS-SWIFT-OBJC-BOOL-NATIVE: both installed ARM64 Mac free scalar entries accept valid 0/1 with ignored upper register bits, return canonical 0/1 and preserve x20/x21 and guarded outputs; this native comparison does not claim Catalyst signed-byte semantics')
	}
}

fn objc_bool_suite(probe ObjcBoolProbe) {
	for name in ['_$s10ObjectiveC22_convertBoolToObjCBoolyAA0eF0VSbF',
		'_$s10ObjectiveC22_convertObjCBoolToBoolySbAA0cD0VF']! {
		address := runtime_symbol('/usr/lib/swift/libswiftObjectiveC.dylib', name) or { panic(err) }
		objc_bool_case(unsafe { ObjcBoolConvert(voidptr(address)) }, probe)
		if _ := runtime_symbol('/usr/lib/swift/libswiftCore.dylib', name) { assert false }
		if _ := runtime_symbol('/usr/lib/swift/libswiftObjectiveC.dylib', name[1..]) { assert false }
	}
	for name in ['_$s10ObjectiveC8ObjCBoolVSQAAMc', '_$sSo8NSObjectCs7CVarArg10ObjectiveCMc', '_swift_once', '_objc_msgSend']! {
		if _ := runtime_symbol('/usr/lib/swift/libswiftObjectiveC.dylib', name) { assert false }
	}
}

fn test_swift_objc_bool() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil }, page, C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert code != u64(-1)
	// Save caller registers, set Swift context/error sentinels, call x1 with
	// scalar x0, then write result/x20/x21 to the guarded output supplied in x2.
	for i, op in [u32(0xa9bd7bfd), 0xa90153f3, 0xa9025bf5, 0xaa0203f3, 0xaa0103f0,
		0xd28a0414, 0xd28a0435, 0xd63f0200, 0xa9005260, 0xf9000a75,
		0xa94153f3, 0xa9425bf5, 0xa8c37bfd, 0xd65f03c0]! { write32(code + u64(i * 4), op) }
	C.__builtin___clear_cache(unsafe { voidptr(code) }, unsafe { voidptr(code + 56) })
	assert C.mprotect(unsafe { voidptr(code) }, page, C.PROT_READ | C.PROT_EXEC) == 0
	probe := unsafe { ObjcBoolProbe(voidptr(code)) }
	objc_bool_native(probe)
	objc_bool_suite(probe)
	for _ in 0 .. 2 {
		objc_start()
		objc_bool_suite(probe)
		assert ios_runtime.live == 0 && ios_runtime.swift_heap.len == 0
		assert ios_runtime.swift_objc_metadata.len == 0 && ios_runtime.swift_error_arena == 0
		objc_stop()
		objc_bool_suite(probe)
	}
	assert C.munmap(unsafe { voidptr(code) }, page) == 0
	println('IOS-SWIFT-OBJC-BOOL: two scoped conversions, canonical 0/1, ignored upper bits, guarded raw calls preserving x20/x21, round trips, unsupported overlay and wrong-library rejection, before/during/after two runtime cycles with no owner or metadata arena')
}
