// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import macho
import crypto.sha256
$if macos {
	#include <objc/runtime.h>
}
fn C.objc_getClass(&char) voidptr
fn C.objc_allocateClassPair(voidptr, &char, usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.objc_disposeClassPair(voidptr)
fn C.sel_registerName(&char) voidptr
fn C.class_addMethod(voidptr, voidptr, voidptr, &char) bool
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char

fn encoding_eos_type() string {
	input := os.getenv('VINIX_IOS_CONSTANT_DICT_IMAGE')
	path := if input != '' { input } else { os.getwd() + '/build/ios/fortnite/local/Payload/FortniteClient-IOS-Shipping.app/Frameworks/EOSSDK.framework/EOSSDK' }
	data := os.read_bytes(path) or { panic(err) }
	defer { unsafe { data.free() } }
	assert sha256.sum(data).hex() == 'f3269c98beef0365b3dbd1bc1a3baeac54b39b744086ec56c88aa1e5ef369d22'
	offset := 0xcd3406
	assert data[offset + 1605] == 0
	assert sha256.sum(data[offset..offset + 1605]).hex() == 'fe0de4fb3988b532bd78a09097a8779173873b4677876b23363a8ffe84e8876e'
	return unsafe { tos(&data[offset], 1605) }.clone()
}
fn encoding_unused_imp(owner u64, _selector &char) u64 { return owner }
fn encoding_native(text string) {
	$if macos {
		cls := C.objc_allocateClassPair(C.objc_getClass(c'NSObject'), c'VinixNativeLongEncoding', 0)
		assert cls != unsafe { nil }
		selector := C.sel_registerName(c'epicLongTypeEncoding')
		assert C.class_addMethod(cls, selector, unsafe { voidptr(encoding_unused_imp) }, text.str)
		C.objc_registerClassPair(cls)
		method := C.class_getInstanceMethod(cls, selector); assert method != unsafe { nil }
		stored := C.method_getTypeEncoding(method)
		assert unsafe { stored.vstring() } == text && C.strlen(stored) == 1605
		C.objc_disposeClassPair(cls)
		println('IOS-ENCODING-NATIVE: installed ObjC runtime accepts and reflects the exact 1605-byte EOSSDK method encoding; no implementation invoked')
	}
}
fn encoding_model(base u64, page u64, data_size u64, file_size u64) ObjMetadata {
	return ObjMetadata{ base: base, layout: macho.Layout{base: 0x1000, size: page + data_size},
		image: macho.Image{ segments: [macho.Segment{name: '__TEXT', address: 0x1000, size: page, filesize: page, prot: 5},
			macho.Segment{name: '__DATA_CONST', address: 0x1000 + page, size: data_size, filesize: file_size, prot: 1}] } }
}
fn encoding_method_list(base u64, list u64, selector u64, types u64, format int) {
	write32(list, if format == 0 { u32(24) } else if format == 1 { u32(0xc000000c) } else { u32(0x8000000c) })
	write32(list + 4, 1)
	entry := list + 8
	if format == 0 {
		unsafe { *(&u64(entry)) = selector; *(&u64(entry + 8)) = types; *(&u64(entry + 16)) = base }
	} else {
		cell := list + 64
		unsafe { *(&u64(cell)) = selector }
		name := if format == 1 { selector } else { cell }
		write32(entry, u32(i32(i64(name) - i64(entry))))
		write32(entry + 4, u32(i32(i64(types) - i64(entry + 4))))
		write32(entry + 8, u32(i32(i64(base) - i64(entry + 8))))
	}
}
fn encoding_case(text string) {
	page := u64(C.getpagesize()); data_size := ((65536 + page - 1) / page + 2) * page
	total := page * 3 + data_size
	region := u64(C.mmap(unsafe { nil }, usize(total), C.PROT_READ | C.PROT_WRITE, C.MAP_PRIVATE | C.MAP_ANONYMOUS, -1, 0))
	assert region != u64(-1)
	base := region + page; data := base + page
	assert C.mprotect(unsafe { voidptr(region) }, usize(page), C.PROT_NONE) == 0
	assert C.mprotect(unsafe { voidptr(data + data_size) }, usize(page), C.PROT_NONE) == 0
	write32(base, 0xd65f03c0)
	assert C.mprotect(unsafe { voidptr(base) }, usize(page), C.PROT_READ | C.PROT_EXEC) == 0
	model := encoding_model(base, page, data_size, data_size)
	address := data + 256
	for length in [0, 1, 1023, 1024, 1605, 65535]! {
		C.memset(unsafe { voidptr(address) }, 0x71, usize(length))
		unsafe { *(&u8(address + u64(length))) = 0 }
		assert C.mprotect(unsafe { voidptr(data) }, usize(data_size), C.PROT_READ) == 0
		value := model.type_at(address) or { panic(err) }
		assert value.len == length && (length == 0 || u64(value.str) == address)
		if length <= 1023 { assert (model.string_at(address) or { panic(err) }).len == length }
		else { if _ := model.string_at(address) { assert false, 'names retain their existing bound' } }
		assert C.mprotect(unsafe { voidptr(data) }, usize(data_size), C.PROT_READ | C.PROT_WRITE) == 0
	}
	C.memset(unsafe { voidptr(address) }, 0x71, 65536)
	unsafe { *(&u8(address + 65536)) = 0 }
	if _ := model.type_at(address) { assert false, 'oversized type encoding must reject' }
	ignored := model.type_at(address) or {
		assert err.code() == 0 && err.msg() == 'iOS: Objective-C type encoding exceeds 65535 bytes'
		''
	}
	assert ignored == ''
	for invalid in [region, data + data_size, base + page + data_size + 1]! {
		if _ := model.type_at(invalid) { assert false, 'range checked before access' }
	}
	// The terminator itself must be inside file-backed bytes, not only the mmap.
	C.memcpy(unsafe { voidptr(address) }, text.str, usize(text.len))
	unsafe { *(&u8(address + u64(text.len))) = 0 }
	truncated := encoding_model(base, page, data_size, 256 + u64(text.len))
	if _ := truncated.type_at(address) { assert false, 'unterminated file-backed encoding must reject' }
	boundary := data + data_size - u64(text.len) - 1
	C.memcpy(unsafe { voidptr(boundary) }, text.str, usize(text.len))
	unsafe { *(&u8(data + data_size - 1)) = 0 }
	assert (model.type_at(boundary) or { panic(err) }) == text
	name := data + 128; C.memcpy(unsafe { voidptr(name) }, c'epicLongTypeEncoding', 21)
	list := data + 32
	cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixImageLongEncoding', 0)
	assert cls != 0; objc_register_class(cls)
	for format in 0 .. 3 {
		encoding_method_list(base, list, name, address, format)
		assert C.mprotect(unsafe { voidptr(data) }, usize(data_size), C.PROT_READ) == 0
		methods := model.methods(list) or { panic(err) }
		assert methods.len == 1 && methods['epicLongTypeEncoding'].imp == base && methods['epicLongTypeEncoding'].types == text
		if format == 0 {
			record := objc_record_method(cls, unsafe { &char(name) }, base, unsafe { &char(methods['epicLongTypeEncoding'].types.str) }, false)
			assert record.types == text && u64(record.types.str) != address
		}
		unsafe { methods.free() }
		assert C.mprotect(unsafe { voidptr(data) }, usize(data_size), C.PROT_READ | C.PROT_WRITE) == 0
	}
	assert C.munmap(unsafe { voidptr(region) }, usize(total)) == 0
	method := objc_instance_method(cls, objc_selector(c'epicLongTypeEncoding'))
	assert ctext(u64(objc_method_types(method))) == text
	objc_dispose_class(cls)
}
fn test_objc_type_encodings() {
	text := encoding_eos_type()
	defer { unsafe { text.free() } }
	encoding_native(text)
	for _ in 0 .. 2 {
		objc_start(); classes := ios_runtime.classes.len
		encoding_case(text)
		assert ios_runtime.classes.len == classes && ios_runtime.live == 0
		objc_stop(); assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-ENCODING: exact EOS method bytes, 65535-byte bounded borrowed types, unchanged name limits, protected/truncated storage, three method-list formats, owned reflection after unmapping and two drained lifetimes')
}
