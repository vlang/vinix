// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os
import time

fn C.mkfifo(&char, u32) int

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn test_snapshot_decoder_retires_complete_and_partial_results() {
	$if track_heap ? {
		text := json2.encode([Snapshot{ repository: Repository{ id: 'publisher', url: 'file:///repository', public_key: 'a'.repeat(64) }, text: '{"format":1}', signature: 'b'.repeat(128) }])
		broken := text[..text.len - 3]
		C.vinix_heap_begin()
		for _ in 0 .. 1000 { snapshots := decode_snapshots(text)!; close_decoded_snapshots(snapshots) }
		valid := C.vinix_heap_end()
		C.vinix_heap_begin()
		for _ in 0 .. 1000 {
			if snapshots := decode_snapshots(broken) { close_decoded_snapshots(snapshots); assert false }
			else { message := err.msg(); unsafe { message.free(); err.free() } }
		}
		invalid := C.vinix_heap_end()
		println('SNAPSHOT DECODE 1000 complete decodes retained ' + valid.str() + ' bytes; 1000 partial refusals retained ' + invalid.str() + ' bytes')
		assert valid == 0 && invalid == 0
	}
}

fn snapshot_decode_fixture(id string) Snapshot {
	return Snapshot{ repository: Repository{ id: id, url: 'file:///repository', public_key: '01' + '00'.repeat(31) },
		text: 'payload', signature: 'b'.repeat(128) + '\n' }
}

fn refuse_snapshot_decode(text string) {
	if snapshots := decode_snapshots(text) { close_decoded_snapshots(snapshots); assert false, 'cache must refuse' }
	else { message := err.msg(); assert message != ''; unsafe { message.free(); err.free() } }
}

fn test_snapshot_decoder_preserves_opaque_bytes_and_owned_bounded_records() {
	opaque := Snapshot{ ...snapshot_decode_fixture('publisher'),
		text: " \n{\"repository\":{\"id\":\"literal\"},\"text\":\"λ🚀\\\"\"}\t\x00\n", signature: 'b'.repeat(128) + '\r\n\t' }
	for count in [0, 64, 4096]! {
		mut expected := []Snapshot{cap: count}
		for i in 0 .. count { expected << Snapshot{ ...opaque, repository: Repository{ ...opaque.repository, id: 'publisher-' + i.str() } } }
		canonical := json2.encode(expected)
		// Five owned strings per record exceed the tracker's live-record table
		// at the valid maximum; track empty/growing cases and qualify full bounds
		// functionally and under ASan instead.
		tracked := count != 4096
		$if track_heap ? { if tracked { C.vinix_heap_begin() } }
		for _ in 0 .. if tracked { 1000 } else { 1 } {
			values := decode_snapshots(canonical)!; assert values.len == count
			if count > 0 { assert values[count - 1].repository.id == expected[count - 1].repository.id && values[0].text == opaque.text && values[0].signature == opaque.signature }
			close_decoded_snapshots(values)
		}
		$if track_heap ? { if tracked { kept := C.vinix_heap_end(); assert kept == 0 } }
		input := canonical.clone()
		first := decode_snapshots(input)!; second := decode_snapshots(input)!
		if count > 0 { assert first.data != second.data && first[0].text.str != second[0].text.str }
		unsafe { input.free() }; close_decoded_snapshots(first)
		assert second == expected && json2.encode(second) == canonical
		close_decoded_snapshots(second)
	}
	text := json2.encode([opaque])
	for input in [text.replace('"repository":', '"reposito\\u0072y":').replace('"public_key":', '"public_\\u006bey":'),
		text.replace('"text":', '"te\\u0078t":').replace('"signature":', '"signat\\u0075re":')] {
		values := decode_snapshots(input)!; assert values == [opaque] && json2.encode(values) == text; close_decoded_snapshots(values)
	}
	println('SNAPSHOT DECODE owned empty/growing/full 4096 records, retired source buffers, escaped keys, opaque Unicode/NUL text and legacy signature bytes preserve canonical output PASS')
}

