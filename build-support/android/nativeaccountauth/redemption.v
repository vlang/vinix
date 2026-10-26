// SPDX-License-Identifier: GPL-2.0-or-later
module nativeaccountauth

// An interaction is redeemed on a fresh kernel-authenticated connection. The
// ticket identifies one original request; it never names an Activity, caller,
// process-local object or authenticator response capability.
pub struct Redemption {
pub:
	request    u64
	capability []u8
}

fn validate_redemption(value Redemption) ! {
	if value.request == 0 || value.capability.len != 32 {
		return error('invalid account interaction redemption')
	}
	mut any := u8(0)
	for byte in value.capability { any |= byte }
	if any == 0 { return error('invalid account interaction ticket') }
}

fn append_redemption(mut body []u8, value Redemption) ! {
	validate_redemption(value)!
	append_uint(mut body, value.request, 8)
	body << value.capability
}

fn (mut reader RequestReader) redemption() !Redemption {
	request := reader.uint_value(8)!
	if reader.position > reader.bytes.len - 32 {
		return error('truncated account interaction ticket')
	}
	capability := reader.bytes[reader.position..reader.position + 32].clone()
	reader.position += 32
	value := Redemption{request, capability}
	validate_redemption(value) or {
		unsafe { capability.free() }
		return err
	}
	return value
}
