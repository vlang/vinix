// SPDX-License-Identifier: GPL-2.0-or-later
module main

type StorekitPurchaseSend = fn (u64, u64, u64, u64) u64

fn storekit_purchase_msg(object u64, selector &char, a u64, b u64) u64 {
	return unsafe { StorekitPurchaseSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), a, b) }
}

fn test_storekit_purchase_descriptors() {
	names := ['SKPaymentQueue', 'SKPayment', 'SKMutablePayment', 'SKRequest',
		'SKReceiptRefreshRequest', 'SKProductsRequest']!
	parents := ['NSObject', 'NSObject', 'SKPayment', 'NSObject', 'SKRequest', 'SKRequest']!
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		for i, name in names {
			cls := ios_runtime.names[name]
			parent := ios_runtime.names[parents[i]]
			assert objc_class_parent(cls) == parent
			assert objc_class_parent(read64(cls)) == read64(parent)
			assert ctext(u64(objc_class_name(cls))) == name
			assert !objc_class_meta(cls) && objc_class_meta(read64(cls))
			// Descriptor storage only, not Apple's private instance layout.
			assert objc_class_size(cls) == if name == 'SKPaymentQueue' { u64(24) } else { u64(8) }
			for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
				symbol := prefix + name
				assert runtime_symbol('/System/Library/Frameworks/StoreKit.framework/StoreKit', symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
				for wrong in ['Foundation', 'UIKit', 'GameKit', 'GameController']! {
					if _ := runtime_symbol('/System/Library/Frameworks/' + wrong + '.framework/' + wrong, symbol) { assert false, wrong + ': ' + symbol }
				}
				if _ := runtime_symbol('/usr/lib/libobjc.A.dylib', symbol) { assert false }
			}
			assert storekit_purchase_family(cls) && storekit_purchase_family(read64(cls))
			assert storekit_purchase_msg(cls, c'class', 0, 0) == cls
			assert storekit_purchase_msg(cls, c'superclass', 0, 0) == parent
			assert objc_class_method(cls, u64(c'class')) != 0
			assert objc_class_method(cls, u64(c'superclass')) != 0
			sub_name := 'Vinix' + name
			sub := objc_allocate_class(cls, sub_name.str, 0)
			objc_register_class(sub)
			assert objc_class_parent(sub) == cls && storekit_purchase_family(sub)
			assert storekit_purchase_family(read64(sub))
			assert storekit_purchase_msg(sub, c'superclass', 0, 0) == cls
			for target in [cls, sub]! {
				for selector in [c'alloc', c'allocWithZone:', c'new', c'init', c'copy', c'copyWithZone:',
					c'mutableCopy', c'mutableCopyWithZone:', c'initWithCoder:', c'encodeWithCoder:',
					c'classForCoder', c'supportsSecureCoding', c'initWithProductIdentifiers:', c'initWithReceiptProperties:', c'defaultQueue',
					c'paymentWithProduct:', c'paymentWithProductIdentifier:', c'addPayment:', c'finishTransaction:',
					c'addTransactionObserver:', c'removeTransactionObserver:', c'transactions', c'canMakePayments',
					c'productIdentifier', c'quantity', c'start', c'cancel', c'delegate', c'setDelegate:']! {
					instance := name == 'SKPaymentQueue' && ctext(u64(selector)) in ['addTransactionObserver:', 'removeTransactionObserver:', 'transactions']!
					assert (objc_instance_method(target, u64(selector)) != 0) == instance, ctext(u64(selector))
					implemented := name == 'SKPaymentQueue' && ctext(u64(selector)) in ['defaultQueue', 'canMakePayments']!
					assert (objc_class_method(target, u64(selector)) != 0) == implemented, ctext(u64(selector))
					assert objc_responds(target, selector) == implemented, ctext(u64(selector))
				}
			}
		}
		if _ := runtime_symbol('/System/Library/Frameworks/StoreKit.framework/StoreKit', '_OBJC_CLASS_$_SKPaymentTransaction') { assert false }
		assert !storekit_purchase_family(ios_runtime.names['NSObject'])
		assert !storekit_purchase_family(ios_runtime.names['SKStorefront'])
		objc_pool_pop(pool)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-STOREKIT-PURCHASE: six scoped class/metaclass imports, native inheritance, subclass metadata, truthful reflection and two drained runtimes')
}

