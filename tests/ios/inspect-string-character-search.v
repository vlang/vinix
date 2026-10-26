// SPDX-License-Identifier: GPL-2.0-or-later
// Apple Foundation oracle. Run on ARM64 macOS; keep output outside Git.
module main

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char

struct SearchRange { location u64 length u64 }
type SearchSend = fn (u64, u64, u64, u64) u64
type SearchBytes = fn (u64, u64, u64, u64, u64) u64
type SearchResult = fn (u64, u64, u64) SearchRange

fn main() {
	entry := u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))
	assert entry != 0
	send := unsafe { SearchSend(voidptr(entry)) }
	bytes := unsafe { SearchBytes(voidptr(entry)) }
	search := unsafe { SearchResult(voidptr(entry)) }
	pool := send(u64(C.objc_getClass(c'NSAutoreleasePool')), u64(C.sel_registerName(c'new')), 0, 0)
	cls := u64(C.objc_getClass(c'NSString'))
	sel := u64(C.sel_registerName(c'rangeOfCharacterFromSet:'))
	method := C.class_getInstanceMethod(voidptr(cls), voidptr(sel))
	println('TYPES: ' + unsafe { C.method_getTypeEncoding(method).vstring() })
	for text in ['', 'abc', 'A\x00π', 'a🎮π', '😀🎮π', 'é', '🎮🎮', '\U0010ffff']! {
		object := send(cls, u64(C.sel_registerName(c'alloc')), 0, 0)
		string_object := bytes(object, u64(C.sel_registerName(c'initWithBytes:length:encoding:')), u64(text.str), u64(text.len), 4)
		for point in [u32(0), 0x61, 0x3c0, 0x301, 0xd83c, 0xdfae, 0xd83d, 0xde00, 0x1f3ae, 0x1f600, 0x10ffff]! {
			set := send(u64(C.objc_getClass(c'NSCharacterSet')), u64(C.sel_registerName(c'characterSetWithRange:')), point, 1)
			result := search(string_object, sel, set)
			println('SEARCH: ${text.bytes().hex()} U+${point.hex()} ${result.location} ${result.length}')
		}
		send(string_object, u64(C.sel_registerName(c'release')), 0, 0)
	}
	send(pool, u64(C.sel_registerName(c'drain')), 0, 0)
}
