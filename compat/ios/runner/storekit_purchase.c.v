// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Payments and requests have metadata only. The queue factory is defined below.
fn storekit_purchase_name(name string) bool {
	return name in ['SKPaymentQueue', 'SKPayment', 'SKMutablePayment', 'SKRequest',
		'SKReceiptRefreshRequest', 'SKProductsRequest']!
}

fn storekit_purchase_family(cls u64) bool {
	mut current := cls
	for _ in 0 .. 128 {
		info := ios_runtime.classes[current] or { return false }
		if storekit_purchase_name(info.name) { return true }
		current = info.parent
		if current == 0 { return false }
	}
	panic('iOS: cyclic StoreKit purchase superclass chain')
}

fn storekit_purchase_unsupported(selector string) bool {
	return selector !in ['class', 'superclass', 'self', 'isKindOfClass:',
		'respondsToSelector:', 'conformsToProtocol:']!
}

fn storekit_purchase_require_storage(cls u64) {
	storekit_purchase_require_operation(cls, 'allocation/storage')
}

fn storekit_purchase_install(cls u64, caller_storage bool) {
	if cls == ios_runtime.names['SKPaymentQueue'] && !caller_storage { return }
	storekit_purchase_require_storage(cls)
}

fn storekit_queue_types(name string, meta bool, selector string) ?string {
	if name != 'SKPaymentQueue' || !meta { return none }
	return match selector {
		'defaultQueue' { '@16@0:8' }
		'canMakePayments' { 'B16@0:8' }
		else { none }
	}
}

fn storekit_queue_allows(name string, meta bool, selector string) bool {
	if name != 'SKPaymentQueue' { return false }
	if storekit_queue_types(name, meta, selector) != none { return true }
	if selector == 'methodSignatureForSelector:' { return true }
	return !meta && selector in ['retain', 'release', 'autorelease']!
}

fn storekit_queue_storage(object u64) {
	header := obj_header(object)
	if header.allocation_cls != ios_runtime.names['SKPaymentQueue'] || header.caller_storage
		|| header.native_size != 24 || header.cls != header.allocation_cls || read64(object) != header.cls
		|| header.releasing || header.destroying || header.destroyed
		|| C.ios_ref_change(unsafe { &header.refs }, 0) <= 0 {
		panic('iOS: payment queue requires live built-in storage')
	}
}

fn storekit_queue_default() u64 {
	cls := ios_runtime.names['SKPaymentQueue']
	// +initialize may run caller code, so it precedes the cache lock.
	objc_initialize(cls)
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if ios_runtime.storekit_queue_retired { panic('iOS: payment queue cache is retired') }
	if ios_runtime.storekit_queue == 0 {
		object := u64(C.calloc(1, 24))
		if object == 0 { panic('iOS: cannot allocate payment queue') }
		objc_install_storage(cls, object, false)
		ios_runtime.storekit_queue = object
	}
	object := ios_runtime.storekit_queue
	storekit_queue_storage(object)
	return object // Borrowed; the cache owns the initial reference.
}

fn storekit_queue_retire(object u64) {
	C.ios_objc_initialize_lock()
	defer { C.ios_objc_initialize_unlock() }
	if object != 0 && object == ios_runtime.storekit_queue {
		panic('iOS: destroying cached payment queue storage')
	}
}

fn storekit_queue_stop() {
	C.ios_objc_initialize_lock()
	ios_runtime.storekit_queue_retired = true
	object := ios_runtime.storekit_queue
	ios_runtime.storekit_queue = 0
	C.ios_objc_initialize_unlock()
	objc_release(object)
}

fn storekit_queue_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if object !in ios_runtime.classes || selector !in ['defaultQueue', 'canMakePayments']! { return false }
	mut cls := object
	for _ in 0 .. 128 {
		if cls == 0 { return false }
		if cls == ios_runtime.names['SKPaymentQueue'] {
			// Custom allocation/initialization and subclass factories remain unsupported.
			if object != cls { storekit_purchase_require_operation(object, selector) }
			frame.x[0] = if selector == 'defaultQueue' { storekit_queue_default() } else { u64(0) }
			return true
		}
		cls = objc_class_parent(cls)
	}
	panic('iOS: cyclic payment queue superclass chain')
}

fn storekit_purchase_require_operation(cls u64, selector string) {
	if storekit_purchase_family(cls) {
		info := ios_runtime.classes[cls] or { panic('iOS: missing StoreKit receiver class') }
		panic('iOS: StoreKit payment and request construction or operations are not implemented: '
			+ info.name + ' ' + selector)
	}
}

fn storekit_purchase_symbol(symbol string) ?u64 {
	for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
		if !symbol.starts_with(prefix) { continue }
		name := symbol[prefix.len..]
		if !storekit_purchase_name(name) { return none }
		cls := ios_runtime.names[name] or { return none }
		return if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
	}
	return none
}