fn test_storekit_purchase_construction_rejected() {
	objc_start()
	for name in ['SKPaymentQueue', 'SKPayment', 'SKMutablePayment', 'SKRequest', 'SKReceiptRefreshRequest', 'SKProductsRequest']! {
		cls := ios_runtime.names[name]
		sub_name := 'Blocked' + name
		sub := objc_allocate_class(cls, sub_name.str, 0)
		objc_register_class(sub)
		for target in [cls, sub]! {
			for mode in ['alloc', 'allocWithZone:', 'new', 'init', 'initWithProductIdentifiers:', 'initWithReceiptProperties:', 'copy', 'mutableCopy', 'allocate', 'caller', 'install', 'super-alloc', 'super-new', 'isa-in', 'isa-out', 'defaultQueue', 'paymentWithProduct:', 'paymentWithProductIdentifier:', 'addPayment:', 'start', 'cancel', 'missing-imp', 'metaclass']! {
				// Preserve all 276 rejection checks after enabling the queue factory.
				requested := if name == 'SKPaymentQueue' && target == cls && mode == 'defaultQueue' { 'restoreCompletedTransactions' } else { mode }
				mut fds := [2]i32{}
				assert C.pipe(unsafe { &fds[0] }) == 0
				pid := C.fork()
				assert pid >= 0
				if pid == 0 {
					C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
					match mode {
						'allocate' { objc_allocate(target) }
						'caller' { mut storage := [1]u64{}; objc_construct_instance(target, u64(unsafe { &storage[0] })) }
						'install' { mut storage := [1]u64{}; objc_install_storage(target, u64(unsafe { &storage[0] }), true) }
						'metaclass' { objc_allocate(read64(target)) }
						'super-alloc', 'super-new', 'missing-imp' {
							selector := if mode == 'super-alloc' { c'alloc' } else if mode == 'super-new' { c'new' } else { c'notAPurchaseMethod' }
							imp := if mode == 'missing-imp' { objc_method_implementation(read64(target), u64(selector)) } else { objc_method_imp(objc_class_method(ios_runtime.names['NSObject'], u64(selector))) }
							assert imp != 0
							unsafe { StorekitPurchaseSend(voidptr(imp))(target, u64(selector), 0, 0) }
						}
						'isa-in' { objc_set_class(objc_allocate(ios_runtime.names['NSObject']), target) }
						'isa-out' {
							object := objc_allocate(ios_runtime.names['NSObject'])
							// Simulate corrupt storage without constructing a payment or request.
							obj_header(object).allocation_cls = target
							objc_set_class(object, ios_runtime.names['NSObject'])
						}
						else { storekit_purchase_msg(target, requested.str, 0, 0) }
					}
					C._exit(0)
				}
				C.close(fds[1])
				mut bytes := [16384]u8{}
				mut length := 0
				for {
					assert length < bytes.len
					count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length))
					if count == 0 { break }
					if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
					assert count > 0
					length += int(count)
				}
				C.close(fds[0])
				mut status := i32(0)
				assert C.ios_waitpid(pid, &status, 0) == pid && status == 256, mode
				output := unsafe { tos(&bytes[0], length) }
				reason := if mode.starts_with('isa-') { 'changing StoreKit purchase storage isa is not implemented' } else { 'StoreKit payment and request construction or operations are not implemented' }
				assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:') && !output.contains('> assert '), mode + ': ' + output
				if !mode.starts_with('isa-') {
					assert output.contains(ctext(u64(objc_class_name(target))) + ' '), mode + ': ' + output
					operation := match mode {
						'allocate', 'caller', 'install', 'metaclass' { 'allocation/storage' }
						'super-alloc' { 'alloc' }
						'super-new' { 'new' }
						'missing-imp' { 'notAPurchaseMethod' }
						else { requested }
					}
					assert output.contains(': ' + ctext(u64(objc_class_name(target))) + ' ' + operation + '\n'), mode + ': ' + output
				}
			}
		}
	}
	objc_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	println('IOS-STOREKIT-PURCHASE-REJECT: 276 dispatch, factories, direct/caller allocation, metaclass, subclass, saved NSObject IMP and isa cases fail explicitly')
}