fn test_snapshot_decoder_retires_partial_schema_string_and_duplicate_refusals() {
	base := snapshot_decode_fixture('publisher'); text := json2.encode([base])
	for input in ['null', '{}', '[null]', '[[[]]]', text + 'true', text[..text.len - 1], text[..text.len - 3],
		text.replace('"repository":', '"unknown":[],"repository":'),
		text.replace('"text":', '"te\\u0078t":"ignored","text":'),
		text.replace('"signature":', '"signature":false,"ignored":'),
		text.replace('"text":"payload",', ''), text.replace('"url":"file:///repository",', ''),
		text.replace('"repository":{', '"repository":null,"unknown":{'),
		text.replace('"id":"publisher"', '"id":false'),
		text.replace('"id":"publisher"', '"id":"' + 'p'.repeat(129) + '"'),
		text.replace('"url":', '"u\\u0072l":"file:///other","url":'),
		text.replace('file:///repository', 'file:///../outside'), text.replace('file:///repository', 'http://untrusted.invalid'),
		text.replace('payload', ''), text.replace('payload', 'bad\\ud800'), text.replace('payload', 'bad\\udc00'),
		text.replace('payload', 'bad' + u8(0xff).ascii_str()), text.replace('payload', 'bad\n'),
		text.replace('b'.repeat(128) + '\\n', ''), text.replace('b'.repeat(128), 'b'.repeat(257)),
		text.replace('"public_key":"' + base.repository.public_key + '"', '"public_key":null'),
		json2.encode([base, base])] {
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. 1000 { refuse_snapshot_decode(input) }
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
	}
	mut too_many := []Snapshot{cap: 4097}
	for i in 0 .. 4097 { too_many << snapshot_decode_fixture('publisher-' + i.str()) }
	// Full record inventories exceed the heap tracker's live-record capacity.
	refuse_snapshot_decode(json2.encode(too_many))
	println('SNAPSHOT DECODE 1000-cycle partial/schema/UTF8/duplicate refusals retire scratch; 4097 records refuse before admission PASS')
}

fn test_snapshot_decoder_counts_exact_encoded_metadata_boundary() {
	base := snapshot_decode_fixture('publisher')
	encoded := json2.encode([base]); overhead := encoded.len - base.text.len
	boundary := Snapshot{ ...base, text: 'x'.repeat(max_metadata - overhead) }
	for sample in [Snapshot{ ...boundary, text: boundary.text[..boundary.text.len - 1] }, boundary] {
		text := json2.encode([sample]); assert text.len <= max_metadata && text.len >= max_metadata - 1
		$if track_heap ? { C.vinix_heap_begin() }
		values := decode_snapshots(text)!; assert values.len == 1 && values[0].text == sample.text
		close_decoded_snapshots(values)
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
	}
	too_large := json2.encode([Snapshot{ ...boundary, text: boundary.text + 'x' }]); assert too_large.len == max_metadata + 1
	$if track_heap ? { C.vinix_heap_begin() }
	refuse_snapshot_decode(too_large)
	$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
	println('SNAPSHOT DECODE exact 8 MiB and limit-minus-one preserve opaque text; limit-plus-one refuses before parsing PASS')
}

fn test_snapshot_file_reader_retires_scratch_preserves_damage_and_allows_restored_retry() {
	directory := os.temp_dir() + '/vinix-snapshot-decode-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(directory)!; defer { os.rmdir_all(directory) or {} }
	path := directory + '/catalog.json'; text := json2.encode([snapshot_decode_fixture('publisher')])
	for failure in ['absent', 'valid', 'partial', 'alias', 'fifo']! {
		match failure {
			'valid' { os.write_file(path, text)! }
			'partial' { os.write_file(path, text[..text.len - 1])! }
			'alias' { os.rm(path)!; os.symlink(directory + '/missing', path)! }
			'fifo' { os.rm(path)!; assert C.mkfifo(path.str, 0o600) == 0 }
			else {}
		}
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. 1000 {
			if values := read_snapshots(directory) {
				assert failure in ['absent', 'valid']! && values.len == if failure == 'absent' { 0 } else { 1 }
				close_decoded_snapshots(values)
			} else {
				message := err.msg(); assert failure !in ['absent', 'valid']! && message != ''
				if failure == 'partial' { assert message.starts_with('invalid cached repository metadata:') }
				unsafe { message.free(); err.free() }
			}
		}
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
		if failure == 'absent' { assert os.ls(directory)!.len == 0 }
		if failure == 'partial' { assert os.read_file(path)! == text[..text.len - 1] }
		if failure == 'fifo' { assert os.lstat(path)!.mode & 0o170000 == 0o010000 }
		if failure == 'alias' { assert os.readlink(path)! == directory + '/missing' }
		if failure in ['alias', 'fifo']! { os.rm(path)!; os.write_file(path, text)! }
	}
	os.write_file(path, text)!
	values := read_snapshots(directory)!; assert values[0].text == 'payload'; close_decoded_snapshots(values)
	assert os.read_file(path)! == text
	blocked := directory + '/blocked'; os.write_file(blocked, 'ordinary parent')!
	$if track_heap ? { C.vinix_heap_begin() }
	for _ in 0 .. 1000 {
		if unexpected := read_snapshots(blocked) { close_decoded_snapshots(unexpected); assert false }
		else { message := err.msg(); assert message != ''; unsafe { message.free(); err.free() } }
	}
	$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
	assert os.read_file(blocked)! == 'ordinary parent'
	println('SNAPSHOT DECODE 1000 absent/valid/partial/alias/FIFO/parent file reads retire scratch, preserve retained bytes and permit restored retry PASS')
}
