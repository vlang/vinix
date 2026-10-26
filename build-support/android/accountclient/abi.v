// SPDX-License-Identifier: GPL-2.0-or-later
// Normal V library boundary for the freestanding Android JNI runtime.
module accountclient

import nativeaccountauth

#include <string.h>

fn C.strnlen(&u8, uint) uint

@[heap]
struct RequestBuilder {
mut:
	id              u64
	op              nativeaccountauth.Operation
	account_name    ?string
	account_type    ?string
	auth_token_type ?string
	features        []string
	options         []nativeaccountauth.Option
}

// C strings are standard UTF-8, not JNI modified UTF-8. The wire encoder
// checks UTF-8, embedded NUL, unique keys/features and reserved identity keys.
fn abi_string(value &u8) !string {
	if value == unsafe { nil } { return error('missing account text') }
	length := C.strnlen(value, 4097)
	if length > 4096 { return error('account text exceeds limit') }
	return unsafe { value.vstring_with_len(int(length)).clone() }
}

pub fn scalar(tag u16, text &u8, number i64) !nativeaccountauth.Scalar {
	return match tag {
		0 { nativeaccountauth.Scalar{ kind: .null_value } }
		1 { nativeaccountauth.Scalar{ kind: .text, text: abi_string(text)! } }
		2 {
			if number !in [i64(0), 1] { return error('invalid account boolean') }
			nativeaccountauth.Scalar{ kind: .boolean, boolean: number == 1 }
		}
		3 {
			if number < -2147483648 || number > 2147483647 {
				return error('account int32 overflow')
			}
			nativeaccountauth.Scalar{ kind: .int32, number: number }
		}
		4 { nativeaccountauth.Scalar{ kind: .int64, number: number } }
		else { return error('unknown account scalar tag') }
	}
}

@[export: 'vinix_android_account_request']
pub fn abi_request(id u64, op u16, account_type &u8, token_type &u8) voidptr {
	if id == 0 || op !in [u16(1), 2] { return unsafe { nil } }
	mut builder := &RequestBuilder{ id: id, op: unsafe { nativeaccountauth.Operation(op) } }
	if account_type != unsafe { nil } {
		builder.account_type = abi_string(account_type) or {
			abi_request_free(builder)
			return unsafe { nil }
		}
	}
	if token_type != unsafe { nil } {
		builder.auth_token_type = abi_string(token_type) or {
			abi_request_free(builder)
			return unsafe { nil }
		}
	}
	return builder
}

// A separate builder preserves the existing addition/query C ABI. Every field
// is copied before returning; submit performs the complete wire validation.
@[export: 'vinix_android_account_token_request']
pub fn abi_token_request(id u64, name &u8, account_type &u8, token_type &u8) voidptr {
	if id == 0 { return unsafe { nil } }
	mut builder := &RequestBuilder{id: id, op: .get_auth_token}
	builder.account_name = abi_string(name) or { abi_request_free(builder); return unsafe { nil } }
	builder.account_type = abi_string(account_type) or { abi_request_free(builder); return unsafe { nil } }
	builder.auth_token_type = abi_string(token_type) or { abi_request_free(builder); return unsafe { nil } }
	return builder
}

@[export: 'vinix_android_account_feature']
pub fn abi_feature(handle voidptr, value &u8) i32 {
	if handle == unsafe { nil } { return -1 }
	mut builder := unsafe { &RequestBuilder(handle) }
	if builder.features.len >= 32 { return -1 }
	feature := abi_string(value) or { return -1 }
	if feature.len == 0 || feature in builder.features {
		unsafe { feature.free() }
		return -1
	}
	builder.features << feature
	return 0
}

@[export: 'vinix_android_account_option']
pub fn abi_option(handle voidptr, key &u8, tag u16, text &u8, number i64) i32 {
	if handle == unsafe { nil } { return -1 }
	mut builder := unsafe { &RequestBuilder(handle) }
	name := abi_string(key) or { return -1 }
	if name.len == 0 || builder.options.len >= 32 || builder.options.any(it.key == name) {
		unsafe { name.free() }
		return -1
	}
	value := scalar(tag, text, number) or {
		unsafe { name.free() }
		return -1
	}
	builder.options << nativeaccountauth.Option{name, value}
	return 0
}

@[export: 'vinix_android_account_submit']
pub fn abi_submit(handle voidptr, endpoint &u8) voidptr {
	if handle == unsafe { nil } { return unsafe { nil } }
	builder := unsafe { &RequestBuilder(handle) }
	path := abi_string(endpoint) or { return unsafe { nil } }
	defer { unsafe { path.free() } }
	request := nativeaccountauth.Request{
		id:              builder.id
		operation:       builder.op
		account_name:    builder.account_name
		account_type:    builder.account_type
		auth_token_type: builder.auth_token_type
		features:        builder.features
		options:         builder.options
	}
	return submit(request, path) or { return unsafe { nil } }
}