fn storekit_queue_reader() u64 {
	pool := objc_pool_push()
	cls := ios_runtime.names['SKPaymentQueue']
	object := storekit_purchase_msg(cls, c'defaultQueue', 0, 0)
	for _ in 0 .. 128 {
		assert storekit_purchase_msg(cls, c'defaultQueue', 0, 0) == object
		assert storekit_purchase_msg(cls, c'canMakePayments', 0, 0) == 0
		assert storekit_purchase_msg(object, c'retain', 0, 0) == object
		storekit_purchase_msg(object, c'release', 0, 0)
	}
	objc_pool_pop(pool)
	return object
}

fn test_storekit_queue_factory() {
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		baseline := ios_runtime.live
		assert ios_runtime.storekit_queue == 0
		mut workers := []thread u64{}
		for _ in 0 .. 8 { workers << spawn storekit_queue_reader() }
		objects := workers.wait()
		object := objects[0]
		assert object != 0
		for result in objects { assert result == object }
		unsafe { workers.free(); objects.free() }
		cls := ios_runtime.names['SKPaymentQueue']
		assert ios_runtime.live == baseline + 1 && obj_header(object).refs == 1
		assert storekit_purchase_msg(object, c'class', 0, 0) == cls
		assert storekit_purchase_msg(object, c'self', 0, 0) == object
		assert storekit_purchase_msg(object, c'isKindOfClass:', ios_runtime.names['NSObject'], 0) == 1
		for selector in [c'defaultQueue', c'canMakePayments']! {
			method := objc_class_method(cls, u64(selector))
			assert method != 0 && objc_instance_method(cls, u64(selector)) == 0
			types := if selector == c'defaultQueue' { '@16@0:8' } else { 'B16@0:8' }
			assert ctext(u64(objc_method_types(method))) == types
			assert objc_responds(cls, selector) && !objc_responds(object, selector)
			signature := storekit_purchase_msg(cls, c'methodSignatureForSelector:', u64(selector), 0)
			assert signature != 0
			assert storekit_purchase_msg(signature, c'numberOfArguments', 0, 0) == 2
			assert ctext(storekit_purchase_msg(signature, c'methodReturnType', 0, 0)) == types[..1]
			imp := objc_method_imp(method)
			actual := unsafe { StorekitPurchaseSend(voidptr(imp))(cls, u64(selector), 0, 0) }
			assert actual == if selector == c'defaultQueue' { object } else { u64(0) }
		}
		for selector in [c'addPayment:', c'finishTransaction:', c'restoreCompletedTransactions', c'delegate', c'setDelegate:', c'init', c'copy']! {
			assert !objc_responds(object, selector) && objc_instance_method(cls, u64(selector)) == 0
		}
		objc_retain(object)
		assert storekit_purchase_msg(object, c'autorelease', 0, 0) == object
		objc_pool_pop(pool)
		assert obj_header(object).refs == 1
		assert storekit_purchase_msg(cls, c'defaultQueue', 0, 0) == object
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		assert ios_runtime.storekit_queue == 0 && ios_runtime.storekit_queue_retired
	}
	println('IOS-STOREKIT-QUEUE: typed factory and false payment availability, message/direct IMP calls, eight concurrent first readers, balanced ownership and two drained runtimes')
}

