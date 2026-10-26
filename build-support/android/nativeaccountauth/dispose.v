// SPDX-License-Identifier: GPL-2.0-or-later
module nativeaccountauth

// These disposal helpers are for owning decoder/builder results only, never
// registry-backed caller identities or caller-owned literals/borrowed arrays.
pub fn dispose_options(options []Option) {
	for option in options {
		unsafe { option.key.free() }
		if option.value.kind == .text { unsafe { option.value.text.free() } }
	}
	unsafe { options.free() }
}

pub fn dispose_request(request Request) {
	if value := request.redemption { unsafe { value.capability.free() } }
	if value := request.account_name { unsafe { value.free() } }
	if value := request.account_type { unsafe { value.free() } }
	if value := request.auth_token_type { unsafe { value.free() } }
	if value := request.token_value { unsafe { value.free() } }
	// []string.free() also releases its strings; freeing each feature first
	// would release every decoded feature twice.
	unsafe { request.features.free() }
	dispose_options(request.options)
}
