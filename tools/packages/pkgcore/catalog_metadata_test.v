// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64
fn C.vinix_heap_count() u32

fn cache_snapshot() Snapshot {
	return Snapshot{ repository: Repository{ id: 'trusted', url: 'file:///srv/packages', public_key: 'a'.repeat(64) },
		text: '{}', signature: 'b'.repeat(128) }
}

fn encode_cache_fixture(snapshots []Snapshot) !string {
	mut encoding := new_snapshot_encoding()
	defer { unsafe { encoding.free() } }
	for snapshot in snapshots { append_snapshot_metadata(snapshot, mut encoding)! }
	return finish_snapshot_encoding(mut encoding)
}

fn test_incremental_snapshot_encoding_preserves_exact_bytes_order_and_escaping() {
	first := cache_snapshot()
	second := Snapshot{ ...first, repository: Repository{ ...first.repository, id: 'other' },
		text: '{"quote":"\\\"","path":"a\\\\b","unicode":"é/文件"}\n\t' }
	for snapshots in [ []Snapshot{}, [first], [second, first] ] {
		encoded := encode_cache_fixture(snapshots)!
		assert encoded == json2.encode(snapshots)
		decoded := decode_snapshots(encoded)!
		assert decoded == snapshots
		close_decoded_snapshots(decoded)
		unsafe { encoded.free() }
	}
	println('CACHE PREFLIGHT exact snapshot wrapper encoding, empty cache, order, escaping and reader round-trip PASS')
}

fn cache_boundary_snapshot() Snapshot {
	base := cache_snapshot()
	text := json2.encode([base])
	overhead := text.len - base.text.len
	unsafe { text.free() }
	return Snapshot{ ...base, text: 'a'.repeat(max_metadata - overhead) }
}

fn test_snapshot_encoding_counts_closing_bracket_and_cumulative_prefix_at_exact_limit() {
	boundary := cache_boundary_snapshot()
	below := Snapshot{ ...boundary, text: boundary.text[..boundary.text.len - 1] }
	for snapshot in [below, boundary] {
		encoded := encode_cache_fixture([snapshot])!
		assert encoded.len == max_metadata - (boundary.text.len - snapshot.text.len)
		decoded := decode_snapshots(encoded)!
		assert decoded.len == 1 && decoded[0].text == snapshot.text
		close_decoded_snapshots(decoded)
		unsafe { encoded.free() }
	}
	for snapshots in [ [Snapshot{ ...boundary, text: boundary.text + 'a' }], [boundary, cache_snapshot()],
		[Snapshot{ ...boundary, text: '"'.repeat(max_metadata / 2) }] ] {
		if encoded := encode_cache_fixture(snapshots) { unsafe { encoded.free() }; assert false } else {
			message := err.msg(); assert message == 'combined repository metadata exceeds cache limit'
			unsafe { message.free(); err.free() }
		}
	}
	println('CACHE PREFLIGHT limit-minus-one and exact 8 MiB accepted; closing byte, cumulative prefix and escape expansion overflow refused PASS')
}

fn test_repeated_snapshot_encoding_retires_accepted_and_rejected_buffers() {
	$if track_heap ? {
		base := cache_snapshot()
		accepted := [Snapshot{ ...base, text: 'x'.repeat(2048) }, base]
		rejected := [cache_boundary_snapshot(), base]
		for snapshots in [accepted, rejected] {
			for _ in 0 .. 16 {
				C.vinix_heap_begin()
				if encoded := encode_cache_fixture(snapshots) { unsafe { encoded.free() } }
				else { message := err.msg(); unsafe { message.free(); err.free() } }
				kept := C.vinix_heap_end(); count := C.vinix_heap_count()
				assert kept == 0 && count == 0, '${kept} bytes / ${count} allocations retained'
			}
		}
		println('CACHE PREFLIGHT 16 accepted and 16 oversized encodings retire all encoder scratch PASS')
	}
}
