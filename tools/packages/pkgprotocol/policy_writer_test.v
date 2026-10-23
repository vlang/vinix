// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}

fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

fn policy_writer_require(ok bool) {
	// These checks must remain effective in -prod consumers too.
	if !ok { panic('policy writer check failed') }
}

fn policy_writer_refused(document &PolicyDocument) {
	text := document.encode() or {
		cause := err.msg()
		unsafe {
			cause.free()
			err.free()
		}
		return
	}
	unsafe { text.free() }
	panic('policy writer accepted invalid wire fields')
}

fn policy_writer_roundtrip(document &PolicyDocument) {
	text := document.encode() or { panic(err) }
	mut decoded := decode_policy_document(text) or { panic(err) }
	unsafe { text.free() }
	policy_writer_require(decoded == *document)
	decoded.close()
	decoded.close()
	policy_writer_require(decoded.architecture == '' && decoded.policy.pins.len == 0 && decoded.policy.allowed.len == 0)
}

fn test_policy_writer_exact_complete_schema_and_independent_owned_output() {
	for arch in ['aarch64', 'x86_64']! {
		document := PolicyDocument{ format: 1, architecture: arch }
		text := document.encode()!
		defer { unsafe { text.free() } }
		expected := '{"format":1,"architecture":"' + arch + '","policy":{"offline":false,"allowed":[],"pins":[],"permissions":[],"licenses":[],"allow_firmware":false,"reserve_bytes":0}}'
		defer { unsafe { expected.free() } }
		policy_writer_require(text == expected)
		policy_writer_roundtrip(&document)
	}
	mut owned := PolicyDocument{
		format:       1
		architecture: 'aarch64'.clone()
		policy:       PolicySettings{
			offline:        true
			allowed:        ['app'.clone(), 'runtime'.clone()]
			pins:           [PolicyPin{ id: 'app'.clone(), minimum: '1.0.0'.clone(), before: '2.0.0'.clone() }]
			permissions:    ['files'.clone(), 'process'.clone()]
			licenses:       ['License "quoted" \\ é🚀'.clone()]
			allow_firmware: true
			reserve_bytes:  u64(1) << 40
		}
	}
	text := owned.encode()!
	owned.close()
	owned.close()
	mut decoded := decode_policy_document(text)!
	unsafe { text.free() }
	policy_writer_require(decoded.policy.offline && decoded.policy.allow_firmware
		&& decoded.policy.reserve_bytes == u64(1) << 40 && decoded.policy.allowed == [
		'app',
		'runtime',
	]
		&& decoded.policy.pins[0].minimum == '1.0.0' && decoded.policy.pins[0].before == '2.0.0'
		&& decoded.policy.licenses[0] == 'License "quoted" \\ é🚀')
	decoded.close()
	decoded.close()
	println('POLICY WRITER complete format-1 schema, empty/false fields, escaping, independent output PASS')
}

fn test_policy_writer_preserves_borrowed_authoring_order_and_service_semantics() {
	mut allowed := ['z'.clone(), 'a'.clone(), 'z'.clone()]
	mut pins := [
		PolicyPin{ id: 'z'.clone(), minimum: '2.0.0'.clone(), before: '1.0.0'.clone() },
		PolicyPin{ id: 'a'.clone(), minimum: ''.clone(), before: ''.clone() },
	]
	mut permissions := ['process'.clone(), 'files'.clone()]
	mut licenses := ['z'.clone(), 'a'.clone()]
	defer {
		unsafe {
			for value in allowed { value.free() }
			(&array(&allowed)).free()
			for pin in pins {
				pin.id.free()
				pin.minimum.free()
				pin.before.free()
			}
			(&array(&pins)).free()
			for value in permissions { value.free() }
			(&array(&permissions)).free()
			for value in licenses { value.free() }
			(&array(&licenses)).free()
		}
	}
	document := PolicyDocument{
		format:       1
		architecture: 'not-an-arch'
		policy:       PolicySettings{
			allowed:       allowed
			pins:          pins
			permissions:   permissions
			licenses:      licenses
			reserve_bytes: ~u64(0)
		}
	}
	text := document.encode()!
	defer { unsafe { text.free() } }
	policy_writer_require(text == '{"format":1,"architecture":"not-an-arch","policy":{"offline":false,"allowed":["z","a","z"],"pins":[{"id":"z","minimum":"2.0.0","before":"1.0.0"},{"id":"a","minimum":"","before":""}],"permissions":["process","files"],"licenses":["z","a"],"allow_firmware":false,"reserve_bytes":18446744073709551615}}')
	policy_writer_require(allowed[0] == 'z' && pins[0].minimum == '2.0.0' && permissions[0] == 'process' && licenses[0] == 'z')
	// Presentation decoding deliberately refuses this authoring file; the CLI
	// canonicalizes valid proposals, and independently rejects invalid semantics.
	mut refused := decode_policy_document(text) or {
		unsafe { err.free() }
		PolicyDocument{}
	}
	policy_writer_require(refused.format == 0)
	refused.close()
	println('POLICY WRITER borrowed order, duplicates, ranges and full u64 left to service PASS')
}

