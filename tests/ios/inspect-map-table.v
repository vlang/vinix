// SPDX-License-Identifier: GPL-2.0-or-later
// Measure object-map nil handling, equality, and weak ownership on Apple.
module main
#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_storeWeak(&u64, voidptr) voidptr
type Send = fn (u64, voidptr, u64, u64, u64) u64
fn msg(object u64, selector &char, a u64, b u64, c u64) u64 {
	return unsafe { Send(C.dlsym(voidptr(i64(-2)), c'objc_msgSend'))(object, C.sel_registerName(selector), a, b, c) }
}
fn main() {
	pool := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0, 0)
	cls := u64(C.objc_getClass(c'NSMapTable'))
	for factory in [c'new', c'strongToStrongObjectsMapTable', c'weakToStrongObjectsMapTable', c'strongToWeakObjectsMapTable', c'weakToWeakObjectsMapTable']! {
		inner := msg(u64(C.objc_getClass(c'NSAutoreleasePool')), c'new', 0, 0, 0)
		table := msg(cls, factory, 0, 0, 0)
		if factory != c'new' { msg(table, c'retain', 0, 0, 0) }
		key := msg(u64(C.objc_getClass(c'NSObject')), c'new', 0, 0, 0)
		value := msg(u64(C.objc_getClass(c'NSObject')), c'new', 0, 0, 0)
		msg(table, c'setObject:forKey:', value, key, 0)
		assert msg(table, c'objectForKey:', key, 0, 0) == value
		msg(table, c'setObject:forKey:', value, 0, 0)
		println('${unsafe { factory.vstring() }} nil-key-count=${msg(table, c'count', 0, 0, 0)}')
		msg(table, c'setObject:forKey:', 0, key, 0)
		println('nil-value-count=${msg(table, c'count', 0, 0, 0)} lookup=${msg(table, c'objectForKey:', key, 0, 0) == value}')
		msg(inner, c'drain', 0, 0, 0)
		// Factories return autoreleased tables; own them across pool drains.
		msg(table, c'removeAllObjects', 0, 0, 0)
		msg(value, c'release', 0, 0, 0)
		msg(key, c'release', 0, 0, 0)
		fresh_key := msg(u64(C.objc_getClass(c'NSObject')), c'new', 0, 0, 0)
		fresh_value := msg(u64(C.objc_getClass(c'NSObject')), c'new', 0, 0, 0)
		msg(table, c'setObject:forKey:', fresh_value, fresh_key, 0)
		msg(fresh_value, c'release', 0, 0, 0)
		println('released-value-count=${msg(table, c'count', 0, 0, 0)} lookup=${msg(table, c'objectForKey:', fresh_key, 0, 0) != 0}')
		msg(fresh_key, c'release', 0, 0, 0)
		println('released-key-count=${msg(table, c'count', 0, 0, 0)}')
		msg(table, c'removeAllObjects', 0, 0, 0)
		msg(table, c'release', 0, 0, 0)
	}
	table := msg(cls, c'new', 0, 0, 0)
	mut keys := [2]u64{}
	mut slots := [2]u64{}
	for i in 0 .. 2 {
		keys[i] = msg(msg(u64(C.objc_getClass(c'NSMutableString')), c'alloc', 0, 0, 0), c'initWithUTF8String:', u64(c'equal'), 0, 0)
		C.objc_storeWeak(unsafe { &slots[i] }, voidptr(keys[i]))
		msg(table, c'setObject:forKey:', table, keys[i], 0)
	}
	for key in keys { msg(key, c'release', 0, 0, 0) }
	println('equal-key-ownership first=${slots[0] != 0} replacement=${slots[1] != 0}')
	msg(table, c'removeAllObjects', 0, 0, 0)
	for i in 0 .. 2 { C.objc_storeWeak(unsafe { &slots[i] }, unsafe { nil }) }
	msg(table, c'release', 0, 0, 0)
	msg(pool, c'drain', 0, 0, 0)
}
