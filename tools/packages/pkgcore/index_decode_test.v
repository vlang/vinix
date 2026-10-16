// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import strings
import tools.packages.signing

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn index_decode_package(id string, architecture string) Package {
	return Package{ id: id, architecture: architecture, version: '1.0.0', name: 'Catalog é🚀',
		description: 'Quotes "firmware":false and brackets [] {}', homepage: 'https://example.invalid',
		license: 'MIT', kind: 'native', entrypoint: 'bin/app', arguments: ['--title="Catalog"'],
		permissions: ['display', 'files'], associations: ['text/plain'], window_protocol: 2,
		dependencies: [Dependency{ id: 'data', minimum: '1.0.0', before: '2.0.0' }],
		files: [Payload{ path: 'bin/app', sha256: 'a'.repeat(64), bytes: 1, executable: true }] }
}

fn index_decode_refusal(text string) {
	if value := decode_signed_index('fixture', text, 1900000000) { close_decoded_index(value); assert false }
	else { message := err.msg(); assert message != ''; unsafe { message.free(); err.free() } }
}

fn index_decode_selected(selection string) bool {
	return os.args.len != 3 || os.args[1] != '--index-case' || os.args[2] == selection
}

// Build large input without retaining the generic encoder's per-record scratch.
fn index_decode_document(count int, architecture string) string {
	p := index_decode_package('app', architecture)
	defer { close_decoded_package(p) }
	template := json2.encode(p); defer { unsafe { template.free() } }
	start := template.index('"id":"app"') or { panic('fixture ID missing') }
	end := start + '"id":"app"'.len
	mut out := strings.new_builder(count * (template.len + 8) + 128)
	defer { unsafe { out.free() } }
	out.write_string('{"format":1,"repository":"fixture","sequence":18446744073709551615,"expires":9223372036854775807,"packages":[')
	for i in 0 .. count {
		if i > 0 { out.write_u8(`,`) }
		out.write_string(unsafe { tos(template.str, start) })
		out.write_string('"id":"app-')
		digits := i.str(); out.write_string(digits); unsafe { digits.free() }
		out.write_u8(`"`)
		out.write_string(unsafe { tos(template.str + end, template.len - end) })
	}
	out.write_string(']}')
	return out.str()
}

fn test_index_decode_retires_empty_and_growing_results_and_keeps_independent_fields() {
	if os.args.len == 3 && os.args[1] == '--index-case' && !os.args[2].starts_with('owned-') { return }
	cycles := $if track_heap ? { 1000 } $else { 64 }
	for architecture in ['aarch64', 'x86_64']! {
		for count in [0, 1, 64, 4096]! {
			if !index_decode_selected('owned-' + architecture + '-' + count.str()) { continue }
			text := index_decode_document(count, architecture)
			defer { unsafe { text.free() } }
			last_id := 'app-' + (count - 1).str()
			tracked := count != 4096 // Full declarations exceed the tracker's live-record table.
			$if track_heap ? { if tracked { C.vinix_heap_begin() } }
			for _ in 0 .. if tracked { cycles } else { 1 } {
				value := decode_signed_index('fixture', text, 1900000000)!
				assert value.packages.len == count && value.sequence == ~u64(0) && value.expires == max_i64
				if count > 0 {
					assert value.packages[count - 1].id == last_id && value.packages[count - 1].architecture == architecture
					assert value.packages[0].name == 'Catalog é🚀' && value.packages[0].window_protocol == 2
					assert value.packages[0].arguments[0] == '--title="Catalog"' && value.packages[0].dependencies[0].before == '2.0.0'
					assert value.packages[0].files[0].path == 'bin/app' && value.packages[0].files[0].executable
				}
				close_decoded_index(value)
			}
			$if track_heap ? { if tracked {
				kept := C.vinix_heap_end(); assert kept == 0
				println('INDEX DECODE ' + architecture + ' ' + count.str() + ' packages: 1000 cycles retained ' + kept.str() + ' bytes')
			} }
			if count == 4096 { continue }
			mut source := text.clone()
			first := decode_signed_index('fixture', source, 1900000000)!
			second := decode_signed_index('fixture', source, 1900000000)!
			assert first == second && first.repository.str != second.repository.str
			if count > 0 { assert first.packages.data != second.packages.data }
			close_decoded_index(first); unsafe { source.free() }; source = 'replaced'
			assert second.repository == 'fixture' && second.packages.len == count && source == 'replaced'
			assert json2.encode(second) == text
			if count > 0 { assert second.packages[count - 1].architecture == architecture && second.packages[0].name == 'Catalog é🚀' }
			close_decoded_index(second)
		}
	}
	println('INDEX DECODE both architectures, empty/growing owned results, full 4096 packages, retired source buffers and exact canonical declarations PASS')
}

