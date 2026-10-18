// SPDX-License-Identifier: GPL-2.0-or-later
module pkgprotocol

import json2

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn permission_review(architecture string) Review {
	return Review{format: 2, operation: 'upgrade', architecture: architecture, fingerprint: 'a'.repeat(64), requested: ['editor'],
		rows: [ReviewPackage{id: 'editor', name: 'Editor', version: '2.0.0', installed_version: '1.0.0', architecture: architecture,
			kind: 'native', repository: 'trusted', public_key: 'b'.repeat(64), license: 'MIT', requested: true, action: 'update',
			permissions: ['display', 'network'], installed_permissions_known: true, installed_permissions: ['files']}]}
}

fn test_review_permissions_own_complete_and_legacy_groups_and_reject_inconsistent_facts() {
	for arch in ['aarch64', 'x86_64']! {
		mut source := permission_review(arch)
		defer { source.close() }
		text := json2.encode(source)
		without_known := text.replace(',"installed_permissions_known":true', '')
		without_permissions := text.replace(',"installed_permissions":["files"]', '')
		without_pair := without_known.replace(',"installed_permissions":["files"]', '')
		legacy := without_pair.replace('"format":2', '"format":1')
		defer { unsafe { text.free(); without_known.free(); without_permissions.free(); without_pair.free(); legacy.free() } }
		mut decoded := decode_review(text)!
		assert decoded.rows[0].installed_permissions_known && decoded.rows[0].installed_permissions == ['files']
		assert decoded.rows[0].permissions == ['display', 'network']
		decoded.close(); decoded.close()
		mut old := decode_review(legacy)!
		assert !old.rows[0].installed_permissions_known && old.rows[0].installed_permissions.len == 0
		old.close()
		mut invalid := [without_known.clone(), without_permissions.clone(),
			text.replace('"format":2', '"format":1'),
			text.replace('"installed_permissions_known":true', '"installed_permissions_known":false'),
			text.replace('"installed_permissions_known":true', '"installed_permissions_known":true,"installed_permissions_known":true'),
			text.replace('"installed_permissions_known":true', '"installed_permissions_known":true,"installed\\u005fpermissions_known":true'),
			text.replace('"installed_permissions":["files"]', '"installed_permissions":["files"],"installed_permissions":[]'),
			text.replace('"installed_permissions":["files"]', '"installed_permissions":null'),
			text.replace('"installed_permissions":["files"]', '"installed_permissions":["root"]'),
			text.replace('"installed_permissions":["files"]', '"installed_permissions":["files","files"]'),
			text.replace('"installed_permissions":["files"]', '"installed_permissions":["audio","display","files","network","process","files"]'),
			text.replace('"installed_version":"1.0.0"', '"installed_version":""'),
			text.replace('"action":"update"', '"action":"install"'),
			text.replace('"action":"update"', '"action":"keep"'),
			text.replace('"installed_permissions":["files"]', '"installed_permissions":["\xff"]')]
		defer { unsafe { for value in invalid { value.free() }; (&array(&invalid)).free() } }
		for warmup in 0 .. 2 {
			$if track_heap ? { if warmup == 1 { C.vinix_heap_begin() } }
			for _ in 0 .. 1000 {
				mut complete := decode_review(text)!; complete.close()
				mut prior := decode_review(legacy)!; prior.close()
				for bad in invalid {
					mut refused := decode_review(bad) or { unsafe { err.free() }; continue }
					refused.close(); assert false, 'invalid installed permission group was accepted'
				}
			}
		}
		$if track_heap ? {
			kept := C.vinix_heap_end(); assert kept == 0, 'review permissions retained ' + kept.str()
		}
		// A known empty previous set is different from unavailable metadata.
		empty := text.replace('"installed_permissions":["files"]', '"installed_permissions":[]')
		mut empty_prior := decode_review(empty)!; assert empty_prior.rows[0].installed_permissions_known; empty_prior.close()
		unsafe { empty.free() }
	}
	println('REVIEW PERMISSIONS both hosts admit complete/legacy/known-empty groups, reject fifteen malformed groups and retire 1000 valid/legacy/refused cycles PASS')
}
