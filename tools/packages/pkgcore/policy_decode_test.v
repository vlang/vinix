// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import strings

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn policy_decode_selected(selection string) bool {
	return os.args.len != 3 || os.args[1] != '--policy-decode-case' || os.args[2] == selection
}

// Stream full bounds without retaining generic fixture encoder temporaries in
// the manual-free guest. Small results also round-trip through the public writer.
fn policy_decode_settings(count int) string {
	mut out := strings.new_builder(count * 160 + 256)
	defer { unsafe { out.free() } }
	out.write_string('{"offline":true,"allowed":[')
	for section in 0 .. 3 {
		for i in 0 .. count {
			if i > 0 { out.write_u8(`,`) }
			digits := (10000 + i).str(); defer { unsafe { digits.free() } }
			out.write_string(if section == 1 { '{"id":"item-' } else { '"item-' })
			out.write_string(digits)
			out.write_string(if section == 1 { '","minimum":"1.0.0","before":"2.0.0"}' } else { '"' })
		}
		out.write_string(match section {
			0 { '],"pins":[' }
			1 { '],"permissions":["files","network"],"licenses":[' }
			else { '],"allow_firmware":false,"reserve_bytes":0}' }
		})
	}
	return out.str()
}

fn policy_decode_document(count int, architecture string) string {
	settings := policy_decode_settings(count); defer { unsafe { settings.free() } }
	return '{"format":1,"architecture":"' + architecture + '","policy":' + settings + '}'
}

fn policy_decode_review(count int, architecture string) string {
	settings := policy_decode_settings(1); defer { unsafe { settings.free() } }
	row := PolicyImpact{ id: 'item-10000', name: 'Data é🚀', version: '1.0.0', kind: 'data', license: 'MIT',
		proprietary: true, firmware: true, repository: 'fixture', public_key: 'a'.repeat(64), requested: false,
		diagnostic_before: 'Quoted "rows":[] and braces {}', diagnostic_after: 'policy block' }
	encoded := json2.encode(row); defer { unsafe { encoded.free(); row.public_key.free() } }
	tail := encoded.index(',"name":') or { panic('fixture name missing') }
	mut out := strings.new_builder(encoded.len * count + settings.len * 2 + 256)
	defer { unsafe { out.free() } }
	out.write_string('{"format":1,"architecture":"'); out.write_string(architecture)
	out.write_string('","generation":'); out.write_string(if count == 0 { '0' } else { '1' })
	out.write_string(',"fingerprint":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","previous":')
	out.write_string(settings); out.write_string(',"proposed":'); out.write_string(settings)
	out.write_string(',"rows":[')
	for i in 0 .. count {
		if i > 0 { out.write_u8(`,`) }
		digits := (10000 + i).str(); defer { unsafe { digits.free() } }
		out.write_string('{"id":"item-'); out.write_string(digits); out.write_u8(`"`)
		out.write_string(unsafe { tos(encoded.str + tail, encoded.len - tail) })
	}
	out.write_string(']}')
	return out.str()
}

fn policy_decode_refusal(text string, review bool) {
	if review {
		if mut value := decode_policy_review(text) { value.close(); assert false }
		else { message := err.msg(); assert message != ''; unsafe { message.free(); err.free() } }
	} else {
		if mut value := decode_policy_document(text, 'aarch64') { value.close(); assert false }
		else { message := err.msg(); assert message != ''; unsafe { message.free(); err.free() } }
	}
}

fn test_policy_decode_independent_owned_documents_and_reviews() {
	if os.args.len == 3 && os.args[1] == '--policy-decode-case' && !os.args[2].starts_with('owned-') { return }
	root := os.temp_dir() + '/vinix-policy-decode-' + os.getpid().str()
	os.mkdir_all(root)!; defer { os.rmdir_all(root) or {} }
	path := root + '/policy.json'
	for architecture in ['aarch64', 'x86_64']! {
		for count in [1, 64, 4096]! {
			if !policy_decode_selected('owned-' + architecture + '-' + count.str()) { continue }
			document := policy_decode_document(count, architecture); review := policy_decode_review(count, architecture)
			defer { unsafe { document.free(); review.free() } }
			os.write_file(path, document)!
			tracked := count != 4096
			cycles := if tracked { $if track_heap ? { 1000 } $else { 64 } } else { 1 }
			$if track_heap ? { if tracked { C.vinix_heap_begin() } }
			for _ in 0 .. cycles {
				mut policy := read_policy_document(path, architecture)!
				assert policy.format == 1 && policy.architecture == architecture && policy.policy.pins.len == count
				assert policy.policy.allowed.len == count && policy.policy.licenses.len == count && policy.policy.pins.last().before == '2.0.0'
				assert policy.policy.offline && policy.policy.permissions.len == 2 && policy.policy.reserve_bytes == 0
				policy.close(); policy.close()
				mut value := decode_policy_review(review)!
				assert value.rows.len == count && value.architecture == architecture && value.generation == 1
				last := value.rows[count - 1]
				assert last.name == 'Data é🚀' && last.proprietary && last.firmware && !last.requested
				assert last.diagnostic_before == 'Quoted "rows":[] and braces {}' && last.diagnostic_after == 'policy block'
				value.close(); value.close()
			}
			$if track_heap ? { if tracked {
				kept := C.vinix_heap_end(); assert kept == 0
				println('POLICY DECODE ' + architecture + ' ' + count.str() + ' entries: 1000 cycles retained ' + kept.str() + ' bytes')
			} }
			if !tracked { continue }
			source := review.clone(); mut first := decode_policy_review(source)!; mut second := decode_policy_review(source)!
			assert first == second && first.rows.data != second.rows.data && first.rows[0].name.str != second.rows[0].name.str
			assert first.previous.allowed.data != second.previous.allowed.data && first.previous.allowed.data != first.proposed.allowed.data
			first.close(); unsafe { source.free() }
			assert second.rows.last().name == 'Data é🚀' && json2.encode(second) == review; second.close()
			mut decoded := decode_policy_document(document, architecture)!
			assert json2.encode(decoded) == document; decoded.close()
		}
	}
	println('POLICY DECODE both architectures, owned independent file documents/reviews, repeated close, exact writer bytes and full 4096 bounds PASS')
}

