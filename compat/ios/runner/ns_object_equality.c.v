// SPDX-License-Identifier: GPL-2.0-or-later
module main

// A saved NSObject IMP must keep identity semantics even when called on a
// value subclass or after the method is replaced. Do not redispatch it through
// the receiver's framework implementation.
fn ns_object_identity_equal(object u64, _selector u64, other u64) bool {
	return object == other
}

// These classes override NSObject's identity comparison in Foundation. Their
// Objective-C equality implementations are still unavailable; keep rejecting
// the message rather than silently inheriting the wrong comparison. Existing
// CF equality and Swift bridging helpers continue to handle their value data.
fn ns_object_equality_unavailable(name string, meta bool, selector string) bool {
	return !meta && selector == 'isEqual:' && name in [
		'NSString', 'NSArray', 'NSDictionary', 'NSData', 'NSIndexPath']!
}
