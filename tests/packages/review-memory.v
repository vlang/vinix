// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import tools.packages.pkgprotocol

#include "@VMODROOT/../../desktop/tools/tests/heap_tracker.h"
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn consume(kind int, text string, expected bool) {
	mut accepted := true
	match kind {
		0 { mut value := pkgprotocol.decode_review(text) or { accepted = false; unsafe { err.free() }; pkgprotocol.Review{} }; value.close() }
		1 { mut value := pkgprotocol.decode_repositories(text) or { accepted = false; unsafe { err.free() }; pkgprotocol.RepositoryStatus{} }; value.close() }
		2 { mut value := pkgprotocol.decode_repository_review(text) or { accepted = false; unsafe { err.free() }; pkgprotocol.RepositoryReview{} }; value.close() }
		3 { mut value := pkgprotocol.decode_mirror_review(text) or { accepted = false; unsafe { err.free() }; pkgprotocol.MirrorReview{} }; value.close() }
		4 { mut value := pkgprotocol.decode_deployment_mirror_review(text) or { accepted = false; unsafe { err.free() }; pkgprotocol.DeploymentMirrorReview{} }; value.close() }
		else { panic('invalid memory fixture') }
	}
	assert accepted == expected
}

fn main() {
	mut rows := []pkgprotocol.ReviewPackage{cap: 32}
	for index in 0 .. 32 {
		rows << pkgprotocol.ReviewPackage{ id: 'app-' + index.str(), name: 'Application é🚀', description: 'A complete application description '.repeat(8),
			version: '1.0.0', architecture: 'aarch64', kind: 'native', repository: 'trusted', public_key: 'b'.repeat(64),
			license: 'MIT', permissions: ['files', 'network'], action: 'export', requested: index == 0 }
	}
	rows.sort(a.id < b.id)
	review := pkgprotocol.Review{ format: 1, operation: 'mirror', names: ['app-0'], requested: ['app-0'], architecture: 'aarch64',
		fingerprint: 'a'.repeat(64), rows: rows }
	mirror := pkgprotocol.MirrorReview{ format: 1, input_destination: '/media/' + 'new é🚀; $literal '.repeat(16),
		destination: '/media/' + 'new é🚀; $literal '.repeat(16), review: review }
	mut repositories := []pkgprotocol.Repository{cap: 32}
	mut history := []pkgprotocol.RepositoryFloor{cap: 32}
	for index in 0 .. 32 {
		repositories << pkgprotocol.Repository{ id: 'publisher-' + index.str(), public_key: 'b'.repeat(64), url: 'https://example.invalid/' + 'long-é-'.repeat(32) }
		history << pkgprotocol.RepositoryFloor{ id: repositories.last().id, public_key: 'b'.repeat(64), sequence: 7, index_sha256: 'c'.repeat(64) }
	}
	repository := pkgprotocol.RepositoryReview{ format: 1, operation: 'enroll', architecture: 'aarch64', id: 'trusted',
		url: 'https://example.invalid/' + 'long-é-'.repeat(32), public_key: 'b'.repeat(64), fingerprint: 'a'.repeat(64),
		index_sha256: 'c'.repeat(64), sequence: 7, expires: 2000000000, package_count: 1 }
	texts := [json2.encode(review),
		json2.encode(pkgprotocol.RepositoryStatus{ format: 1, architecture: 'aarch64', repositories: repositories, history: history }),
		json2.encode(repository), json2.encode(mirror), json2.encode(pkgprotocol.DeploymentMirrorReview{ format: 1,
			deployment: '/company/' + 'approved-é-'.repeat(32) + '.json', deployment_sha256: 'd'.repeat(64), mirror: mirror })]
	mut invalid := []string{cap: 5}
	for kind, text in texts {
		invalid << match kind {
			1 { text.replace('"sequence":7', '"sequence":18446744073709551616') }
			2 { text.replace('"remembered_sequence":0', '"remembered_sequence":null') }
			else { text.replace('"id":"app-9"', '"id":"app-9","firm\\u0077are":false') }
		}
	}
	for warmup in 0 .. 2 {
		if warmup == 1 { C.vinix_heap_begin() }
		for _ in 0 .. 1000 {
			for kind, text in texts { consume(kind, text, true); consume(kind, invalid[kind], false) }
		}
	}
	kept := C.vinix_heap_end()
	assert kept == 0, 'metadata review readers retained ${kept} bytes'
	println('Package/repository/offline review readers: 1000 wide valid/partial-invalid decode/close cycles retain zero tracked bytes')
}
