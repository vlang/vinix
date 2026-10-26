// SPDX-License-Identifier: GPL-2.0-or-later
module accountclient

// These getters borrow the current decoded event until the next read or close,
// exactly like the account snapshot ABI. They never expose registry pointers.
@[export: 'vinix_android_account_authenticator_count']
pub fn abi_authenticator_count(handle voidptr) u32 {
	if handle == unsafe { nil } { return 0 }
	client := unsafe { &Client(handle) }
	if client.current.kind != .authenticators { return 0 }
	return u32(client.current.authenticators.len)
}

@[export: 'vinix_android_account_authenticator_type']
pub fn abi_authenticator_type(handle voidptr, index u32) &u8 {
	if index >= abi_authenticator_count(handle) { return unsafe { nil } }
	return unsafe { &Client(handle) }.current.authenticators[index].account_type.str
}

@[export: 'vinix_android_account_authenticator_package']
pub fn abi_authenticator_package(handle voidptr, index u32) &u8 {
	if index >= abi_authenticator_count(handle) { return unsafe { nil } }
	return unsafe { &Client(handle) }.current.authenticators[index].package_name.str
}

// field: 0=labelId, 1=iconId, 2=smallIconId, 3=accountPreferencesId.
@[export: 'vinix_android_account_authenticator_resource']
pub fn abi_authenticator_resource(handle voidptr, index u32, field u16) u32 {
	if index >= abi_authenticator_count(handle) { return 0 }
	value := unsafe { &Client(handle) }.current.authenticators[index]
	return match field {
		0 { value.label_id }
		1 { value.icon_id }
		2 { value.small_icon_id }
		3 { value.account_preferences_id }
		else { 0 }
	}
}

@[export: 'vinix_android_account_authenticator_custom_tokens']
pub fn abi_authenticator_custom_tokens(handle voidptr, index u32) i32 {
	if index >= abi_authenticator_count(handle) { return -1 }
	return i32(unsafe { &Client(handle) }.current.authenticators[index].custom_tokens)
}
