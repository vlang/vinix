// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import json2

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn test_cleanup_review_strict_roundtrip_bounds_and_owned_decoding() {
	text := json2.encode(CleanupReview{ architecture: 'aarch64', generation: 9, previous: 8,
		fingerprint: 'a'.repeat(64), generations: [u64(1), 2, 5] })
	defer { unsafe { text.free() } }
	mut review := decode_cleanup_review(text)!
	assert review.generations == [u64(1), 2, 5] && review.generation == 9 && review.previous == 8
	review.close(); review.close()
	for invalid in [text + '{}', text.replace('"format":1', '"format":2'), text.replace('"format":1', '"format":1,"unknown":1'),
		text.replace('"format":1', '"format":1,"forma\\u0074":1'), text.replace('"generations":[1,2,5]', '"generations":null'),
		text.replace('[1,2,5]', '[1,1]'), text.replace('[1,2,5]', '[2,1]'), text.replace('[1,2,5]', '[0]'),
		text.replace('[1,2,5]', '[8]'), text.replace('[1,2,5]', '[9]'), text.replace('[1,2,5]', '[-1]'),
		text.replace('[1,2,5]', '[01]'), text.replace('[1,2,5]', '[1.0]'), text.replace('[1,2,5]', '[18446744073709551616]'),
		text.replace('"previous":8', '"previous":9'), text.replace('"architecture":"aarch64",', ''),
		text.replace('"architecture":"aarch64"', '"architecture":"\\ud800"'), text.replace('"generation":9', '"generation":"9"')] {
		mut refused := false
		decode_cleanup_review(invalid) or { refused = true; unsafe { err.free() } }
		assert refused, invalid
		unsafe { invalid.free() }
	}
	mut generations := []u64{len: 4096, init: u64(index + 1)}
	wide := json2.encode(CleanupReview{ architecture: 'x86_64', generation: 5000, previous: 4999,
		fingerprint: 'b'.repeat(64), generations: generations })
	mut decoded := decode_cleanup_review(wide)!; assert decoded.generations.len == 4096; decoded.close()
	generations << u64(4097)
	excess := json2.encode(CleanupReview{ architecture: 'x86_64', generation: 5000, previous: 4999,
		fingerprint: 'b'.repeat(64), generations: generations })
	mut refused := false; decode_cleanup_review(excess) or { refused = true; unsafe { err.free() } }; assert refused
	unsafe { generations.free(); wide.free(); excess.free() }
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 1000 {
		mut owned := decode_cleanup_review(text)!; owned.close()
		decode_cleanup_review('{"architecture":"aarch64","fingerprint":"owned","generations":[1,2,3],"previous":null}') or { unsafe { err.free() } }
	}
	$if track_heap ? {
		kept := C.vinix_heap_end(); assert kept == 0, 'cleanup decoder retained ${kept} bytes'
	}
	println('CLEANUP PROTOCOL strict bounded metadata, retained generation refusal and 1000 owned decode cycles PASS')
}
