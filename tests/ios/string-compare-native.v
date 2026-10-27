// SPDX-License-Identifier: GPL-2.0-or-later
// Inspect the installed Foundation contract without abstract-class IMP calls.
module main

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.dlsym(voidptr, &char) voidptr
type Send = fn (u64, u64, u64, u64, u64) u64
struct Pair { left string right string }

fn main() {
	send := Send(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))
	cls := u64(C.objc_getClass(c'NSString'))
	compare := u64(C.sel_registerName(c'compare:'))
	method := C.class_getInstanceMethod(voidptr(cls), voidptr(compare))
	assert method != unsafe { nil }
	println('Encoding: ' + unsafe { C.method_getTypeEncoding(method).vstring() })
	pool_cls := u64(C.objc_getClass(c'NSAutoreleasePool'))
	pool := send(pool_cls, u64(C.sel_registerName(c'new')), 0, 0, 0)
	for pair in [Pair{'', ''}, Pair{'a', 'b'}, Pair{'A', 'a'}, Pair{'10', '2'},
		Pair{'é', 'e\u0301'}, Pair{'é', 'f'}, Pair{'é', 'e'}, Pair{'é', 'e\u0302'},
		Pair{'e\u0301', 'f'}, Pair{'e\u0301x', 'éy'}, Pair{'é', 'e\u0301x'},
		Pair{'Å', 'Å'}, Pair{'각', '각'}, Pair{'각', '각'}, Pair{'ﬁ', 'fi'},
		Pair{'😀', '\ue000'}, Pair{'a\x00b', 'a\x00c'}, Pair{'A\u0315\u0300', 'À\u0315'},
		Pair{'\u0301\u0327A', '\u0327\u0301A'}, Pair{'Ａ', 'A'},
		Pair{'\U0001d15e', '\U0001d157\U0001d165'},
		Pair{'x\U0001d15e', 'x\U0001d157\U0001d165'},
		Pair{'\U0002f800', '丽'}, Pair{'豈', '豈'}, Pair{'\u0344', '\u0308\u0301'},
		Pair{'\U0001d15f', '\U0001d158\U0001d165'},
		Pair{'é😀', 'e\u0301😀'}, Pair{'\U0001109a', '\U00011099\U000110ba'}] {
		mut objects := [2]u64{}
		for i, text in [pair.left, pair.right] {
			allocated := send(cls, u64(C.sel_registerName(c'alloc')), 0, 0, 0)
			objects[i] = send(allocated, u64(C.sel_registerName(c'initWithBytes:length:encoding:')), u64(text.str), u64(text.len), 4)
			assert objects[i] != 0
		}
		forward := i64(send(objects[0], compare, objects[1], 0, 0))
		reverse := i64(send(objects[1], compare, objects[0], 0, 0))
		println(pair.left.bytes().hex() + ' / ' + pair.right.bytes().hex() + ' = ' + forward.str() + ', reverse=' + reverse.str())
		assert forward == -reverse && forward >= -1 && forward <= 1
		for object in objects { send(object, u64(C.sel_registerName(c'release')), 0, 0, 0) }
	}
	send(pool, u64(C.sel_registerName(c'drain')), 0, 0, 0)
}
