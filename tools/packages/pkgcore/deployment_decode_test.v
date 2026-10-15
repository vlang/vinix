// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

const deployment_decode_fixture = '{"format":2,"architecture":"aarch64","packages":["runtime","app"],"locked":[{"id":"runtime","version":"1.0.0","architecture":"all","repository":"publisher","public_key":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","minimum_sequence":18446744073709551615,"metadata_sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},{"id":"app","version":"2.0.0","architecture":"aarch64","repository":"publisher","public_key":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","minimum_sequence":1,"metadata_sha256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"}]}'
const deployment_roots_fixture = '{"format":1,"architecture":"x86_64","packages":["runtime","app"]}'

fn test_deployment_decode_owns_sorted_fields_and_preserves_source_bytes() {
	mut text := deployment_decode_fixture.clone()
	mut document := decode_deployment(text, 'aarch64')!
	assert text == deployment_decode_fixture
	unsafe { text.free() }
	assert document.format == 2 && document.architecture == 'aarch64'
	assert document.packages == ['app', 'runtime'] && document.locked[0].id == 'app'
	assert document.locked[1].architecture == 'all' && document.locked[1].minimum_sequence == ~u64(0)
	document.close(); document.close()
	assert document.architecture == '' && document.packages.len == 0 && document.locked.len == 0
	mut roots := decode_deployment(deployment_roots_fixture, 'x86_64')!
	assert roots.format == 1 && roots.packages == ['app', 'runtime'] && roots.locked.len == 0
	roots.close()
}

fn deployment_decode_invalid() []string {
	return [
		'', '[]', 'null', '{}', '{', deployment_decode_fixture + 'false',
		deployment_decode_fixture.replace('"format":2', '"format":0'),
		deployment_decode_fixture.replace('"format":2', '"format":3'),
		deployment_decode_fixture.replace('"format":2', '"format":"2"'),
		deployment_decode_fixture.replace('"format":2', '"format":2.0'),
		deployment_decode_fixture.replace('"format":2', '"format":2e0'),
		deployment_decode_fixture.replace('"format":2,', ''),
		deployment_decode_fixture.replace('"format":2', '"format":2,"f\\u006frmat":2'),
		deployment_decode_fixture.replace('"packages":["runtime","app"]', '"packages":null'),
		deployment_decode_fixture.replace('"packages":["runtime","app"]', '"packages":["app",null]'),
		deployment_decode_fixture.replace('"packages":["runtime","app"]', '"packages":["app","app"]'),
		deployment_decode_fixture.replace('"packages":["runtime","app"]', '"packages":["App"]'),
		deployment_decode_fixture.replace('"locked":[', '"unknown":['),
		deployment_decode_fixture.replace('"locked":[', '"locked":[null,'),
		deployment_decode_fixture.replace('"id":"app"', '"id":"runtime"'),
		deployment_decode_fixture.replace('"id":"app"', '"id":"app","i\\u0064":"app"'),
		deployment_decode_fixture.replace('"id":"app"', '"id":"app","unknown":"value"'),
		deployment_decode_fixture.replace('"id":"app"', '"id":"\\ud800"'),
		deployment_decode_fixture.replace('"id":"app"', '"id":"\\udc00"'),
		deployment_decode_fixture.replace('"id":"app"', '"id":"bad\\x20"'),
		deployment_decode_fixture.replace('"version":"2.0.0"', '"version":"01.0.0"'),
		deployment_decode_fixture.replace('"version":"2.0.0"', '"version":"1.0"'),
		deployment_decode_fixture.replace('"version":"2.0.0"', '"version":"1.x.0"'),
		deployment_decode_fixture.replace('"version":"2.0.0"', '"version":"9999999999.0.0"'),
		deployment_decode_fixture.replace('"architecture":"all"', '"architecture":"x86_64"'),
		deployment_decode_fixture.replace('"repository":"publisher"', '"repository":"Publisher"'),
		deployment_decode_fixture.replace('"minimum_sequence":1,', '"minimum_sequence":0,'),
		deployment_decode_fixture.replace('"minimum_sequence":1,', '"minimum_sequence":null,'),
		deployment_decode_fixture.replace('"minimum_sequence":1,', '"minimum_sequence":-1,'),
		deployment_decode_fixture.replace('"minimum_sequence":1,', '"minimum_sequence":"1",'),
		deployment_decode_fixture.replace('"minimum_sequence":1,', '"minimum_sequence":01,'),
		deployment_decode_fixture.replace('"minimum_sequence":1,', '"minimum_sequence":1.0,'),
		deployment_decode_fixture.replace('"minimum_sequence":1,', '"minimum_sequence":1e0,'),
		deployment_decode_fixture.replace('"minimum_sequence":1,', '"minimum_sequence":18446744073709551616,'),
		deployment_decode_fixture.replace('"minimum_sequence":1,', ''),
		deployment_decode_fixture.replace('"metadata_sha256":"cccc', '"metadata_sha256":"CCCC'),
		deployment_decode_fixture.replace('"metadata_sha256":"cccc', '"metadata_sha256":"'),
		deployment_decode_fixture.replace('"architecture":"aarch64"', '"architecture":"invalid"'),
		deployment_decode_fixture.replace('"id":"app"', '"id":"' + 'a'.repeat(129) + '"'),
		deployment_decode_fixture.replace('"id":"app"', '"id":"a\nb"'),
		deployment_decode_fixture.replace('"id":"app"', '"id":"a' + [u8(0xff)].bytestr() + '"'),
		deployment_decode_fixture.replace('"locked":[', '"locked":[[],'),
		deployment_decode_fixture.replace('"locked":[', '"locked":[true,'),
		deployment_roots_fixture.replace('"packages":["runtime","app"]', '"packages":[] ,"locked":[]'),
		deployment_roots_fixture.replace('"packages":["runtime","app"]', '"packages":["app",]'),
		deployment_roots_fixture.replace('"packages":["runtime","app"]', '"packages":[["app"]]'),
		deployment_roots_fixture.replace('"packages":["runtime","app"]', '"packages":["app"] ,'),
	]
}

