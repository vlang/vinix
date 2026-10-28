// SPDX-License-Identifier: GPL-2.0-or-later
module main

#flag -framework Foundation
#include <objc/runtime.h>
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.object_getClass(voidptr) voidptr
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_isMetaClass(voidptr) bool
fn C.dlopen(&char, int) voidptr
fn C.class_getClassMethod(voidptr, voidptr) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.sel_registerName(&char) voidptr
fn C.method_getTypeEncoding(voidptr) &char

fn main() {
	assert C.dlopen(c'/System/Library/Frameworks/StoreKit.framework/StoreKit', 2) != unsafe { nil }
	names := ['SKPaymentQueue', 'SKPayment', 'SKMutablePayment', 'SKRequest', 'SKReceiptRefreshRequest', 'SKProductsRequest']!
	parents := ['NSObject', 'NSObject', 'SKPayment', 'NSObject', 'SKRequest', 'SKRequest']!
	for i, name in names {
		cls := C.objc_getClass(name.str)
		parent := C.objc_getClass(parents[i].str)
		assert cls != unsafe { nil } && parent != unsafe { nil } && !C.class_isMetaClass(cls)
		meta := C.object_getClass(cls)
		assert meta != unsafe { nil } && C.class_isMetaClass(meta)
		assert C.class_getSuperclass(cls) == parent
		assert C.class_getSuperclass(meta) == C.object_getClass(parent)
		println('${name} PARENT ${parents[i]} METAPARENT ${parents[i]}')
	}
	queue := C.objc_getClass(c'SKPaymentQueue')
	for selector in ['defaultQueue', 'canMakePayments']! {
		sel := C.sel_registerName(selector.str)
		method := C.class_getClassMethod(queue, sel)
		assert method != unsafe { nil } && C.class_getInstanceMethod(queue, sel) == unsafe { nil }
		types := unsafe { cstring_to_vstring(C.method_getTypeEncoding(method)) }
		assert types == if selector == 'defaultQueue' { '@16@0:8' } else { 'B16@0:8' }
		println('SKPaymentQueue +' + selector + ' ' + types)
	}
	for selector in ['addTransactionObserver:', 'removeTransactionObserver:', 'transactionObservers', 'transactions']! {
		sel := C.sel_registerName(selector.str)
		method := C.class_getInstanceMethod(queue, sel)
		assert method != unsafe { nil } && C.class_getClassMethod(queue, sel) == unsafe { nil }
		types := unsafe { cstring_to_vstring(C.method_getTypeEncoding(method)) }
		assert types == if selector.ends_with(':') { 'v24@0:8@16' } else { '@16@0:8' }
		println('SKPaymentQueue -' + selector + ' ' + types)
	}
	println('IOS-STOREKIT-PURCHASE-INSPECT: PASS (metadata only; no purchases or requests)')
}
