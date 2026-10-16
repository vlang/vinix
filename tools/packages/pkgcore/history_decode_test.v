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

fn test_history_decoders_retire_complete_and_partial_results() {
	$if track_heap ? {
		mut retained := u64(0)
		for publisher in [false, true]! {
			collection := if publisher { 'indexes' } else { 'repositories' }
			text := '{"format":1,"' + collection + '":[{"id":"publisher","public_key":"' + 'a'.repeat(64) + '","sequence":18446744073709551615,"index_sha256":"' + 'b'.repeat(64) + '"}]}'
			broken := text[..text.len - 3]
			C.vinix_heap_begin()
			for _ in 0 .. 1000 { history := decode_history(text, publisher)!; close_decoded_history(history) }
			valid := C.vinix_heap_end()
			C.vinix_heap_begin()
			for _ in 0 .. 1000 {
				if history := decode_history(broken, publisher) { close_decoded_history(history); assert false }
				else { message := err.msg(); unsafe { message.free(); err.free() } }
			}
			invalid := C.vinix_heap_end()
			println('HISTORY DECODE publisher=' + publisher.str() + ' 1000 complete decodes retained ' + valid.str() + ' bytes; 1000 partial refusals retained ' + invalid.str() + ' bytes')
			retained += valid + invalid
		}
		assert retained == 0
	}
}

fn history_decode_text(publisher bool, floors []RepositoryFloor) string {
	return if publisher { json2.encode(ReleaseHistory{ indexes: floors }) } else { json2.encode(TrustHistory{ repositories: floors }) }
}

fn refuse_history_decode(text string, publisher bool) {
	if history := decode_history(text, publisher) { close_decoded_history(history); assert false, 'history must refuse' }
	else { message := err.msg(); assert message != ''; unsafe { message.free(); err.free() } }
}

fn test_history_decoders_preserve_bounded_owned_records_and_exact_writer_bytes() {
	for publisher in [false, true]! {
		for count in [0, 64, 4096]! {
			mut floors := []RepositoryFloor{cap: count}
			for i in 0 .. count {
				// Repeated IDs with distinct keys are separate durable identities.
				floors << RepositoryFloor{ id: 'publisher', public_key: '0'.repeat(64 - i.hex().len) + i.hex(),
					sequence: ~u64(0), index_sha256: 'b'.repeat(64) }
			}
			text := history_decode_text(publisher, floors)
			$if track_heap ? { C.vinix_heap_begin() }
			for _ in 0 .. if count == 4096 { 1 } else { 1000 } {
				history := decode_history(text, publisher)!; assert history.repositories.len == count
				if count > 0 { assert history.repositories[count - 1].public_key == floors[count - 1].public_key && history.repositories[0].sequence == ~u64(0) }
				close_decoded_history(history)
			}
			$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
			first := decode_history(text, publisher)!; second := decode_history(text, publisher)!
			if count > 0 { assert first.repositories.data != second.repositories.data && first.repositories[0].public_key.str != second.repositories[0].public_key.str }
			close_decoded_history(first)
			assert history_decode_text(publisher, second.repositories) == text
			close_decoded_history(second)
		}
		collection := if publisher { 'indexes' } else { 'repositories' }
		escaped := ' \n{"for\\u006dat":1,"' + collection + '":[{"i\\u0064":"pub\\u006cisher","public_key":"' + '0'.repeat(64) + '","sequ\\u0065nce":1,"index_sha256":"' + 'b'.repeat(64) + '"}]}\t'
		history := decode_history(escaped, publisher)!
		assert history.repositories[0].id == 'publisher' && history.repositories[0].sequence == 1
		close_decoded_history(history)
	}
	println('HISTORY DECODE owned empty/growing/full 4096 identities, distinct keys per ID, u64 maximum, escaped keys and exact canonical writer bytes PASS')
}

