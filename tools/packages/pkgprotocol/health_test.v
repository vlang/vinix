// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import json2

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn health_protocol_fixture(count int) HealthReport {
	mut rows := []PackageHealth{cap: count}
	for index in 0 .. count {
		rows << PackageHealth{ id: 'app-' + (10000 + index).str(), name: 'Editor é🚀', version: '1.0.0', kind: 'native',
			repository: 'trusted', public_key: 'a'.repeat(64), issue: if index % 2 == 0 { 'payload' } else { '' },
			diagnostic: if index % 2 == 0 { 'Installed payload failed verification: bin/app' } else { '' } }
	}
	return HealthReport{ generation: 7, architecture: 'aarch64', rows: rows }
}

fn test_health_reports_require_complete_typed_canonical_and_coherent_rows() {
	text := json2.encode(health_protocol_fixture(32))
	mut decoded := decode_health(text)!
	assert decoded.rows.len == 32 && decoded.rows[0].issue == 'payload' && decoded.generation == 7
	decoded.close(); decoded.close()
	for bad in [text + '{}', text[..text.len - 1], text.replace('"format":1', '"format":2'),
		text.replace('"format":1', '"format":true'), text.replace('"generation":7', '"generation":-1'),
		text.replace('"generation":7', '"generation":07'), text.replace('"generation":7', '"generation":0'),
		text.replace('"generation":7', '"generation":18446744073709551616'),
		text.replace('"architecture":"aarch64"', '"architecture":null'),
		text.replace('"format":1', '"format":1,"extra":{}'), text.replace('"format":1', '"format":1,"forma\\u0074":1'),
		text.replace(',"diagnostic":""', ''), text.replace('"issue":"payload"', '"issue":"trusted"'),
		text.replace('"issue":"payload"', '"issue":""'), text.replace('"issue":""', '"issue":"payload"'),
		text.replace('"kind":"native"', '"kind":"runtime"').replace('"issue":"payload"', '"issue":"registration"'),
		text.replace('"issue":"payload"', '"issue":"payload","iss\\u0075e":""'),
		text.replace('app-10001', 'app-10000'), text.replace('app-10001', 'app-09999'),
		text.replace('Editor é🚀', 'x'.repeat(257)), text.replace('bin/app', 'x'.repeat(385)),
		text.replace('Editor é🚀', 'bad\\nname'), text.replace('Editor é🚀', '\xff'),
		text.replace('"rows":[', '"rows":null,"ignored":[')] {
		mut refused := false
		decode_health(bad) or { refused = true; message := err.msg(); unsafe { message.free(); err.free() } }
		assert refused, bad[..if bad.len > 128 { 128 } else { bad.len }]
	}
	mut empty := decode_health('{"format":1,"generation":0,"architecture":"x86_64","rows":[]}')!
	empty.close()
	println('HEALTH PROTOCOL complete typed fields, escaped duplicate/unknown keys, canonical numbers, sorted unique rows, issue coherence, UTF-8 and bounds PASS')
}

fn test_maximum_health_report_fits_the_reply_bound_and_decoder_retires_partial_rows() {
	base := health_protocol_fixture(4096)
	wide := HealthReport{ ...base, rows: base.rows.map(PackageHealth{ ...it,
		id: 'a'.repeat(119) + it.id, name: '"'.repeat(256), version: '999999999.999999999.999999999', kind: 'windows',
		repository: 'a'.repeat(128), diagnostic: '\\'.repeat(384), issue: 'namespace' }) }
	text := json2.encode(wide)
	assert text.len < 8 * 1024 * 1024
	mut decoded := decode_health(text)!; assert decoded.rows.len == 4096; decoded.close()
	too_many := json2.encode(health_protocol_fixture(4097))
	if _ := decode_health(too_many) { assert false }
	println('HEALTH PROTOCOL 4096 maximally escaped rows fit the reply bound; excess rows refuse PASS')
	$if track_heap ? {
		small := json2.encode(health_protocol_fixture(32))
		bad := small[..small.len - 1] + ',"extra":{}}'
		C.vinix_heap_begin()
		for _ in 0 .. 1000 {
			mut report := decode_health(small)!; report.close()
			decode_health(bad) or { message := err.msg(); unsafe { message.free(); err.free() } }
		}
		kept := C.vinix_heap_end(); assert kept == 0, 'health decoder retained ${kept} bytes'
		println('HEALTH PROTOCOL 1000 complete and partial-invalid decode/retirement cycles retain zero tracked bytes PASS')
	}
}
