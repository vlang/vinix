// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import json2

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn test_progress_has_bounded_typed_counters_and_owned_decoded_fields() {
	valid := Progress{ phase: 'download', package: 'app', repository: 'trusted', path: 'bin/app', current: 64, total: 128 }
	mut decoded := decode_progress(json2.encode(valid))!
	assert decoded == valid
	decoded.close()
	assert decoded.phase == '' && decoded.package == '' && decoded.path == ''
	for bad in [Progress{ ...valid, format: 2 }, Progress{ ...valid, phase: 'run' },
		Progress{ ...valid, current: 129 }, Progress{ ...valid, package: 'bad;command' },
		Progress{ ...valid, path: '../private' }, Progress{ ...valid, path: 'bin\napp' },
		Progress{ ...valid, total: u64(4) * 1024 * 1024 * 1024 + 1 },
		Progress{ ...valid, phase: 'activate' }, Progress{ phase: 'complete' },
		Progress{ phase: 'stage', total: 4097 }, Progress{ phase: 'metadata', repository: 'trusted', total: 1 }] {
		mut refused := false
		decode_progress(json2.encode(bad)) or { refused = true }
		assert refused
	}
	text := json2.encode(valid)
	for bad in [text.replace('"current":64,', ''), text.replace('"current":64', '"current":"64"'),
		text.replace('"current":64', '"current":null'), text.replace('"current":64', '"current":-1'),
		text.replace('"current":64', '"current":18446744073709551616'), ' '.repeat(progress_limit + 1)] {
		mut refused := false
		decode_progress(bad) or { refused = true }
		assert refused
	}
	for event in [Progress{ phase: 'resolve' }, Progress{ phase: 'verify', package: 'app', path: 'bin/app' },
		Progress{ phase: 'metadata', repository: 'trusted', path: 'index.json', current: 256 },
		Progress{ phase: 'stage', current: 2, total: 2 }, Progress{ phase: 'activate' },
		Progress{ phase: 'complete', current: 1, total: 1 }] { event.validate()! }
}

fn test_progress_reader_rejects_duplicate_unknown_noncanonical_and_invalid_utf8_metadata() {
	text := json2.encode(Progress{ phase: 'copy', package: 'app', repository: 'trusted', path: 'share/é🚀', current: 64, total: 128 })
	for bad in [text + '{}', text.replace('"phase":"copy"', '"phase":"copy","ph\\u0061se":"verify"'),
		text.replace('"path":"share/é🚀"', '"path":"\\ud800"'), text.replace('"current":64', '"current":064'),
		text.replace('"current":64', '"current":64.0'), text.replace('"phase":', '"unknown":'),
		text.replace('"package":"app"', '"package":null')] {
		mut accepted := false
		mut event := decode_progress(bad) or { unsafe { err.free() }; continue }
		accepted = true; event.close(); assert !accepted
	}
	for path in ['/bin/app', 'bin//app', 'bin/./app', 'bin/../app', 'bin/', '.', '..', 'bin\\app']! { assert !progress_path(path) }
	for path in ['', 'bin/app', 'share/é🚀', '.../app', '.hidden/file']! { assert progress_path(path) }
}

fn test_progress_reader_retires_valid_invalid_and_partial_decoded_fields() {
	$if track_heap ? {
		text := json2.encode(Progress{ phase: 'copy', package: 'app', repository: 'trusted', path: 'share/é🚀', current: 64, total: 128 })
		partial := text.replace('"total":128', '"total":null')
		invalid := text.replace('"phase":"copy"', '"phase":"unknown"')
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				mut event := decode_progress(text)!; event.close()
				for bad in [partial, invalid]! {
					mut refused := decode_progress(bad) or { unsafe { err.free() }; continue }
					refused.close(); assert false
				}
			}
		}
		kept := C.vinix_heap_end(); assert kept == 0, 'progress decoding retained ${kept} bytes'
		println('PACKAGE PROGRESS 1000 valid, invalid and partial metadata decode/retirement cycles retain zero tracked bytes PASS')
	}
}
