// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os

fn test_native_security_trust_anchor_decisions_and_ownership() {
	path := os.getenv('VINIX_IOS_TRUST_FIXTURE')
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

fn test_security_certificate_time_calendar_and_bounds() {
	for text, expected in {
		'700101000000Z': i64(0)
		'500101000000Z': i64(-631152000)
		'491231235959Z': i64(2524607999)
		'20000229000000Z': i64(951782400)
		'00010101000000Z': i64(-62135596800)
		'99991231235959Z': i64(253402300799)
	} {
		field := SecurityDer{ tag: if text.len == 13 { u8(23) } else { u8(24) }, length: text.len, end: text.len }
		assert security_certificate_time(text.str, field)? == expected
	}
	for text in ['19000229000000Z', '20010229000000Z', '261309000000Z', '260000000000Z',
		'261032000000Z', '261009240000Z', '261009006000Z', '261009000060Z', '261009000000+',
		'26100X000000Z', '00000101000000Z', '', '26Z'] {
		field := SecurityDer{ tag: if text.len == 13 { u8(23) } else { u8(24) }, length: text.len, end: text.len }
		assert security_certificate_time(text.str, field) == none
	}
}

fn test_security_trust_invalid_inputs_and_mutable_array_snapshots() {
	objc_start()
	defer { objc_stop(); assert ios_runtime.live == 0 }
	assert sec_trust_create(0, 0, unsafe { nil }) == -50
	mut output := u64(0x1234)
	assert sec_trust_create(0, 0, &output) == -50 && output == 0x1234
	certificate := objc_allocate(sec_certificate_type_id())
	policy := sec_policy_basic()
	array := objc_allocate(ios_runtime.names['NSMutableArray'])
	mut input := obj_header(array)
	array_append(mut input, certificate)
	assert sec_trust_create(array, policy, &output) == 0
	// Mutation of a caller's array cannot change the owned trust snapshot.
	array_append(mut input, certificate)
	objc_release(array)
	objc_release(certificate)
	objc_release(policy)
	assert sec_trust_count(output) == 1
	assert sec_trust_key(output) == 0 // Typed but empty certificate, never a valid key.
	mut result := u32(99)
	assert sec_trust_evaluate(output, &result) == -4 && result == 0
	date := cf_date_create(0, 1e300)
	assert sec_trust_date(output, date) == -50
	objc_release(date)
	assert sec_trust_date(output, 0) == 0
	assert sec_trust_policies(output, 0) == -50
	assert sec_trust_anchors(output, output) == -50
	assert sec_trust_network_get(output, unsafe { nil }) == -50
	assert sec_trust_evaluate(output, unsafe { nil }) == -50
	assert sec_trust_copy_policies(output, unsafe { nil }) == -50
	mut error_output := u64(0)
	assert !sec_trust_evaluate_error(0, &error_output)
	assert cf_error_code(error_output) == -50
	objc_release(error_output)
	objc_release(output)
	assert ios_runtime.live == ios_runtime.framework_objects.len
}
