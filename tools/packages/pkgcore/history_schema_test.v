// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn history_fixture(publisher bool) string {
	floors := [RepositoryFloor{id: 'first', public_key: 'a'.repeat(64), sequence: 10, index_sha256: 'b'.repeat(64)},
		RepositoryFloor{id: 'second', public_key: 'a'.repeat(64), sequence: ~u64(0), index_sha256: 'c'.repeat(64)}]
	return if publisher { json2.encode(ReleaseHistory{indexes: floors}) }
		else { json2.encode(TrustHistory{repositories: floors}) }
}

fn history_refused(text string, publisher bool) {
	if history := decode_history(text, publisher) {
		close_decoded_history(history)
		assert false, 'accepted incomplete/ambiguous repository history: ' + text
	} else {
		message := err.msg(); unsafe { message.free(); err.free() }
	}
}

fn test_history_requires_complete_records_without_resetting_sequence_floors() {
	for publisher in [false, true] {
		text := history_fixture(publisher)
		collection := if publisher { 'indexes' } else { 'repositories' }
		for invalid in ['{}', 'null', '[]', 'true', '1', '"history"', '', '{broken',
			'{"format":1}', '{"' + collection + '":[]}', '{"format":1,"' + collection + '":null}',
			text.replace('"id":"first",', ''), text.replace('"public_key":"' + 'a'.repeat(64) + '",', ''),
			text.replace('"sequence":10,', ''), text.replace(',"index_sha256":"' + 'b'.repeat(64) + '"', ''),
			text.replace('"format":1', '"format":"1"'),
			text.replace('"sequence":10', '"sequence":"10"'),
			text.replace('"sequence":10', '"sequence":null'),
			text.replace('"sequence":10', '"sequence":-1'),
			text.replace('"sequence":10', '"sequence":1.5'),
			text.replace('"sequence":10', '"sequence":18446744073709551616'),
			text.replace('"' + collection + '":[', '"' + collection + '":[null,'),
			text.replace('"index_sha256":"' + 'b'.repeat(64) + '"', '"index_sha256":null'),
			text.replace('"format":1', '"format":1,"for\\u006dat":1'),
			text.replace('"sequence":10', '"sequence":1,"sequ\\u0065nce":10'),
			text.replace('"format":1', '"unknown":[],"format":1'),
			text.replace('"id":"first"', '"id":"first","unknown":false'),
			text.replace('"' + collection + '":', '"' + collection + '":[],"' + collection + '":'),
			text.replace('"' + collection + '":', '"misspelled":'),
			' '.repeat(max_metadata + 1)] {
			assert invalid != text
			history_refused(invalid, publisher)
		}
		// The two durable envelopes are distinct formats, despite shared floors.
		history_refused(history_fixture(!publisher), publisher)
	}
}

fn test_history_preserves_canonical_records_explicit_empty_arrays_and_unique_escapes() {
	for publisher in [false, true] {
		text := history_fixture(publisher)
		for valid in [text, ' \n' + text + '\t', text.replace('"sequence":', '"sequ\\u0065nce":')
			.replace('"format":', '"for\\u006dat":')] {
			history := decode_history(valid, publisher)!
			assert history.format == 1 && history.repositories.len == 2
			assert history.repositories[0].sequence == 10 && history.repositories[1].sequence == ~u64(0)
			encoded := if publisher { json2.encode(ReleaseHistory{indexes: history.repositories}) } else { json2.encode(history) }
			assert encoded == text
			close_decoded_history(history)
		}
		empty := if publisher { '{"format":1,"indexes":[]}' } else { '{"format":1,"repositories":[]}' }
		history := decode_history(empty, publisher)!
		assert history.repositories.len == 0
		close_decoded_history(history)
	}
}

fn test_history_rejects_invalid_floor_identities_duplicates_and_record_limits() {
	for publisher in [false, true] {
		text := history_fixture(publisher)
		for invalid in [text.replace('"sequence":10', '"sequence":0'),
			text.replace('"id":"first"', '"id":"../escape"'),
			text.replace('"id":"second"', '"id":"first"'),
			text.replace('"public_key":"' + 'a'.repeat(64) + '"', '"public_key":"invalid"'),
			text.replace('"index_sha256":"' + 'b'.repeat(64) + '"', '"index_sha256":"invalid"')] {
			history_refused(invalid, publisher)
		}
		floor := RepositoryFloor{id: 'app', public_key: 'a'.repeat(64), sequence: 1, index_sha256: 'b'.repeat(64)}
		floors := []RepositoryFloor{len: 4097, init: floor}
		history_refused(if publisher { json2.encode(ReleaseHistory{indexes: floors}) }
			else { json2.encode(TrustHistory{repositories: floors}) }, publisher)
	}
}

fn test_history_scanners_retire_owned_keys_and_failure_objects() {
	$if track_heap ? {
		for publisher in [false, true] {
			text := history_fixture(publisher)
			inputs := [text, '{"format":1}',
				text.replace('"sequence":10', '"sequence":1,"sequ\\u0065nce":10'),
				text.replace('"format":1', '"unknown":[],"format":1')]
			for warmup in 0 .. 2 {
				if warmup == 1 { C.vinix_heap_begin() }
				for _ in 0 .. 1000 {
					for i, input in inputs {
						mut accepted := true
						document_keys_schema(input, if publisher { release_history_field } else { trust_history_field },
							if publisher { release_history_required } else { trust_history_required }, history_value_type) or {
							accepted = false
							message := err.msg(); unsafe { message.free(); err.free() }
						}
						assert accepted == (i == 0)
					}
				}
				if warmup == 1 {
					kept := C.vinix_heap_end()
					assert kept == 0
					println('History scanner publisher=' + publisher.str() + ': retained ' + kept.str() + ' bytes in 1000 cycles')
				}
			}
		}
	}
}
