// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Payments and requests have metadata only. The queue has no App Store provider.
struct StorekitObserver {
mut:
	object u64 // Stable zeroing-weak slot; registration does not own the observer.
}

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
	if name != 'SKPaymentQueue' { return none }
	if !meta {
		return match selector {
			'addTransactionObserver:', 'removeTransactionObserver:' { 'v24@0:8@16' }
			'transactionObservers', 'transactions' { '@16@0:8' }
			else { none }
		}
	}
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
	records := ios_runtime.storekit_observers
	ios_runtime.storekit_observers = []&StorekitObserver{}
	ios_runtime.storekit_observers.flags |= .noslices
	C.ios_objc_initialize_unlock()
	for record in records {
		objc_destroy_weak(unsafe { &record.object })
		unsafe { free(record) }
	}
	unsafe { records.free() }
	objc_release(object)
}

// Caller holds the recursive runtime lock, also used by zeroing-weak teardown.
fn storekit_observers_remove(observer u64) {
	for i := ios_runtime.storekit_observers.len - 1; i >= 0; i-- {
		record := ios_runtime.storekit_observers[i]
		if record.object != 0 && record.object != observer { continue }
		ios_runtime.storekit_observers.delete(i)
		objc_destroy_weak(unsafe { &record.object })
		unsafe { free(record) }
	}
}

fn storekit_observers_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if selector !in ['addTransactionObserver:', 'removeTransactionObserver:', 'transactionObservers', 'transactions']!
		|| object in ios_runtime.classes || read64(object) != ios_runtime.names['SKPaymentQueue'] { return false }
	observer := frame.x[2]
	if selector in ['addTransactionObserver:', 'removeTransactionObserver:']! {
		if observer == 0 { panic('iOS: payment queue requires a non-nil observer') }
		if selector == 'addTransactionObserver:' && !objc_responds(observer, c'paymentQueue:updatedTransactions:') {
			panic('iOS: payment observer requires paymentQueue:updatedTransactions:')
		}
	}
	// Allocation/initialization may reenter; do it before locking the registry.
	array := if selector in ['transactionObservers', 'transactions']! { objc_allocate(ios_runtime.names['NSArray']) } else { u64(0) }
	C.ios_objc_initialize_lock()
	storekit_queue_storage(object)
	if ios_runtime.storekit_queue_retired || object != ios_runtime.storekit_queue {
		panic('iOS: payment queue cache is retired')
	}
	storekit_observers_remove(if selector == 'removeTransactionObserver:' { observer } else { u64(0) })
	if selector == 'addTransactionObserver:' {
		mut found := false
		for record in ios_runtime.storekit_observers { if record.object == observer { found = true; break } }
		if !found {
			record := &StorekitObserver{}
			objc_store_weak(unsafe { &record.object }, observer)
			ios_runtime.storekit_observers << record
		}
	} else if selector == 'transactionObservers' {
		mut target := obj_header(array)
		for record in ios_runtime.storekit_observers {
			value := objc_load_weak(unsafe { &record.object })
			// The immutable snapshot owns the load's +1, independently of registration.
			if value != 0 { target.items << value }
		}
	}
	// With no payment provider there are no unfinished transactions or callbacks.
	C.ios_objc_initialize_unlock()
	if array != 0 { frame.x[0] = objc_autorelease(array) } else { frame.x[0] = 0 }
	return true
}

fn storekit_queue_dispatch(object u64, selector string, mut frame RegisterFrame) bool {
	if storekit_observers_dispatch(object, selector, mut frame) { return true }
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