fn test_policy_decode_compatibility_and_borrowed_validation() {
	if !policy_decode_selected('compatibility') { return }
	document := policy_decode_document(1, 'aarch64'); review := policy_decode_review(1, 'aarch64')
	cycles := $if track_heap ? { 1000 } $else { 64 }
	for input in [document, ' \n' + document + '\t', document.replace('"policy":', '"pol\\u0069cy":'), document.replace('"files","network"', '"network","files"')] {
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. cycles { mut value := decode_policy_document(input, 'aarch64')!; assert value.policy.permissions[0] == 'files'; value.close() }
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
		mut value := decode_policy_document(input, 'aarch64')!; assert json2.encode(value) == document; value.close()
	}
	for input in [document.replace(',"minimum":"1.0.0","before":"2.0.0"', ''), document.replace('"permissions":["files","network"]', '"permissions":[]'),
		document.replace('"reserve_bytes":0', '"reserve_bytes":1099511627776')] {
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. cycles { mut value := decode_policy_document(input, 'aarch64')!; value.close() }
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
	}
	legacy := read_stored_configuration('{"architecture":"aarch64"}')!
	assert legacy.policy.permissions.len == 5 && legacy.policy.reserve_bytes == 67108864; close_decoded_configuration(legacy)
	mut borrowed := decode_policy_review(review)!
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. cycles { borrowed.validate()! }
	$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
	assert json2.encode(borrowed) == review; borrowed.close()
	for input in [policy_decode_review(0, 'x86_64'), review.replace('"generation":1', '"generation":18446744073709551615'),
		review.replace(',"minimum":"1.0.0","before":"2.0.0"', ''), review.replace('"previous":', '"prev\\u0069ous":')] {
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. cycles { mut value := decode_policy_review(input)!; value.close() }
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
	}
	println('POLICY DECODE strict declarations preserve legacy defaults, optional pin ranges, canonical settings, empty permissions and full u64 generations; borrowed validation retires scratch PASS')
}

