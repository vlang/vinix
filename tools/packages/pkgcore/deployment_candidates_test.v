// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import crypto.sha256

$if track_heap ? {
	#include "@VMODROOT/../../../desktop/tools/tests/heap_tracker.h"
	fn C.vinix_heap_begin()
	fn C.vinix_heap_end() u64
}

fn locked_candidates_fixture(total int, selected int) (Catalog, DeploymentLock) {
	mut packages := []Installed{cap: total}
	mut pins := []DeploymentPackage{cap: selected}
	for index in 0 .. total {
		id := 'app-' + index.str()
		p := Package{ id: id, name: id, version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT',
			permissions: ['network', 'files'], associations: ['text/plain', 'image/png'],
			files: [Payload{path: 'z/data', sha256: 'a'.repeat(64), bytes: 7}, Payload{path: 'a/data', sha256: 'b'.repeat(64), bytes: 7}] }
		packages << Installed{ package: p, repository: 'publisher', public_key: 'c'.repeat(64), sequence: 7 }
		if index < selected {
			pins << DeploymentPackage{ id: id, version: p.version, architecture: p.architecture,
				repository: 'publisher', public_key: packages.last().public_key, minimum_sequence: 7,
				metadata_sha256: package_metadata_digest(p) or { panic(err) } }
		}
	}
	return Catalog{packages: packages}, DeploymentLock{ architecture: 'aarch64', locked: pins }
}

fn test_locked_candidates_match_exact_identity_preserve_pin_order_and_refuse_ambiguity() {
	catalog, document := locked_candidates_fixture(4, 2)
	base := catalog.packages[0]
	variants := [Installed{ ...base, package: Package{ ...base.package, id: 'different' } },
		Installed{ ...base, package: Package{ ...base.package, version: '2.0.0' } },
		Installed{ ...base, package: Package{ ...base.package, architecture: 'aarch64' } },
		Installed{ ...base, repository: 'other' }, Installed{ ...base, public_key: 'd'.repeat(64) }]
	for candidate in variants {
		if _ := locked_deployment_candidates(Catalog{packages: [candidate]}, DeploymentLock{locked: [document.locked[0]]}) { assert false } else {
			message := err.msg(); assert message.contains('app-0') && message.contains('absent from the authenticated catalog')
			unsafe { message.free(); err.free() }
		}
	}
	mut mixed := variants.clone(); mixed << catalog.packages.reverse()
	reversed := DeploymentLock{ ...document, locked: document.locked.reverse() }
	selected := locked_deployment_candidates(Catalog{packages: mixed}, reversed)!
	assert selected.len == 2 && selected[0].package.id == 'app-1' && selected[1].package.id == 'app-0'
	assert selected[1].package.files[0].path == 'z/data' && base.package.permissions == ['network', 'files']
	unsafe { (&array(&selected)).free() }
	for count in [2, 257]! {
		if _ := locked_deployment_candidates(Catalog{packages: [base].repeat(count)}, DeploymentLock{locked: [document.locked[0]]}) { assert false } else {
			message := err.msg(); assert message.contains('app-0') && message.contains('ambiguous')
			unsafe { message.free(); err.free() }
		}
	}
	if _ := locked_deployment_candidates(catalog, DeploymentLock{locked: [document.locked[0], document.locked[0]]}) { assert false } else {
		message := err.msg(); assert message.contains('duplicate locked deployment package')
		unsafe { message.free(); err.free() }
	}
	assert catalog.packages[0] == base && document.locked[0].id == 'app-0'
	println('Deployment candidates: exact version/architecture/repository/key matching, lock order, ignored variants, duplicate pins and saturated ambiguity PASS')
}

fn test_locked_candidates_bind_manifest_digest_and_minimum_publisher_sequence() {
	catalog, document := locked_candidates_fixture(1, 1)
	base := catalog.packages[0]
	for candidate in [Installed{ ...base, sequence: 6 },
		Installed{ ...base, package: Package{ ...base.package, description: 'changed metadata' } }] {
		if _ := locked_deployment_candidates(Catalog{packages: [candidate]}, document) { assert false } else {
			message := err.msg(); assert message.contains('app-0: locked publisher sequence or package metadata changed')
			unsafe { message.free(); err.free() }
		}
	}
	selected := locked_deployment_candidates(Catalog{packages: [Installed{ ...base, sequence: 8 }]}, document)!
	assert selected.len == 1 && selected[0].sequence == 8 && selected[0].package == base.package
	unsafe { (&array(&selected)).free() }
	mut empty := locked_deployment_candidates(catalog, DeploymentLock{})!
	assert empty.len == 0; unsafe { empty.free() }
}