fn test_history_decoders_retire_partial_schema_numeric_string_and_overflow_refusals() {
	for publisher in [false, true]! {
		text := history_decode_text(publisher, [RepositoryFloor{ id: 'publisher', public_key: 'a'.repeat(64), sequence: 10, index_sha256: 'b'.repeat(64) }])
		collection := if publisher { 'indexes' } else { 'repositories' }
		mut invalid := ['null', '{}', text + 'true', text[..text.len - 1], text.replace('"format":1', '"format":01'),
			text.replace('"format":1', '"format":2147483648'), text.replace(collection, if publisher { 'repositories' } else { 'indexes' }),
			text.replace('"sequence":10', '"sequence":0'), text.replace('"sequence":10', '"sequence":01'),
			text.replace('"sequence":10', '"sequence":1.0'), text.replace('"sequence":10', '"sequence":1e1'),
			text.replace('"sequence":10', '"sequence":-1'), text.replace('"sequence":10', '"sequence":18446744073709551616'),
			text.replace('"sequence":10', '"sequence":10,"sequ\\u0065nce":10'),
			text.replace('"sequence":10', '"sequence":10,"unknown":[]'),
			text.replace('"id":"publisher"', '"id":null'), text.replace('"id":"publisher"', '"id":"' + 'p'.repeat(129) + '"'),
			text.replace('publisher', 'pub\\ud800'), text.replace('publisher', 'pub\\udc00'), text.replace('publisher', 'pub' + u8(0xff).ascii_str()),
			text.replace('"public_key":"' + 'a'.repeat(64) + '"', '"public_key":"' + 'a'.repeat(65) + '"'),
			text.replace('"index_sha256":"' + 'b'.repeat(64) + '"', '"index_sha256":"invalid"'),
			text.replace('"' + collection + '":[', '"' + collection + '":[null,'),
			history_decode_text(publisher, []RepositoryFloor{len: 2, init: RepositoryFloor{ id: 'same', public_key: 'a'.repeat(64), sequence: 1, index_sha256: 'b'.repeat(64) }})]
		for input in invalid {
			$if track_heap ? { C.vinix_heap_begin() }
			for _ in 0 .. 1000 { refuse_history_decode(input, publisher) }
			$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
		}
		mut floors := []RepositoryFloor{cap: 4097}
		for i in 0 .. 4097 { floors << RepositoryFloor{ id: 'publisher-' + i.str(), public_key: 'a'.repeat(64), sequence: 1, index_sha256: 'b'.repeat(64) } }
		invalid = [history_decode_text(publisher, floors), ' '.repeat(max_metadata + 1)]
		for input in invalid {
			$if track_heap ? { C.vinix_heap_begin() }
			refuse_history_decode(input, publisher)
			$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
		}
	}
	println('HISTORY DECODE 1000-cycle partial/schema/numeric/UTF8/duplicate refusals and 4097-record/8-MiB bounds retire all owned scratch PASS')
}

fn read_history_decode_fixture(directory string, publisher bool) !TrustHistory {
	if publisher { return release_history(directory) }
	return read_history(directory)
}

fn test_history_file_readers_retire_envelopes_preserve_damage_and_allow_restored_retry() {
	directory := os.temp_dir() + '/vinix-history-decode-' + os.getpid().str() + '-' + time.now().unix_micro().str()
	os.mkdir_all(directory + '/.publisher')!; defer { os.rmdir_all(directory) or {} }
	for publisher in [false, true]! {
		path := directory + if publisher { '/.publisher/history.json' } else { '/trust-history.json' }
		text := history_decode_text(publisher, [RepositoryFloor{ id: 'publisher', public_key: '01' + '00'.repeat(31), sequence: 17, index_sha256: 'b'.repeat(64) }])
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
				if history := read_history_decode_fixture(directory, publisher) {
					assert failure in ['absent', 'valid']! && history.repositories.len == if failure == 'absent' { 0 } else { 1 }
					close_decoded_history(history)
				} else {
					message := err.msg(); assert failure !in ['absent', 'valid']! && message != ''
					if failure == 'partial' { assert message.contains(if publisher { 'invalid publisher release history:' } else { 'invalid repository trust history:' }) }
					unsafe { message.free(); err.free() }
				}
			}
			$if track_heap ? { kept := C.vinix_heap_end(); println('HISTORY FILE publisher=' + publisher.str() + ' ' + failure + ' retained ' + kept.str() + ' bytes'); assert kept == 0 }
			if failure == 'partial' { assert os.read_file(path)! == text[..text.len - 1] }
			if failure == 'fifo' { assert os.lstat(path)!.mode & 0o170000 == 0o010000 }
			if failure == 'alias' { assert os.readlink(path)! == directory + '/missing' }
			if failure in ['alias', 'fifo']! { os.rm(path)!; os.write_file(path, text)! }
		}
		os.write_file(path, text)!
		history := read_history_decode_fixture(directory, publisher)!; assert history.repositories[0].sequence == 17
		close_decoded_history(history); assert os.read_file(path)! == text
		blocked := directory + '/blocked-' + publisher.str()
		os.write_file(blocked, 'ordinary file in place of a parent directory')!
		$if track_heap ? { C.vinix_heap_begin() }
		for _ in 0 .. 1000 {
			if unexpected := read_history_decode_fixture(blocked, publisher) { close_decoded_history(unexpected); assert false }
			else { message := err.msg(); assert message != ''; unsafe { message.free(); err.free() } }
		}
		$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0 }
		assert os.read_file(blocked)! == 'ordinary file in place of a parent directory'
	}
	println('HISTORY DECODE 1000 absent/valid/partial/alias/FIFO consumer and publisher reads retire scratch, preserve retained bytes and permit restored retry PASS')
}