fn test_policy_decode_truncated_schema_and_semantic_refusals() {
	if !policy_decode_selected('refusals') { return }
	invalid_utf8 := [u8(0xc0), 0xaf].bytestr()
	for review in [false, true]! {
		text := if review { policy_decode_review(2, 'aarch64') } else { policy_decode_document(1, 'aarch64') }
		$if track_heap ? { C.vinix_heap_begin() }
		for end in 0 .. text.len { policy_decode_refusal(unsafe { tos(text.str, end) }, review) }
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
		mut inputs := [text + 'true', '{}', text.replace('"format":1', '"format":2147483648'), text.replace('"format":1', '"format":2'),
			text.replace('"format":1', '"format":1.0'), text.replace('"format":1', '"format":01'), text.replace('"architecture":"aarch64"', '"architecture":"other"'),
			text.replace('"format":1,', ''), text.replace('"offline":true', '"offline":null'), text.replace('"offline":true', '"offline":"true"'),
			text.replace('"offline":true', '"offline":true,"offl\\u0069ne":false'), text.replace('"offline":true', '"offline":true,"unknown":[]'),
			text.replace('"allowed":["item-10000"]', '"allowed":null'), text.replace('"pins":[', '"pins":[null,'),
			text.replace('"id":"item-10000",', ''), text.replace('"id":"item-10000"', '"id":null'), text.replace('"minimum":"1.0.0"', '"minimum":"3.0.0"'),
			text.replace('"permissions":["files","network"]', '"permissions":["files","files"]'), text.replace('"permissions":["files","network"]', '"permissions":["root"]'),
			text.replace('"licenses":["item-10000"]', '"licenses":["MIT","MIT"]'), text.replace('"reserve_bytes":0', '"reserve_bytes":1099511627777'),
			text.replace('"reserve_bytes":0', '"reserve_bytes":18446744073709551616'), text.replace('"reserve_bytes":0', '"reserve_bytes":-1'),
			text.replace('"reserve_bytes":0', '"reserve_bytes":1e0'), text.replace('"licenses":["item-10000"]', '"licenses":["' + invalid_utf8 + '"]'),
			text.replace('"licenses":["item-10000"]', '"licenses":["\\uD800"]')]
		for field in ['"offline":true,', '"allowed":["item-10000"],', '"pins":[{"id":"item-10000","minimum":"1.0.0","before":"2.0.0"}],',
			'"permissions":["files","network"],', '"licenses":["item-10000"],', '"allow_firmware":false,', ',"reserve_bytes":0'] { inputs << text.replace(field, '') }
		if review {
			inputs << [text.replace('"rows":[', '"rows":[null,'), text.replace('"generation":1', '"generation":0'),
				text.replace('"generation":1', '"generation":18446744073709551616'), text.replace('"fingerprint":"a', '"fingerprint":"z'),
				text.replace('"id":"item-10001"', '"id":"item-10000"'), text.replace('"version":"1.0.0"', '"version":"1.0"'),
				text.replace('"kind":"data"', '"kind":"unknown"'), text.replace('Data é🚀', invalid_utf8),
				text.replace('"diagnostic_after":"policy block"', '"diagnostic_after":"\\uD800"'), text.replace('"public_key":"a', '"public_key":"z'),
				text.replace('"requested":false', '"requested":null'), text.replace('"previous":{', '"previous":null,"unknown":{')]
			for field in ['"id":"item-10000",', '"name":"Data é🚀",', '"version":"1.0.0",', '"kind":"data",', '"license":"MIT",', '"proprietary":true,',
				'"firmware":true,', '"repository":"fixture",', '"public_key":"' + 'a'.repeat(64) + '",', '"requested":false,',
				'"diagnostic_before":"Quoted \\"rows\\":[] and braces {}",', ',"diagnostic_after":"policy block"'] { inputs << text.replace(field, '') }
		}
		cycles := $if track_heap ? { 1000 } $else { 64 }
		for number, input in inputs {
			assert input != text
			$if track_heap ? { C.vinix_heap_begin() }
			for _ in 0 .. cycles { policy_decode_refusal(input, review) }
			$if track_heap ? {
				kept := C.vinix_heap_end(); assert kept == 0
				println('POLICY DECODE refusal ' + review.str() + ' ' + number.str() + ': 1000 cycles retained ' + kept.str() + ' bytes')
			}
		}
	}
	println('POLICY DECODE every truncated prefix and required/schema/UTF8/number/late-row/semantic refusal retires scratch PASS')
}

fn test_policy_decode_metadata_collection_and_disclosure_bounds() {
	if !policy_decode_selected('bounds') { return }
	for review in [false, true]! {
		text := if review { policy_decode_review(1, 'aarch64') } else { policy_decode_document(1, 'aarch64') }
		for size in [max_metadata - 1, max_metadata]! {
			padding := ' '.repeat(size - text.len); padded := text + padding
			if review { mut value := decode_policy_review(padded)!; value.close() }
			else { mut value := decode_policy_document(padded, 'aarch64')!; value.close() }
			unsafe { padded.free(); padding.free() }
		}
		padding := ' '.repeat(max_metadata + 1 - text.len); oversized := text + padding
		policy_decode_refusal(oversized, review); unsafe { oversized.free(); padding.free() }
		for input in [text.replace('"permissions":["files","network"]', '"permissions":["audio","display","files","network","process","files"]'),
			text.replace('"allowed":["item-10000"]', '"allowed":["' + 'a'.repeat(257) + '"]'), text.replace('"licenses":["item-10000"]', '"licenses":["' + 'a'.repeat(257) + '"]')] { policy_decode_refusal(input, review) }
	}
	policy_decode_refusal(policy_decode_document(4097, 'aarch64'), false); policy_decode_refusal(policy_decode_review(4097, 'aarch64'), true)
	settings := policy_decode_settings(4097)
	allowed_end := settings.index('],"pins":') or { panic('missing pins') }; licenses_start := settings.index('"licenses":[') or { panic('missing licenses') }
	policy_decode_refusal('{"format":1,"architecture":"aarch64","policy":{"offline":true,"allowed":[],' + settings[allowed_end + 2..] + '}', false)
	policy_decode_refusal('{"format":1,"architecture":"aarch64","policy":{"offline":true,"allowed":[],"pins":[],"permissions":[],' + settings[licenses_start..] + '}', false)
	review := policy_decode_review(1, 'aarch64')
	for needle in ['Quoted \\"rows\\":[] and braces {}', 'policy block']! {
		value := 'd'.repeat(4096); full := review.replace(needle, value)
		assert full != review
		mut decoded := decode_policy_review(full)!; assert decoded.rows.len == 1; decoded.close()
		policy_decode_refusal(review.replace(needle, value + 'd'), true)
	}
	println('POLICY DECODE exact 8 MiB, 4096 collections/rows and 4096-byte diagnostics accepted; metadata/collection/grant/string/disclosure overflow refused PASS')
}
