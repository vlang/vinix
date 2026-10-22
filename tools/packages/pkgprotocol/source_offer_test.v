// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import strings

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn source_fixture() string {
	return '{"format":1,"status":"local-qualification-only","source_closure_complete":false,"runtime":"org.vinix.wine-runtime","version":"9.17-r1","architecture":"aarch64","reason":"Incomplete corresponding source; local experiment only.","artifacts":[{"path":"runtime-LICENSE.txt","kind":"notice","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","url":"local:publisher"}]}'
}

fn source_refused(text string) bool {
	mut offer := decode_local_source_offer(text) or { unsafe { err.free() }; return true }
	offer.close()
	return false
}

fn test_local_source_offer_scope_types_bounds_and_owned_fields() {
	text := source_fixture()
	mut owned := text.clone()
	mut offer := decode_local_source_offer(owned)!
	unsafe { owned.free() }
	assert offer.runtime == 'org.vinix.wine-runtime' && offer.artifacts[0].path == 'runtime-LICENSE.txt'
	assert !offer.source_closure_complete && offer.status == 'local-qualification-only'
	offer.close(); offer.close()
	escaped := text.replace('"format":1', '"forma\\u0074":1').replace('Incomplete corresponding source; local experiment only.', '調査\\u0020\\ud83d\\udd12')
	mut unicode := decode_local_source_offer(escaped)!
	assert unicode.reason == '調査 🔒'
	unicode.close()
	unsafe { escaped.free() }
	mut bad := [text + '{}', text[..text.len - 1], '', '{}', '[]',
		text.replace('"format":1', '"format":2'), text.replace('"format":1', '"format":01'),
		text.replace('"format":1', '"format":1.0'), text.replace('"format":1', '"format":true'),
		text.replace('"format":1', '"format":1,"forma\\u0074":1'),
		text.replace('"format":1,', ''), text.replace('"format":1', '"format":1,"unknown":0'),
		text.replace('local-qualification-only', 'redistributable'),
		text.replace('"source_closure_complete":false', '"source_closure_complete":true'),
		text.replace('"source_closure_complete":false', '"source_closure_complete":"false"'),
		text.replace('"source_closure_complete":false', '"source_closure_complete":null'),
		text.replace('org.vinix.wine-runtime', ''), text.replace('org.vinix.wine-runtime', '../wine'),
		text.replace('9.17-r1', 'bad version'), text.replace('aarch64', 'all'),
		text.replace('Incomplete corresponding source; local experiment only.', ''),
		text.replace('Incomplete corresponding source; local experiment only.', 'bad\\u0000scope'),
		text.replace('runtime-LICENSE.txt', '../notice'), text.replace('runtime-LICENSE.txt', '.hidden'),
		text.replace('runtime-LICENSE.txt', 'sub/notice'), text.replace('runtime-LICENSE.txt', 'source-offer.json'),
		text.replace('runtime-LICENSE.txt', 'bad\\\\name'), text.replace('runtime-LICENSE.txt', ''),
		text.replace('"kind":"notice"', '"kind":"binary"'),
		text.replace('"kind":"notice"', '"kind":"source"'),
		text.replace('"path":"runtime-LICENSE.txt"', '"path":"runtime-LICENSE.txt","pa\\u0074h":"other"'),
		text.replace('"url":"local:publisher"', '"url":"http://example.invalid/source"'),
		text.replace('"url":"local:publisher"', '"url":"https://"'),
		text.replace('"url":"local:publisher"', '"url":"https://example.invalid/bad path"'),
		text.replace('"url":"local:publisher"', '"url":"https://example.invalid/bad\\npath"'),
		text.replace('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'A'.repeat(64)),
		text.replace('aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'a'.repeat(63)),
		text.replace('"artifacts":[{', '"artifacts":[null,{'), text.replace('"artifacts":[{', '"artifacts":[{}, {'),
		text.replace('"artifacts":[{', '"artifacts":[{"unknown":1}, {'),
		text.replace('"reason":', '"reason":null,"reason":'),
		text.replace('Incomplete corresponding source; local experiment only.', 'x'.repeat(4097)),
		' '.repeat(256 * 1024 + 1)]
	defer { unsafe { bad.free() } }
	for value in bad { assert source_refused(value) }
	// Every partially decoded refusal is checked under the real manual-free
	// allocator too; no generic JSON decoder or per-case warmup masks retention.
	$if track_heap ? {
		for value in bad {
			C.vinix_heap_begin()
			for _ in 0 .. 1000 { assert source_refused(value) }
			kept := C.vinix_heap_end(); assert kept == 0, kept.str()
		}
		C.vinix_heap_begin()
		for _ in 0 .. 1000 {
			mut decoded := decode_local_source_offer(text)!
			decoded.close(); decoded.close()
		}
		kept := C.vinix_heap_end(); assert kept == 0, kept.str()
		println('LOCAL SOURCE OFFER tracked success and ' + bad.len.str() + ' refusal paths x1000 retain zero bytes PASS')
	}
	println('LOCAL SOURCE OFFER local-only scope, strict schema, bounds, Unicode and independent ownership PASS')
}

fn test_local_source_offer_artifact_count_duplicates_and_growth() {
	text := source_fixture()
	start := text.index('[{') or { panic('missing fixture artifacts') }
	artifact := text[start + 1..text.len - 2]
	defer { unsafe { artifact.free() } }
	empty := text[..start] + '[]}'
	defer { unsafe { empty.free() } }
	assert source_refused(empty)
	duplicate := text[..text.len - 2] + ',' + artifact + ']}'
	defer { unsafe { duplicate.free() } }
	assert source_refused(duplicate)
	mut builder := strings.new_builder(64 * 1024)
	defer { unsafe { builder.free() } }
	builder.write_string(text[..start + 1])
	for index in 0 .. 256 {
		if index > 0 { builder.write_u8(`,`) }
		name := index.str()
		row := artifact.replace('runtime-LICENSE.txt', name + '.txt')
		builder.write_string(row)
		unsafe { row.free(); name.free() }
	}
	builder.write_string(']}')
	maximum := builder.str()
	defer { unsafe { maximum.free() } }
	mut decoded := decode_local_source_offer(maximum)!
	assert decoded.artifacts.len == 256 && decoded.artifacts[255].path == '255.txt'
	decoded.close()
	overflow := maximum[..maximum.len - 2] + ',' + artifact + ']}'
	defer { unsafe { overflow.free() } }
	assert source_refused(overflow)
	$if track_heap ? {
		C.vinix_heap_begin()
		for _ in 0 .. 100 {
			mut repeated := decode_local_source_offer(maximum)!
			repeated.close()
			assert source_refused(overflow)
			assert source_refused(duplicate)
		}
		kept := C.vinix_heap_end(); assert kept == 0, kept.str()
	}
	println('LOCAL SOURCE OFFER 256 unique artifacts, growth cleanup, duplicate/count refusal PASS')
}