fn policy_writer_bad_field(field int, value string) {
	mut words := [value]
	mut pins := [match field {
		1 { PolicyPin{ id: value } }
		2 { PolicyPin{ minimum: value } }
		else { PolicyPin{ before: value } }
	}]
	defer { unsafe {
		(&array(&words)).free()
		(&array(&pins)).free()
	}
	 }
	document := match field {
		0 { PolicyDocument{ format: 1, architecture: value } }
		1, 2, 3 { PolicyDocument{ format: 1, policy: PolicySettings{ pins: pins } } }
		4 { PolicyDocument{ format: 1, policy: PolicySettings{ allowed: words } } }
		5 { PolicyDocument{ format: 1, policy: PolicySettings{ permissions: words } } }
		else { PolicyDocument{ format: 1, policy: PolicySettings{ licenses: words } } }
	}
	policy_writer_refused(&document)
}

fn test_policy_writer_bounds_all_fields_counts_and_escaped_wire_size() {
	for format in [-1, 0, 2, 65535]! { policy_writer_refused(&PolicyDocument{ format: format }) }
	for field in 0 .. 7 {
		limit := [16, 128, 29, 29, 128, 16, 256]![field]
		long := 'a'.repeat(limit + 1)
		policy_writer_bad_field(field, long)
		policy_writer_bad_field(field, '\xff')
		unsafe { long.free() }
	}
	arch := 'a'.repeat(16)
	id := 'i'.repeat(128)
	version := 'v'.repeat(29)
	permission := 'p'.repeat(16)
	license := 'l'.repeat(256)
	mut allowed := []string{len: 4096, cap: 4097, init: id}
	mut pins := []PolicyPin{len: 4096, cap: 4097, init: PolicyPin{ id: id, minimum: version, before: version }}
	mut permissions := []string{len: 5, cap: 6, init: permission}
	mut licenses := []string{len: 4096, cap: 4097, init: license}
	defer {
		unsafe {
			arch.free()
			id.free()
			version.free()
			permission.free()
			license.free()
			(&array(&allowed)).free()
			(&array(&pins)).free()
			(&array(&permissions)).free()
			(&array(&licenses)).free()
		}
	}
	base := PolicyDocument{
		format:       1
		architecture: arch
		policy:       PolicySettings{
			allowed:     allowed
			pins:        pins
			permissions: permissions
			licenses:    licenses
		}
	}
	text := base.encode()!
	unsafe { text.free() }
	allowed << 'overflow'
	policy_writer_refused(&PolicyDocument{ ...base, policy: PolicySettings{ allowed: allowed } })
	pins << PolicyPin{}
	policy_writer_refused(&PolicyDocument{ ...base, policy: PolicySettings{ pins: pins } })
	permissions << 'overflow'
	policy_writer_refused(&PolicyDocument{ ...base, policy: PolicySettings{ permissions: permissions } })
	licenses << 'overflow'
	policy_writer_refused(&PolicyDocument{ ...base, policy: PolicySettings{ licenses: licenses } })
	control128 := '\x00'.repeat(128)
	control256 := '\x00'.repeat(256)
	mut escaped_ids := []string{len: 4096, init: control128}
	mut escaped_licenses := []string{len: 4096, init: control256}
	defer { unsafe {
		control128.free()
		control256.free()
		(&array(&escaped_ids)).free()
		(&array(&escaped_licenses)).free()
	}
	 }
	oversized := PolicyDocument{ format: 1, policy: PolicySettings{ allowed: escaped_ids, licenses: escaped_licenses } }
	$if track_heap ? {
		C.vinix_heap_begin()
	}
	for _ in 0 .. 8 { policy_writer_refused(&oversized) }
	$if track_heap ? {
		policy_writer_require(C.vinix_heap_end() == 0 && C.vinix_heap_count() == 0)
	}
	println('POLICY WRITER UTF-8, every field/count boundary and escaped 8 MiB refusal PASS')
}

fn test_policy_writer_repeated_success_refusal_and_double_close_retires_allocations() {
	$if track_heap ? {
		mut pins := []PolicyPin{cap: 256}
		for index in 0 .. 256 {
			number := index.str()
			padding := '0'.repeat(3 - number.len)
			prefix := 'app' + padding
			id := prefix + number
			unsafe {
				number.free()
				padding.free()
				prefix.free()
			}
			pins << PolicyPin{ id: id, minimum: '1.0.0', before: '2.0.0' }
		}
		defer { unsafe {
			for pin in pins { pin.id.free() }
			(&array(&pins)).free()
		}
		 }
		document := PolicyDocument{ format: 1, architecture: 'aarch64', policy: PolicySettings{ pins: pins } }
		bad := PolicyDocument{ format: 2 }
		bad_utf8 := PolicyDocument{ format: 1, architecture: '\xff' }
		semantic := PolicyDocument{ format: 1, architecture: 'unsupported' }
		C.vinix_heap_begin()
		for _ in 0 .. 1000 {
			policy_writer_roundtrip(&document)
			policy_writer_refused(&bad)
			policy_writer_refused(&bad_utf8)
			text := semantic.encode()!
			mut refused := decode_policy_document(text) or {
				unsafe {
					err.free()
					text.free()
				}
				continue
			}
			refused.close()
			unsafe { text.free() }
			panic('semantic response accepted')
		}
		policy_writer_require(C.vinix_heap_end() == 0 && C.vinix_heap_count() == 0)
		println('POLICY WRITER 1000 encode/decode/refusal/double-close cycles with 256 pins retain zero tracked bytes PASS')
	}
}
