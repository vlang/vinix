// SPDX-License-Identifier: GPL-2.0-or-later
module accountclient

import nativeaccountauth

// Redeem on a fresh authenticated connection. The ticket is opaque to the
// Activity process; only the broker may resolve its origin or launch target.
// submit owns an encoded copy before this function returns.
pub fn redeem(id u64, original_request u64, ticket []u8, endpoint string) !&Client {
	return submit(nativeaccountauth.Request{
		id: id
		operation: .redeem_interaction
		redemption: nativeaccountauth.Redemption{request: original_request, capability: ticket}
	}, endpoint)
}

@[export: 'vinix_android_account_redeem']
pub fn abi_redeem(id u64, original_request u64, ticket &u8, length u32, endpoint &u8) voidptr {
	if ticket == unsafe { nil } || length != 32 { return unsafe { nil } }
	path := abi_string(endpoint) or { return unsafe { nil } }
	defer { unsafe { path.free() } }
	// Only borrowed during synchronous encoding; never retained by the client.
	bytes := unsafe { ticket.vbytes(32) }
	return redeem(id, original_request, bytes, path) or { return unsafe { nil } }
}