fn test_storekit_queue_lifetime_rejections() {
	objc_start()
	cls := ios_runtime.names['SKPaymentQueue']
	object := storekit_purchase_msg(cls, c'defaultQueue', 0, 0)
	for mode in ['destroy', 'release-borrowed', 'retired', 'wrong-scope', 'finishTransaction:', 'addPayment:', 'saved-imp-wrong-scope']! {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork()
		assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			match mode {
				'destroy' { objc_destruct_instance(object) }
				'release-borrowed' { objc_release(object) }
				'retired' { storekit_queue_stop(); storekit_purchase_msg(cls, c'defaultQueue', 0, 0) }
				'wrong-scope' { storekit_purchase_msg(object, c'defaultQueue', 0, 0) }
				'saved-imp-wrong-scope' {
					imp := objc_method_imp(objc_class_method(cls, u64(c'defaultQueue')))
					unsafe { StorekitPurchaseSend(voidptr(imp))(object, u64(c'defaultQueue'), 0, 0) }
				}
				else { storekit_purchase_msg(object, mode.str, 0, 0) }
			}
			C._exit(0)
		}
		C.close(fds[1])
		mut bytes := [16384]u8{}
		mut length := 0
		for {
			assert length < bytes.len
			count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0
			length += int(count)
		}
		C.close(fds[0])
		mut status := i32(0)
		assert C.ios_waitpid(pid, &status, 0) == pid && status == 256, mode
		output := unsafe { tos(&bytes[0], length) }
		reason := match mode {
			'destroy', 'release-borrowed' { 'destroying cached payment queue storage' }
			'retired' { 'payment queue cache is retired' }
			else { 'StoreKit payment and request construction or operations are not implemented: SKPaymentQueue ' }
		}
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:') && !output.contains('> assert '), mode + ': ' + output
	}
	objc_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	println('IOS-STOREKIT-QUEUE-REJECT: seven cache destruction, retirement, wrong-scope, saved IMP and unsupported operation cases fail explicitly')
}

fn storekit_observer_updated(object u64, selector u64, queue u64, transactions u64) {
	_ = object; _ = selector; _ = queue; _ = transactions
	panic('test: payment provider must not manufacture transaction callbacks')
}

fn storekit_observer_class() u64 {
	cls := objc_allocate_class(ios_runtime.names['NSObject'], c'VinixPaymentObserver', 0)
	assert objc_add_method(cls, u64(c'paymentQueue:updatedTransactions:'), u64(unsafe { voidptr(storekit_observer_updated) }), c'v32@0:8@16@24')
	objc_register_class(cls)
	return cls
}

fn storekit_observer_worker(cls u64, queue u64) {
	observer := objc_allocate(cls)
	for _ in 0 .. 64 {
		pool := objc_pool_push()
		storekit_purchase_msg(queue, c'addTransactionObserver:', observer, 0)
		storekit_purchase_msg(queue, c'addTransactionObserver:', observer, 0)
		snapshot := storekit_purchase_msg(queue, c'transactionObservers', 0, 0)
		assert observer in obj_header(snapshot).items
		storekit_purchase_msg(queue, c'removeTransactionObserver:', observer, 0)
		objc_pool_pop(pool)
	}
	objc_release(observer)
}

