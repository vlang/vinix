// SPDX-License-Identifier: GPL-2.0-or-later
module mapsaccountstage

import crypto.sha256

$if macos {
	#include <CommonCrypto/CommonDigest.h>
}

@[typedef]
struct C.CC_SHA256_CTX {}

fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

// One streaming digest owns its context until finish or close. Native host
// hashing keeps multi-gigabyte media verification practical on macOS; the
// portable V implementation preserves the same bytes on other hosts.
pub struct HostSha256 {
mut:
	native   voidptr
	portable &sha256.Digest = unsafe { nil }
	finished bool
}

pub fn new_host_sha256() !HostSha256 {
	$if macos {
		context := &C.CC_SHA256_CTX{}
		if C.CC_SHA256_Init(context) != 1 {
			unsafe { free(context) }
			return error('CC_SHA256_Init failed')
		}
		return HostSha256{native: context}
	} $else {
		return new_portable_host_sha256()
	}
}

fn new_portable_host_sha256() HostSha256 {
	return HostSha256{portable: sha256.new()}
}

pub fn (mut state HostSha256) update(bytes []u8) ! {
	if state.finished { return error('SHA256 state already finished') }
	$if macos {
		if state.native != unsafe { nil } {
			mut offset := 0
			for offset < bytes.len {
				// CC_LONG is 32 bits even when V's int is wider. Keep each
				// call bounded without narrowing an arbitrary input length.
				n := int_min(bytes.len - offset, 1024 * 1024)
				if C.CC_SHA256_Update(state.native, unsafe { &u8(bytes.data) + offset }, u32(n)) != 1 {
					return error('CC_SHA256_Update failed')
				}
				offset += n
			}
			return
		}
	}
	if state.portable.write(bytes)! != bytes.len { return error('SHA256 short write') }
}

pub fn (mut state HostSha256) finish() !string {
	if state.finished { return error('SHA256 state already finished') }
	defer { state.close() }
	$if macos {
		if state.native != unsafe { nil } {
			mut result := [32]u8{}
			if C.CC_SHA256_Final(unsafe { &result[0] }, state.native) != 1 {
				return error('CC_SHA256_Final failed')
			}
			return result[..].hex()
		}
	}
	mut result := []u8{len: 32}
	defer { unsafe { result.free() } }
	state.portable.checksum_into(mut result)
	return result.hex()
}

pub fn (mut state HostSha256) close() {
	if state.finished { return }
	if state.native != unsafe { nil } { unsafe { free(state.native) } }
	if state.portable != unsafe { nil } {
		unsafe {
			state.portable.free()
			free(state.portable)
		}
	}
	state.finished = true
}
