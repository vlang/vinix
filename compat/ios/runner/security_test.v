// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_native_security_certificate_and_key_ownership() {
	path := os.getenv('VINIX_IOS_SECURITY_FIXTURE')
	if path == '' { return }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	image := macho.parse(data)!
	defer { module_image_free(image) }
	for _ in 0 .. 2 {
		assert execute(image, [path])! == 0
		assert ios_runtime.live == 0
	}
}

fn test_security_der_bounds_curve_validation_and_unsupported_services() {
	objc_start()
	defer { objc_stop() }
	assert cf_hash(0) == 0
	mut bytes := [1024]u8{}
	mut state := u32(71)
	for length in 0 .. 1024 {
		for i in 0 .. length {
			state = state * u32(1664525) + u32(1013904223)
			bytes[i] = u8(state >> 24)
		}
		// Deterministic malformed input exercises cursor lengths/nesting under ASAN.
		parsed := security_certificate_parse(unsafe { &bytes[0] }, length)
		assert parsed == none
	}
	bytes[0] = 4 // (0,0) is off-curve for each supported NIST curve.
	for i in 1 .. 1024 { bytes[i] = 0 }
	for bits in [256, 384, 521] {
		assert !security_ec_point(unsafe { &bytes[0] }, 1 + 2 * ((bits + 7) / 8), bits)
	}
	assert sec_random_copy(0, 0, unsafe { nil }) == 0
	assert sec_random_copy(1, 1, unsafe { &bytes[0] }) != 0
	assert sec_random_copy(0, ~u64(0), unsafe { &bytes[0] }) != 0
	assert security_symbol('_SecTrustEvaluateWithError') != none
	assert security_symbol('_SecTrustCreateWithCertificates') != none
	assert sec_policy_ssl(1, ios_runtime.names['NSObject']) == 0
	assert sec_policy_properties(0) == 0
	assert security_symbol('_SecItemAdd') != none
	assert ios_runtime.live == 0
}