fn test_storekit_queue_observers() {
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		queue := storekit_purchase_msg(ios_runtime.names['SKPaymentQueue'], c'defaultQueue', 0, 0)
		cls := storekit_observer_class()
		baseline := ios_runtime.live
		weak_baseline := ios_runtime.weak.len
		for selector in [c'addTransactionObserver:', c'removeTransactionObserver:', c'transactionObservers', c'transactions']! {
			method := objc_instance_method(ios_runtime.names['SKPaymentQueue'], u64(selector))
			assert method != 0 && objc_responds(queue, selector)
			assert !objc_responds(ios_runtime.names['SKPaymentQueue'], selector)
			types := if ctext(u64(selector)).ends_with(':') { 'v24@0:8@16' } else { '@16@0:8' }
			assert ctext(u64(objc_method_types(method))) == types
			signature := storekit_purchase_msg(queue, c'methodSignatureForSelector:', u64(selector), 0)
			assert signature != 0
			assert storekit_purchase_msg(signature, c'numberOfArguments', 0, 0) == if types[0] == `v` { u64(3) } else { u64(2) }
		}
		observer := objc_allocate(cls)
		mut weak := u64(0)
		objc_store_weak(&weak, observer)
		imp := objc_method_imp(objc_instance_method(ios_runtime.names['SKPaymentQueue'], u64(c'addTransactionObserver:')))
		unsafe { StorekitPurchaseSend(voidptr(imp))(queue, u64(c'addTransactionObserver:'), observer, 0) }
		storekit_purchase_msg(queue, c'addTransactionObserver:', observer, 0)
		assert ios_runtime.storekit_observers.len == 1 && obj_header(observer).refs == 1
		inner := objc_pool_push()
		snapshot := objc_retain(storekit_purchase_msg(queue, c'transactionObservers', 0, 0))
		assert obj_header(snapshot).items.len == 1 && obj_header(snapshot).items[0] == observer
		assert !objc_is_kind(snapshot, ios_runtime.names['NSMutableArray'])
		assert obj_header(storekit_purchase_msg(queue, c'transactions', 0, 0)).items.len == 0
		objc_pool_pop(inner)
		storekit_purchase_msg(queue, c'removeTransactionObserver:', observer, 0)
		storekit_purchase_msg(queue, c'removeTransactionObserver:', observer, 0)
		assert ios_runtime.storekit_observers.len == 0
		objc_release(observer)
		assert weak != 0 // The snapshot, independently of registration, owns this observer.
		objc_release(snapshot)
		assert weak == 0
		objc_destroy_weak(&weak)
		// Grow the table, then deallocate without explicit removal: weak slot
		// addresses must survive array reallocations and later be unregistered.
		mut values := []u64{}
		values.flags |= .noslices
		for _ in 0 .. 80 {
			value := objc_allocate(cls)
			values << value
			storekit_purchase_msg(queue, c'addTransactionObserver:', value, 0)
		}
		assert ios_runtime.storekit_observers.len == 80
		for value in values { objc_release(value) }
		unsafe { values.free() }
		for record in ios_runtime.storekit_observers { assert record.object == 0 }
		assert obj_header(storekit_purchase_msg(queue, c'transactionObservers', 0, 0)).items.len == 0
		assert ios_runtime.storekit_observers.len == 0 && ios_runtime.weak.len == weak_baseline
		mut workers := []thread{}
		workers.flags |= .noslices
		for _ in 0 .. 8 { workers << spawn storekit_observer_worker(cls, queue) }
		workers.wait()
		unsafe { workers.free() }
		assert ios_runtime.storekit_observers.len == 0 && ios_runtime.weak.len == weak_baseline
		objc_pool_pop(pool)
		assert ios_runtime.live == baseline
		// Shutdown unregisters a still-live observer without retaining/releasing it.
		remaining := objc_allocate(cls)
		storekit_purchase_msg(queue, c'addTransactionObserver:', remaining, 0)
		storekit_queue_stop()
		assert ios_runtime.storekit_observers.len == 0 && ios_runtime.weak.len == weak_baseline
		assert obj_header(remaining).refs == 1
		objc_release(remaining)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-STOREKIT-OBSERVERS: weak identity registration, duplicates, removal, immutable owned snapshots, zeroing after growth, eight concurrent writers, no synthetic transactions and two drained runtimes')
}

fn test_storekit_queue_observer_invalid_input() {
	objc_start()
	queue := storekit_purchase_msg(ios_runtime.names['SKPaymentQueue'], c'defaultQueue', 0, 0)
	invalid := objc_allocate(ios_runtime.names['NSObject'])
	for mode in ['nil-add', 'nil-remove', 'missing-callback', 'retired-observer']! {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0
		mut status := i32(0)
		pid := C.fork()
		assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			if mode == 'retired-observer' { objc_retain(queue); storekit_queue_stop() }
			selector := if mode == 'nil-remove' { c'removeTransactionObserver:' } else if mode == 'retired-observer' { c'transactionObservers' } else { c'addTransactionObserver:' }
			storekit_purchase_msg(queue, selector, if mode == 'missing-callback' { invalid } else { u64(0) }, 0)
			C._exit(0)
		}
		C.close(fds[1])
		mut bytes := [16384]u8{}
		mut length := 0
		for {
			assert length < bytes.len
			count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0
			length += int(count)
		}
		C.close(fds[0])
		assert C.ios_waitpid(pid, &status, 0) == pid && status == 256
		output := unsafe { tos(&bytes[0], length) }
		reason := match mode {
			'missing-callback' { 'payment observer requires paymentQueue:updatedTransactions:' }
			'retired-observer' { 'payment queue cache is retired' }
			else { 'payment queue requires a non-nil observer' }
		}
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:') && !output.contains('> assert '), output
	}
	objc_release(invalid)
	objc_stop()
	println('IOS-STOREKIT-OBSERVERS-REJECT: nil add/remove, missing required callback and retired queue rejected explicitly')
}