fn test_locked_candidates_support_the_complete_catalog_and_lock_limits() {
	catalog, document := locked_candidates_fixture(32768, 4096)
	selected := locked_deployment_candidates(catalog, document)!
	assert selected.len == 4096 && selected.cap == 4096 && selected[4095].package.id == 'app-4095'
	assert selected[0].package.files[0].path == 'z/data' && catalog.packages.last().package.id == 'app-32767'
	unsafe { (&array(&selected)).free() }
	if _ := locked_deployment_candidates(catalog, DeploymentLock{locked: document.locked.repeat(2)}) { assert false } else {
		message := err.msg(); assert message.contains('input limits'); unsafe { message.free(); err.free() }
	}
	// The solver sees only exact pins. An additional unrelated catalog record
	// must not impose a new advertised-catalog limit on existing deployments.
	mut expanded := catalog.packages.clone()
	expanded << Installed{ ...catalog.packages.last(), package: Package{ ...catalog.packages.last().package, id: 'extra' } }
	more := locked_deployment_candidates(Catalog{packages: expanded}, document)!
	assert more.len == 4096; unsafe { (&array(&more)).free() }
	println('Deployment candidates: catalog-32768/lock-4096 and unrelated catalog growth succeed with pin-sized storage; excess pins refuse PASS')
}

fn test_package_metadata_digest_preserves_sdk_bytes_and_all_borrowed_nested_fields() {
	catalog, _ := locked_candidates_fixture(1, 0)
	p := Package{ ...catalog.packages[0].package, arguments: ['--two', '--one'], dependencies: [Dependency{id: 'z'}, Dependency{id: 'a'}] }
	expected := '{"id":"app-0","version":"1.0.0","architecture":"all","name":"app-0","description":"","homepage":"","license":"MIT","proprietary":false,"firmware":false,"kind":"data","runtime":"","entrypoint":"","arguments":["--two","--one"],"permissions":["files","network"],"associations":["image/png","text/plain"],"dependencies":[{"id":"a","minimum":"","before":""},{"id":"z","minimum":"","before":""}],"files":[{"path":"a/data","sha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","bytes":7,"executable":false},{"path":"z/data","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","bytes":7,"executable":false}],"sdk":1}\n'
	digest := package_metadata_digest(p)!
	assert digest == sha256.hexhash(expected)
	assert p.files[0].path == 'z/data' && p.dependencies[0].id == 'z' && p.permissions == ['network', 'files']
	assert p.associations == ['text/plain', 'image/png'] && p.arguments == ['--two', '--one']
	unsafe { digest.free() }
	println('Deployment digest: exact SDK-1 canonical JSON plus LF, sorted inventory/requirements/declarations and literal argument order preserve caller fields PASS')
}

fn test_locked_candidate_matching_retires_its_own_storage_and_preserves_borrowed_fields() {
	$if track_heap ? {
		catalog, document := locked_candidates_fixture(256, 16)
		late := DeploymentLock{ ...document, locked: [...document.locked, DeploymentPackage{ ...document.locked[0], id: 'absent' }] }
		changed := DeploymentLock{ ...document, locked: [DeploymentPackage{ ...document.locked[0], metadata_sha256: '0'.repeat(64) }] }
		old := DeploymentLock{ ...document, locked: [DeploymentPackage{ ...document.locked[0], minimum_sequence: 8 }] }
		ambiguous := Catalog{packages: [...catalog.packages, catalog.packages[0]]}
		large := Package{ ...catalog.packages[0].package, description: 'd'.repeat(4096), arguments: ['literal', 'a'.repeat(4096)] }
		for warmup in 0 .. 2 {
			if warmup == 1 { C.vinix_heap_begin() }
			for _ in 0 .. 1000 {
				candidates := locked_deployment_candidates(catalog, document)!
				assert candidates.len == 16 && candidates[0].package.files[0].path == 'z/data'
				unsafe { (&array(&candidates)).free() }
				for refused in [late, changed, old]! {
					if _ := locked_deployment_candidates(catalog, refused) { assert false } else {
						message := err.msg(); assert message != ''; unsafe { message.free(); err.free() }
					}
				}
				if _ := locked_deployment_candidates(ambiguous, document) { assert false } else {
					message := err.msg(); assert message.contains('ambiguous'); unsafe { message.free(); err.free() }
				}
				digest := package_metadata_digest(large)!; unsafe { digest.free() }
			}
		}
		kept := C.vinix_heap_end()
		println('Deployment candidates: 1000 exact/absent/digest/sequence/ambiguous matching and growing digest cycles retained ${kept} bytes')
		assert kept == 0
	}
}