@[export: 'vinix_android_account_request_free']
pub fn abi_request_free(handle voidptr) {
	if handle == unsafe { nil } { return }
	mut builder := unsafe { &RequestBuilder(handle) }
	// The submitted client owns its encoded request, never these builder arrays.
	nativeaccountauth.dispose_request(nativeaccountauth.Request{
		id:              builder.id
		operation:       builder.op
		account_name:    builder.account_name
		account_type:    builder.account_type
		auth_token_type: builder.auth_token_type
		features:        builder.features
		options:         builder.options
	})
	unsafe { free(builder) }
}

@[export: 'vinix_android_account_read']
pub fn abi_read(handle voidptr, kind &u16, id &u64, timeout i32) i32 {
	if handle == unsafe { nil } || kind == unsafe { nil } || id == unsafe { nil } { return -1 }
	mut client := unsafe { &Client(handle) }
	if !client.read(int(timeout)) or { return -1 } { return 0 }
	unsafe {
		*kind = u16(client.current.kind)
		*id = client.current.id
	}
	return 1
}

// Copy the broker's public ticket while the caller still owns the current
// event. No service response capability, Java object or target crosses this ABI.
@[export: 'vinix_android_account_interaction']
pub fn abi_interaction(handle voidptr, output &u8, length u32) i32 {
	if handle == unsafe { nil } || output == unsafe { nil } || length != 32 { return -1 }
	client := unsafe { &Client(handle) }
	if client.current.kind != .interaction || client.current.interaction.handle.len != 32 {
		return -1
	}
	unsafe { C.memcpy(output, client.current.interaction.handle.data, 32) }
	return 0
}

@[export: 'vinix_android_account_close']
pub fn abi_close(handle voidptr) {
	if handle == unsafe { nil } { return }
	mut client := unsafe { &Client(handle) }
	client.close()
	unsafe { free(client) }
}

@[export: 'vinix_android_account_count']
pub fn abi_count(handle voidptr) u32 {
	if handle == unsafe { nil } { return 0 }
	return u32(unsafe { &Client(handle) }.current.options.len)
}

@[export: 'vinix_android_account_key']
pub fn abi_key(handle voidptr, index u32) &u8 {
	if handle == unsafe { nil } { return unsafe { nil } }
	client := unsafe { &Client(handle) }
	if index >= u32(client.current.options.len) { return unsafe { nil } }
	return client.current.options[index].key.str
}

@[export: 'vinix_android_account_tag']
pub fn abi_tag(handle voidptr, index u32) u16 {
	if handle == unsafe { nil } { return 0xffff }
	client := unsafe { &Client(handle) }
	if index >= u32(client.current.options.len) { return 0xffff }
	return u16(client.current.options[index].value.kind)
}

@[export: 'vinix_android_account_text']
pub fn abi_text(handle voidptr, index u32) &u8 {
	if handle == unsafe { nil } { return unsafe { nil } }
	client := unsafe { &Client(handle) }
	if index >= u32(client.current.options.len) || client.current.options[index].value.kind != .text {
		return unsafe { nil }
	}
	return client.current.options[index].value.text.str
}

@[export: 'vinix_android_account_number']
pub fn abi_number(handle voidptr, index u32) i64 {
	if handle == unsafe { nil } { return 0 }
	client := unsafe { &Client(handle) }
	if index >= u32(client.current.options.len) { return 0 }
	value := client.current.options[index].value
	return if value.kind == .boolean { i64(value.boolean) } else { value.number }
}

@[export: 'vinix_android_account_account_count']
pub fn abi_account_count(handle voidptr) u32 {
	if handle == unsafe { nil } { return 0 }
	return u32(unsafe { &Client(handle) }.current.accounts.len)
}

@[export: 'vinix_android_account_account_name']
pub fn abi_account_name(handle voidptr, index u32) &u8 {
	if handle == unsafe { nil } { return unsafe { nil } }
	client := unsafe { &Client(handle) }
	if index >= u32(client.current.accounts.len) { return unsafe { nil } }
	return client.current.accounts[index].name.str
}

@[export: 'vinix_android_account_account_type']
pub fn abi_account_type(handle voidptr, index u32) &u8 {
	if handle == unsafe { nil } { return unsafe { nil } }
	client := unsafe { &Client(handle) }
	if index >= u32(client.current.accounts.len) { return unsafe { nil } }
	return client.current.accounts[index].account_type.str
}
