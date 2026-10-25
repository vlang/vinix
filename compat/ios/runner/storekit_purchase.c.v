// SPDX-License-Identifier: GPL-2.0-or-later
module main

// Import and inheritance metadata only; no payment or request storage exists.
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
	if storekit_purchase_family(cls) {
		panic('iOS: StoreKit payment and request construction or operations are not implemented')
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