fn test_deployment_decode_rejects_partial_coerced_duplicate_and_invalid_documents() {
	for invalid in deployment_decode_invalid() {
		if mut document := decode_deployment(invalid, if invalid.contains('x86_64') { 'x86_64' } else { 'aarch64' }) {
			document.close(); assert false, invalid
		} else { unsafe { err.free() } }
	}
	// Every truncated prefix must refuse and retire its partially read fields.
	for end in 0 .. deployment_decode_fixture.len {
		prefix := unsafe { tos(deployment_decode_fixture.str, end) }
		if mut document := decode_deployment(prefix, 'aarch64') { document.close(); assert false } else { unsafe { err.free() } }
	}
	for format in [1, 2]! {
		text := if format == 1 { '{"packages":[],"architecture":"aarch64","format":1}' }
			else { '{"locked":[],"packages":[],"architecture":"x86_64","format":2}' }
		mut document := decode_deployment(text, if format == 1 { 'aarch64' } else { 'x86_64' })!
		assert document.packages.len == 0 && document.locked.len == 0; document.close()
	}
	escaped := deployment_decode_fixture.replace('"format"', '"f\\u006frmat"').replace('"id":"app"', '"id":"\\u0061pp"')
	mut document := decode_deployment(escaped, 'aarch64')!
	assert document.locked[0].id == 'app'; document.close()
	println('Deployment decode: formats 1/2, both architectures, empty/reordered/escaped fields, strict scalar/schema and all truncated prefixes PASS')
}

fn deployment_decode_large(count int, pins bool) string {
	mut roots := []string{cap: count}
	mut locked := []DeploymentPackage{cap: if pins { count } else { 0 }}
	for index in 0 .. count {
		number := index.str(); id := 'app-' + number
		unsafe { number.free(); roots.push_many(&id, 1) }
		if pins {
			locked << DeploymentPackage{ id: id, version: '1.0.0', architecture: 'all', repository: 'publisher',
				public_key: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', minimum_sequence: 1,
				metadata_sha256: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' }
		}
	}
	encoded := if pins { json2.encode(DeploymentLock{ architecture: 'aarch64', packages: roots, locked: locked }) }
		else { json2.encode(roots) }
	text := if pins { encoded.clone() } else { '{"format":1,"architecture":"aarch64","packages":' + encoded + '}' }
	unsafe { encoded.free(); for id in roots { id.free() }; (&array(&roots)).free(); locked.free() }
	return text
}

fn test_deployment_decode_bounds_roots_pins_and_input_before_unbounded_growth() {
	for pins in [false, true]! {
		text := deployment_decode_large(4096, pins)
		mut document := decode_deployment(text, 'aarch64')!
		assert document.packages.len == 4096 && document.locked.len == if pins { 4096 } else { 0 }
		document.close(); unsafe { text.free() }
		invalid := deployment_decode_large(4097, pins)
		if mut accepted := decode_deployment(invalid, 'aarch64') { accepted.close(); assert false } else { unsafe { err.free() } }
		unsafe { invalid.free() }
	}
	// Isolate the pin limit from the independent requested-root limit.
	too_many := deployment_decode_large(4097, true)
	start := too_many.index('"locked":') or { panic('missing fixture pins') }
	invalid := '{"format":2,"architecture":"aarch64","packages":[],' + too_many[start..]
	if mut accepted := decode_deployment(invalid, 'aarch64') { accepted.close(); assert false } else { unsafe { err.free() } }
	unsafe { invalid.free(); too_many.free() }
	large := deployment_decode_fixture + ' '.repeat(max_metadata)
	if mut accepted := decode_deployment(large, 'aarch64') { accepted.close(); assert false } else { unsafe { err.free() } }
	unsafe { large.free() }
}

fn test_deployment_decode_retires_success_and_refusal_allocations() {
	$if track_heap ? {
		invalid := deployment_decode_invalid()
		// The tracker has 16,384 live slots; a maximum closure legitimately
		// owns more strings. Measure pin growth at 512 and roots at their limit.
		large := deployment_decode_large(512, true)
		wide := deployment_decode_large(4096, false)
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				mut document := decode_deployment(deployment_decode_fixture, 'aarch64')!
				document.close()
				mut roots := decode_deployment(deployment_roots_fixture, 'x86_64')!
				roots.close()
				for text in invalid {
					if mut result := decode_deployment(text, 'aarch64') { result.close(); assert false } else {
						message := err.msg(); assert message != ''
						unsafe { message.free(); err.free() }
					}
				}
			}
			for _ in 0 .. 4 {
				mut maximum := decode_deployment(large, 'aarch64')!
				assert maximum.locked.len == 512; maximum.close()
				mut roots_maximum := decode_deployment(wide, 'aarch64')!
				assert roots_maximum.packages.len == 4096; roots_maximum.close()
			}
			for end in 0 .. deployment_decode_fixture.len {
				prefix := unsafe { tos(deployment_decode_fixture.str, end) }
				if mut result := decode_deployment(prefix, 'aarch64') { result.close(); assert false } else { unsafe { err.free() } }
			}
		}
		kept := C.vinix_heap_end()
		println('Deployment decode: 1000 format-1/2 success/refusal cycles, pin-512/root-4096 growth and all truncated prefixes retained ${kept} bytes')
		assert kept == 0
		unsafe { for text in invalid { text.free() }; (&array(&invalid)).free(); large.free(); wide.free() }
	}
}
