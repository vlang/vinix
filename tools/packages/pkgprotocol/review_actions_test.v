// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import json2

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

struct ActionCase {
	operation string
	action string
	previous string
	target string = '2.0.0'
	accepted bool
}

fn action_review_case(arch string, format int, c ActionCase) Review {
	removed := c.action == 'remove'
	return Review{format: format, operation: c.operation, architecture: arch,
		fingerprint: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
		names: if c.operation in ['install', 'remove', 'mirror']! { ['app'] } else { []string{} },
		target_generation: if c.operation == 'rollback' { u64(1) } else { u64(0) },
		requested: if removed { []string{} } else { ['app'] },
		rows: [ReviewPackage{id: 'app', name: 'App', version: c.target, installed_version: c.previous,
			architecture: arch, kind: 'native', repository: 'trusted',
			public_key: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
			license: 'MIT', action: c.action, requested: !removed, permissions: ['files']}]}
}

fn test_review_actions_match_versions_in_current_legacy_and_nested_reviews() {
	cases := [
		ActionCase{operation: 'install', action: 'install', accepted: true},
		ActionCase{operation: 'upgrade', action: 'install', accepted: true},
		ActionCase{operation: 'deploy', action: 'install', accepted: true},
		ActionCase{operation: 'rollback', action: 'install', accepted: true},
		ActionCase{operation: 'install', action: 'update', previous: '1.0.0', accepted: true},
		ActionCase{operation: 'upgrade', action: 'update', previous: '1.0.0', accepted: true},
		ActionCase{operation: 'deploy', action: 'update', previous: '1.0.0', accepted: true},
		ActionCase{operation: 'rollback', action: 'update', previous: '3.0.0', accepted: true},
		ActionCase{operation: 'upgrade', action: 'update', previous: '2.0.0', accepted: true},
		ActionCase{operation: 'repair', action: 'update', previous: '2.0.0', accepted: true},
		ActionCase{operation: 'repair', action: 'keep', previous: '2.0.0', accepted: true},
		ActionCase{operation: 'remove', action: 'keep', previous: '2.0.0', accepted: true},
		ActionCase{operation: 'remove', action: 'remove', previous: '2.0.0', accepted: true},
		ActionCase{operation: 'upgrade', action: 'remove', previous: '2.0.0', accepted: true},
		ActionCase{operation: 'deploy', action: 'remove', previous: '2.0.0', accepted: true},
		ActionCase{operation: 'rollback', action: 'remove', previous: '2.0.0', accepted: true},
		ActionCase{operation: 'mirror', action: 'export', accepted: true},
		ActionCase{operation: 'upgrade', action: 'update'},
		ActionCase{operation: 'upgrade', action: 'keep'},
		ActionCase{operation: 'upgrade', action: 'remove'},
		ActionCase{operation: 'install', action: 'install', previous: '1.0.0'},
		ActionCase{operation: 'mirror', action: 'export', previous: '1.0.0'},
		ActionCase{operation: 'upgrade', action: 'keep', previous: '1.0.0'},
		ActionCase{operation: 'remove', action: 'remove', previous: '1.0.0'},
		ActionCase{operation: 'remove', action: 'update', previous: '1.0.0'},
		ActionCase{operation: 'remove', action: 'update', previous: '2.0.0'},
		ActionCase{operation: 'remove', action: 'install'},
		ActionCase{operation: 'repair', action: 'update', previous: '1.0.0'},
		ActionCase{operation: 'repair', action: 'install'},
		ActionCase{operation: 'repair', action: 'remove', previous: '2.0.0'},
		ActionCase{operation: 'upgrade', action: 'export'},
		ActionCase{operation: 'mirror', action: 'install'},
		ActionCase{operation: 'upgrade', action: 'unknown', previous: '2.0.0'},
	]
	for arch in ['aarch64', 'x86_64']! {
		for format in [1, 2]! {
			mut accepted := []string{cap: 64}; mut refused := []string{cap: 64}
			defer { unsafe { for value in accepted { value.free() }; (&array(&accepted)).free()
				for value in refused { value.free() }; (&array(&refused)).free() } }
			for c in cases {
				mut review := action_review_case(arch, format, c)
				mut valid := true
				review.validate() or { valid = false; unsafe { err.free() } }
				assert valid == c.accepted, c.operation + '/' + c.action + '/' + c.previous
				text := json2.encode(review); review.close()
				if c.accepted { accepted << text } else { refused << text }
				// Genuine old writers omit the optional fields altogether.
				without_pair := text.replace(',"installed_permissions_known":false,"installed_permissions":[]', '')
				assert without_pair != text
				if c.accepted { accepted << without_pair } else { refused << without_pair }
			}
			// Nested offline reviews must apply exactly the same row admission.
			for before in ['', '1.0.0']! {
				mut nested := MirrorReview{format: 1, input_destination: '/media/new', destination: '/media/new',
					review: action_review_case(arch, format, ActionCase{operation: 'mirror', action: 'export', previous: before})}
				text := json2.encode(nested)
				locked := json2.encode(DeploymentMirrorReview{format: 1, deployment: '/company/lock.json',
					deployment_sha256: 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc', mirror: nested})
				nested.close()
				mut export_review := decode_mirror_review(text) or { assert before != ''; unsafe { err.free() }; MirrorReview{} }
				assert (export_review.review.rows.len > 0) == (before == ''); export_review.close()
				mut locked_review := decode_deployment_mirror_review(locked) or { assert before != ''; unsafe { err.free() }; DeploymentMirrorReview{} }
				assert (locked_review.mirror.review.rows.len > 0) == (before == ''); locked_review.close()
				unsafe { text.free(); locked.free() }
			}
			for warmup in 0 .. 2 {
				$if track_heap ? { if warmup == 1 { C.vinix_heap_begin() } }
				for _ in 0 .. 1000 {
					for text in accepted { mut value := decode_review(text)!; value.close(); value.close() }
					for text in refused {
						mut value := decode_review(text) or { unsafe { err.free() }; continue }
						value.close(); assert false, 'contradictory review action was admitted'
					}
				}
			}
			$if track_heap ? { kept := C.vinix_heap_end(); assert kept == 0, 'review action decoding retained ' + kept.str() }
		}
	}
	unsafe { (&array(&cases)).free() }
	println('REVIEW ACTIONS both hosts and formats admit seventeen legitimate cases, refuse sixteen contradictions and protect nested offline reviews PASS')
	println('REVIEW ACTIONS 1000 complete/omitted/refused decode and retirement cycles per format and architecture retain zero tracked bytes PASS')
}
