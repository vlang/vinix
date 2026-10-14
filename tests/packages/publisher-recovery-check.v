// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import tools.packages.pkgcore

fn digest(text string) string { return sha256.sum(text.bytes()).hex() }

fn exercise(root string, revoke bool, before bool) ! {
	os.mkdir_all(root + '/etc/vinix-packages')!
	os.mkdir(root + '/source')!
	os.write_file(root + '/source/payload', 'publisher recovery payload')!
	os.write_file(root + '/manifest.json', json2.encode(pkgcore.Package{ id: 'data', name: 'Data',
		version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT' }))!
	os.write_file(root + '/seed', '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60\n')!
	os.chmod(root + '/seed', 0o600)!
	initial := pkgcore.Config{ architecture: 'aarch64', policy: pkgcore.Policy{ offline: true, reserve_bytes: 0 } }
	config_path := root + '/etc/vinix-packages/config.json'
	os.write_file(config_path, json2.encode(initial))!
	os.chmod(config_path, 0o644)!
	pkgcore.pack(root + '/manifest.json', root + '/source', root + '/repository')!
	pkgcore.publish(root + '/repository', 'fixture', root + '/seed', 12, 2000000000)!
	good := pkgcore.Repository{ id: 'fixture', url: 'file://' + root + '/repository',
		public_key: 'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a' }
	pkgcore.enroll_repository(root, good, true)!
	service := pkgcore.Service{ root: root, offline: true }
	service.refresh()!
	installed := service.transact('install', ['data'], pkgcore.TransactionOptions{})!
	directory := pkgcore.state_directory(root)
	valid_history := pkgcore.repository_status(root)!.history
	// Model records created before invalid curve keys were excluded. Keep an
	// independent valid-key floor so recovery must preserve both identities.
	weak := pkgcore.Repository{ ...good, public_key: '01' + '00'.repeat(31) }
	text := pkgcore.canonical_index(pkgcore.Index{ repository: 'fixture', sequence: 4000, expires: 1 })!
	old_floor := pkgcore.RepositoryFloor{ id: 'fixture', public_key: weak.public_key, sequence: 4000, index_sha256: digest(text) }
	history := pkgcore.TrustHistory{ repositories: [old_floor, valid_history[0]] }
	history_path := directory + '/trust-history.json'
	os.write_file(history_path, json2.encode(history) + '\n')!
	os.write_file(config_path, json2.encode(pkgcore.Config{ ...initial, repositories: [weak] }))!
	state := pkgcore.State{ ...installed, packages: [pkgcore.Installed{ ...installed.packages[0], public_key: weak.public_key }] }
	os.write_file(directory + '/generations/' + state.generation.str() + '/state.json', json2.encode(state))!
	os.write_file(directory + '/catalog.json', json2.encode([pkgcore.Snapshot{ repository: weak, text: text, signature: '01' + '00'.repeat(63) }]))!
	personal := root + '/home/user/.local/share/vinix-apps/data'
	os.mkdir_all(personal)!
	os.write_file(personal + '/note', 'keep this note')!
	retained := os.read_file(history_path)!
	cache := os.read_file(directory + '/catalog.json')!
	if _ := service.refresh() { assert false } else { assert err.msg().contains('publisher key') }
	if _ := pkgcore.repository_status(root) { assert false } else { assert err.msg().contains('publisher key') }
	if revoke {
		mut review := pkgcore.review_repository(root, 'revoke', weak, true)!
		pkgcore.revoke_repository_reviewed(root, weak.id, review.fingerprint)!
		review.close()
		assert pkgcore.load_config(root)!.repositories.len == 0
	}
	pkgcore.publish(root + '/repository', 'fixture', root + '/seed', 14, 2000000000)!
	if before {
		if _ := pkgcore.review_repository(root, 'enroll', good, true) { assert false } else {
			assert err.msg().contains('publisher key')
		}
		assert os.read_file(history_path)! == retained && os.read_file(directory + '/catalog.json')! == cache
		println('Publisher recovery baseline: reviewed revocation leaves recorded invalid cache blocking valid re-enrollment PASS')
		return
	}
	if revoke {
		status := pkgcore.repository_status(root)!
		assert status.repositories.len == 0 && status.history == history.repositories
	}
	configuration := os.read_file(config_path)!
	for invalid in [pkgcore.TrustHistory{ repositories: valid_history },
		pkgcore.TrustHistory{ repositories: [pkgcore.RepositoryFloor{ ...old_floor, index_sha256: 'a'.repeat(64) }, valid_history[0]] },
		pkgcore.TrustHistory{ repositories: [pkgcore.RepositoryFloor{ ...old_floor, sequence: 4001 }, valid_history[0]] }] {
		os.write_file(history_path, json2.encode(invalid))!
		if _ := pkgcore.review_repository(root, 'enroll', good, true) { assert false } else { assert err.msg().contains('publisher key') }
		if _ := pkgcore.enroll_repository(root, good, true) { assert false } else { assert err.msg().contains('publisher key') }
		assert os.read_file(config_path)! == configuration && os.read_file(directory + '/catalog.json')! == cache
		assert service.state()! == state
	}
	os.write_file(history_path, retained)!
	os.write_file(directory + '/catalog.json', json2.encode([pkgcore.Snapshot{ repository: weak, text: text + ' ', signature: '01' + '00'.repeat(63) }]))!
	if _ := pkgcore.review_repository(root, 'enroll', good, true) { assert false } else { assert err.msg().contains('publisher key') }
	assert os.read_file(config_path)! == configuration && os.read_file(history_path)! == retained
	os.write_file(directory + '/catalog.json', cache)!
	mut review := pkgcore.review_repository(root, 'enroll', good, true)!
	defer { review.close() }
	assert review.remembered_sequence == 12 && review.sequence == 14
	assert review.previous_public_key == if revoke { '' } else { weak.public_key }
	assert os.read_file(config_path)! == configuration && os.read_file(history_path)! == retained
	assert os.read_file(directory + '/catalog.json')! == cache && service.state()! == state
	// A changed retained floor invalidates a review before trust is published.
	os.write_file(history_path, json2.encode(pkgcore.TrustHistory{ repositories: [old_floor,
		pkgcore.RepositoryFloor{ ...valid_history[0], sequence: 13 }] }))!
	if _ := pkgcore.enroll_repository_reviewed(root, good, true, review.fingerprint) { assert false } else {
		assert err.msg().contains('stale')
	}
	assert os.read_file(config_path)! == configuration && os.read_file(directory + '/catalog.json')! == cache
	os.write_file(history_path, retained)!
	// The exception only retires old cache. It cannot admit a bad live signature.
	index_path := root + '/repository/index.json'
	index := os.read_file(index_path)!
	os.write_file(index_path, index + ' ')!
	if _ := pkgcore.enroll_repository_reviewed(root, good, true, review.fingerprint) { assert false } else {
		assert err.msg().contains('signature verification failed')
	}
	assert os.read_file(config_path)! == configuration && os.read_file(history_path)! == retained
	os.write_file(index_path, index)!
	pkgcore.enroll_repository_reviewed(root, good, true, review.fingerprint)!
	assert pkgcore.load_config(root)!.repositories == [good]
	assert os.read_file(directory + '/catalog.json')! == cache && service.state()! == state
	status := pkgcore.repository_status(root)!
	assert status.history.len == 2 && old_floor in status.history
	assert status.history.any(it.public_key == good.public_key && it.sequence == 14)
	service.refresh()!
	assert pkgcore.read_snapshots(directory)!.len == 1 && pkgcore.read_snapshots(directory)![0].repository == good
	mut update := service.review('upgrade', [])!
	defer { update.close() }
	repaired := service.transact('upgrade', [], pkgcore.TransactionOptions{ expected_review: update.fingerprint })!
	assert repaired.generation > state.generation && repaired.packages[0].public_key == good.public_key
	if _ := service.rollback('') { assert false } else { assert err.msg().contains('publisher key') }
	assert service.state()! == repaired && os.read_file(personal + '/note')! == 'keep this note'
	mut removal := service.review('remove', ['data'])!
	defer { removal.close() }
	service.transact('remove', ['data'], pkgcore.TransactionOptions{ expected_review: removal.fingerprint })!
	assert service.state()!.packages.len == 0 && os.read_file(personal + '/note')! == 'keep this note'
	assert old_floor in pkgcore.repository_status(root)!.history
	println('PUBLISHER RECOVERY ' + if revoke { 'revocation/re-enrollment' } else { 'reviewed key replacement' } + ': exact retired floor retained; stale review/live tamper/old rollback refused; upgrade/uninstall/data PASS')
}

fn check() ! {
	assert os.args.len in [2, 3]
	before := os.args.len == 3 && os.args[2] == '--expect-blocked'
	root := os.abs_path(os.args[1]); assert !os.exists(root) && !os.is_link(root)
	os.mkdir(root)!
	defer { os.rmdir_all(root) or {} }
	if before { exercise(root + '/before', true, true)!; return }
	for revoke in [false, true] { exercise(root + if revoke { '/revoke' } else { '/replace' }, revoke, false)! }
	println('Publisher cache recovery qualification passed')
}

fn main() { check() or { eprintln(err); exit(1) } }
