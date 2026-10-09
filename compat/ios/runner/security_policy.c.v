// SPDX-License-Identifier: GPL-2.0-or-later
// Owned X.509/SSL policy metadata. A policy is not a trust evaluation.
module main

fn sec_policy_type_id() u64 { return ios_runtime.names['VinixSecPolicy'] }

fn security_policy_create(ssl bool, server bool, hostname u64) u64 {
	if hostname != 0 && (!objc_is_kind(hostname, ios_runtime.names['NSString']) || string_text(hostname).len > 65536) { return 0 }
	policy := objc_allocate(sec_policy_type_id())
	properties := objc_allocate(ios_runtime.names['NSMutableDictionary'])
	security_attribute(properties, '_kSecPolicyOid', read64(security_constant(if ssl {
		'_kSecPolicyAppleSSL'
	} else {
		'_kSecPolicyAppleX509Basic'
	}) or { panic('iOS: missing Security policy identifier') }))
	if ssl && !server { security_attribute(properties, '_kSecPolicyClient', framework_object('_kCFBooleanTrue')) }
	if hostname != 0 {
		text := string_text(hostname)
		copied := cf_string_bytes(0, u64(text.str), text.len, 0x08000100, false)
		if copied == 0 { objc_release(properties); objc_release(policy); return 0 }
		security_attribute(properties, '_kSecPolicyName', copied)
		objc_release(copied)
	}
	objc_set_class(properties, ios_runtime.names['NSDictionary'])
	store_field(policy, 0, properties)
	objc_release(properties)
	return policy
}

fn sec_policy_basic() u64 { return security_policy_create(false, false, 0) }
fn sec_policy_ssl(server u8, hostname u64) u64 { return security_policy_create(true, server != 0, hostname) }

fn sec_policy_properties(policy u64) u64 {
	if policy == 0 || read64(policy) != sec_policy_type_id() { return 0 }
	return objc_retain(obj_header(policy).fields[0])
}
