// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import json2

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

fn protocol_policy() PolicySettings {
	return PolicySettings{ offline: true, allowed: ['app', 'runtime'], pins: [PolicyPin{ id: 'runtime', minimum: '1.0.0', before: '2.0.0' }],
		permissions: ['display', 'files'], licenses: ['Vendor «license» {"pins":"text"}'], allow_firmware: true, reserve_bytes: 65536 }
}

fn protocol_policy_review() PolicyReview {
	return PolicyReview{ format: 1, architecture: 'aarch64', generation: 2, fingerprint: 'a'.repeat(64),
		previous: protocol_policy(), proposed: PolicySettings{}, rows: [
		PolicyImpact{ id: 'app', name: 'Editor', version: '1.0.0', kind: 'native', license: 'MIT', repository: 'fixture', public_key: 'b'.repeat(64), requested: true, diagnostic_after: 'runtime: permissions blocked by organization policy' },
		PolicyImpact{ id: 'runtime', name: 'Shared Runtime', version: '1.0.0', kind: 'runtime', license: 'Vendor', proprietary: true, firmware: true, repository: 'fixture', public_key: 'b'.repeat(64), diagnostic_after: 'runtime: permissions blocked by organization policy' }] }
}

fn test_policy_decoding_retires_owned_metadata_on_success_and_refusal() {
	document := json2.encode(PolicyDocument{ format: 1, architecture: 'aarch64', policy: protocol_policy() })
	review := json2.encode(protocol_policy_review())
	documents := [document, document.replace('"before":"2.0.0"', '"before":false'),
		document.replace('"before":"2.0.0"', '"before":"1.0.0"'), document + ' trailing']!
	reviews := [review, review.replace('"name":"Shared Runtime"', '"name":false'),
		review.replace('"generation":2', '"generation":0'), review + ' trailing']!
	for invalid in documents[1..] { assert invalid != document }
	for invalid in reviews[1..] { assert invalid != review }
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 64 {
		for index, input in documents {
			mut decoded := decode_policy_document(input) or { unsafe { err.free() }; assert index != 0; continue }
			assert index == 0
			decoded.close()
		}
		for index, input in reviews {
			mut decoded := decode_policy_review(input) or { unsafe { err.free() }; assert index != 0; continue }
			assert index == 0
			decoded.close()
		}
	}
	$if track_heap ? {
		kept := C.vinix_heap_end()
		count := C.vinix_heap_count()
		println('POLICY DECODERS retained ${kept} bytes / ${count} allocations across 512 attempts')
		assert kept == 0 && count == 0
	}
}

fn test_policy_document_and_review_are_complete_owned_canonical_presentations() {
	doc := PolicyDocument{ format: 1, architecture: 'aarch64', policy: protocol_policy() }
	mut document := decode_policy_document(json2.encode(doc))!
	assert document.policy.allowed == ['app', 'runtime'] && document.policy.allow_firmware && document.policy.offline
	assert document.policy.licenses == doc.policy.licenses
	document.close(); assert document.format == 0 && document.policy.allowed.len == 0
	mut review := decode_policy_review(json2.encode(protocol_policy_review()))!
	assert review.rows.len == 2 && review.rows[1].proprietary && review.rows[1].firmware && !review.rows[1].requested
	assert review.rows[0].diagnostic_after.contains('runtime:') && review.proposed.permissions.len == 0
	assert review.previous.pins[0].before == '2.0.0'
	review.close(); review.close()
	assert review.rows.len == 0 && review.fingerprint == ''
}

fn test_policy_decoder_refuses_missing_coerced_unknown_duplicate_and_noncanonical_fields() {
	valid := json2.encode(PolicyDocument{ format: 1, architecture: 'aarch64', policy: protocol_policy() })
	for bad in [valid.replace('"offline":true,', ''), valid.replace('"offline":true', '"offline":"true"'),
		valid.replace('"reserve_bytes":65536', '"reserve_bytes":-1'), valid.replace('"reserve_bytes":65536', '"reserve_bytes":1.0'),
		valid.replace('"reserve_bytes":65536', '"reserve_bytes":1099511627777'),
		valid.replace('"allowed":["app","runtime"]', '"allowed":["runtime","app"]'),
		valid.replace('"allowed":["app","runtime"]', '"allowed":["app","app"]'),
		valid.replace('"permissions":["display","files"]', '"permissions":["unknown"]'),
		valid.replace('"minimum":"1.0.0"', '"minimum":"2.0.0"'),
		valid.replace('"minimum":"1.0.0"', '"minimum":"01.0.0"'),
		valid.replace('"format":1', '"format":1,"format":1'),
		valid.replace('"offline":true', '"offline":true,"off\\u006cine":false'),
		valid.replace('"id":"runtime"', '"id":"runtime","unknown":true'), valid + ' trailing'] {
		mut refused := false
		mut document := decode_policy_document(bad) or { refused = true; unsafe { err.free() }; PolicyDocument{} }
		document.close(); assert refused, bad
	}
	text := json2.encode(protocol_policy_review())
	for bad in [text.replace('"proprietary":false,', ''), text.replace('"firmware":false,', ''),
		text.replace('"diagnostic_before":"",', ''), text.replace('"requested":true,', ''),
		text.replace('"generation":2', '"generation":0'), text.replace('"generation":2', '"generation":18446744073709551616'),
		text.replace('"generation":2', '"generation":02'), text.replace('"public_key":"', '"public_key":"invalid'),
		text.replace('"name":"Editor"', '"name":"\\ud800"'), text.replace('"name":"Editor"', '"name":"\xff"'),
		text.replace('"id":"app"', '"id":"app","id":"app"'), text.replace('"architecture":"aarch64"', '"architecture":"unknown"')] {
		mut refused := false
		mut review := decode_policy_review(bad) or { refused = true; unsafe { err.free() }; PolicyReview{} }
		review.close(); assert refused, bad
	}
}

fn test_policy_reader_bounds_arrays_and_scalar_strings_before_returning_rows() {
	mut values := []string{cap: 4097}
	for index in 0 .. 4097 { values << 'app-' + index.str() }
	values.sort()
	text := json2.encode(PolicyDocument{ format: 1, architecture: 'aarch64', policy: PolicySettings{ allowed: values } })
	mut refused := false
	decode_policy_document(text) or { refused = true }
	assert refused
	for policy in [PolicySettings{ permissions: ['audio', 'display', 'files', 'network', 'process', 'unknown'] },
		PolicySettings{ licenses: ['x'.repeat(257)] }, PolicySettings{ pins: [PolicyPin{ id: 'app', before: '1.0.0', minimum: '1.0.0' }] }] {
		mut bad := false
		decode_policy_document(json2.encode(PolicyDocument{ format: 1, architecture: 'aarch64', policy: policy })) or { bad = true }
		assert bad
	}
	wide := PolicyDocument{ format: 1, architecture: 'x86_64', policy: PolicySettings{ allowed: values[..32], pins: []PolicyPin{len: 0} } }
	mut document := decode_policy_document(json2.encode(wide))!
	assert document.policy.allowed.len == 32 && document.architecture == 'x86_64'
	document.close()
}