fn test_index_decode_retires_partial_schema_numeric_utf8_and_validation_refusals() {
	if !index_decode_selected('refusals') { return }
	cycles := $if track_heap ? { 1000 } $else { 64 }
	p := index_decode_package('app', 'aarch64')
	text := json2.encode(Index{ repository: 'fixture', sequence: 1, expires: 2000000000, packages: [p] })
	duplicate := json2.encode(Index{ repository: 'fixture', sequence: 1, expires: 2000000000, packages: [p, p] })
	invalid_utf8 := [u8(0xc0), 0xaf].bytestr()
	inputs := ['{"format":1,', text[..text.len - 10], text + 'true', text.replace('"firmware":false,', ''),
		text.replace('"firmware":false', '"firmware":false,"firm\\u0077are":false'),
		text.replace('"files":', '"unknown":{},"files":'), text.replace('"permissions":["display","files"]', '"permissions":null'),
		text.replace('Catalog é🚀', invalid_utf8), text.replace('Catalog é🚀', '\\uD800'),
		text.replace('"sequence":1', '"sequence":0'), text.replace('"sequence":1', '"sequence":01'),
		text.replace('"sequence":1', '"sequence":1.0'), text.replace('"sequence":1', '"sequence":1e0'),
		text.replace('"sequence":1', '"sequence":-1'), text.replace('"sequence":1', '"sequence":18446744073709551616'),
		text.replace('"expires":2000000000', '"expires":9223372036854775808'),
		text.replace('"expires":2000000000', '"expires":-9223372036854775809'),
		text.replace('"expires":2000000000', '"expires":- 1'), text.replace('"expires":2000000000', '"expires":1900000000'),
		text.replace('"repository":"fixture"', '"repository":"other"'), text.replace('"path":"bin/app"', '"path":"../app"'),
		text.replace('"files":[', '"files":[null,'), duplicate]
	for number, input in inputs {
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. cycles { index_decode_refusal(input) }
		$if track_heap ? {
			kept := C.vinix_heap_end(); assert kept == 0, 'signed index refusal retained ' + kept.str()
			println('INDEX DECODE refusal ' + number.str() + ': 1000 cycles retained ' + kept.str() + ' bytes')
		}
	}
	for expiry in ['9223372036854775807', '-9223372036854775807', '-0']! {
		value := decode_signed_index('fixture', text.replace('"expires":2000000000', '"expires":' + expiry), min_i64)!
		assert value.expires > min_i64; close_decoded_index(value)
	}
	value := read_signed_index(text.replace('"expires":2000000000', '"expires":-9223372036854775808'))!
	assert value.expires == min_i64; close_decoded_index(value)
	println('INDEX DECODE partial/schema/UTF8/number/validation refusals retire scratch; full unsigned sequence and signed expiry ranges PASS')
}

fn test_index_decode_metadata_and_package_bounds_remain_explicit() {
	if !index_decode_selected('bounds') { return }
	text := json2.encode(Index{ repository: 'fixture', sequence: 1, expires: 2000000000 })
	for size in [max_metadata - 1, max_metadata]! {
		padded := text + ' '.repeat(size - text.len)
		value := decode_signed_index('fixture', padded, 1900000000)!
		assert value.packages.len == 0; close_decoded_index(value)
		unsafe { padded.free() }
	}
	index_decode_refusal(text + ' '.repeat(max_metadata + 1 - text.len))
	oversized := index_decode_document(4097, 'x86_64')
	index_decode_refusal(oversized)
	println('INDEX DECODE exact 8 MiB and limit-minus-one accepted; limit-plus-one and 4097 packages refused PASS')
}

fn index_decode_signature(private signing.PrivateKey, text string) !string {
	bytes := text.bytes(); defer { unsafe { bytes.free() } }
	signature := signing.sign(private, bytes)!; defer { unsafe { signature.free() } }
	return signature.hex()
}

fn test_index_decode_authenticates_original_bytes_and_retires_signed_refusals() {
	if !index_decode_selected('signed') { return }
	private := signing.new_key_from_seed([]u8{len: 32, init: 7})
	repository := Repository{ id: 'fixture', public_key: private.public_key().hex() }
	text := json2.encode(Index{ repository: 'fixture', sequence: 7, expires: 2000000000, packages: [index_decode_package('app', 'aarch64')] })
	legacy := ' \n' + text.replace('"sequence":7', '"sequ\\u0065nce":7') + '\t\n'
	for original in [text, legacy]! {
		signature := index_decode_signature(private, original)!
		tampered := original + ' '
		malformed := original.replace('"firmware":false,', '')
		malformed_signature := index_decode_signature(private, malformed)!
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. 64 {
			value := verify_index(repository, original, signature, 1900000000)!; assert value.sequence == 7; close_decoded_index(value)
			for invalid in ['not JSON', tampered, malformed]! {
				if decoded := verify_index(repository, invalid, signature, 1900000000) { close_decoded_index(decoded); assert false }
				else { message := err.msg(); assert message.contains('signature verification failed'); unsafe { message.free(); err.free() } }
			}
			if decoded := verify_index(repository, malformed, malformed_signature, 1900000000) { close_decoded_index(decoded); assert false }
			else { message := err.msg(); assert message.contains('missing required signed package field'); unsafe { message.free(); err.free() } }
		}
		$if track_heap ? {
			kept := C.vinix_heap_end(); assert kept == 0
			println('INDEX DECODE signed original/legacy: 64 cycles retained ' + kept.str() + ' bytes')
		}
		assert index_decode_signature(private, original)! == signature
	}
	println('INDEX DECODE authenticated original/legacy bytes, signature-before-schema refusals and 64-cycle signed retries retire scratch PASS')
}
