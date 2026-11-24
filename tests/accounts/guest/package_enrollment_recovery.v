// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import time
import tools.packages.pkgcore
import tools.packages.pkgprotocol

const enrollment_record = package_disk + '/enrollment-cut.json'
const enrollment_source = package_disk + '/field'
const enrollment_workspace = package_state + '/enrollment'

struct EnrollmentCutRecord {
	before     PackageDiskState
	repository pkgcore.Repository
	approval   string
}

fn enrollment_arguments(repository pkgcore.Repository) []string {
	return ['enroll', repository.id, repository.url, repository.public_key]
}

fn prepare_enrollment_cut() !EnrollmentCutRecord {
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	source := package_disk + '/source'
	os.mkdir_all(source + '/bin')!
	os.cp('/sbin/init', source + '/bin/app')!
	os.chmod(source + '/bin/app', 0o755)!
	os.mkdir_all(package_test_root + '/etc/vinix-packages')!
	installed_seed := '/tmp/enrollment-baseline.seed'
	field_seed := '/tmp/enrollment-field.seed'
	defer {
		os.rm(installed_seed) or {}
		os.rm(field_seed) or {}
	}
	installed := pkgcore.Repository{ id: 'fixture', url: 'file://' + package_disk + '/repository',
		public_key: pkgcore.keygen(installed_seed)! }
	field := pkgcore.Repository{ id: 'field', url: 'file://' + enrollment_source,
		public_key: pkgcore.keygen(field_seed)! }
	config := pkgcore.Config{ architecture: architecture, repositories: [installed],
		policy: pkgcore.Policy{ reserve_bytes: 0 } }
	pkgcore.atomic_write(package_test_root + '/etc/vinix-packages/config.json', json2.encode(config))!
	expires := time.now().unix() + 86400
	package_disk_version('1.0.0', architecture)!
	pkgcore.publish(package_disk + '/repository', installed.id, installed_seed, 1, expires)!
	package_root_cli(['--offline', 'update'])!
	package_root_cli(['--offline', 'install', 'recovery-app'])!

	manifest := pkgcore.Package{ id: 'field-app', version: '1.0.0', architecture: architecture,
		name: 'Field fixture', license: 'GPL-2.0-or-later', kind: 'native', entrypoint: 'bin/app' }
	manifest_path := package_disk + '/field-manifest.json'
	os.write_file(manifest_path, json2.encode(manifest))!
	pkgcore.pack(manifest_path, source, enrollment_source)!
	for i, name in ['older', 'exact', 'equivocated']! {
		sequence := if i == 0 { u64(1) } else { u64(2) }
		pkgcore.publish(enrollment_source, field.id, field_seed, sequence, expires + i)!
		saved := package_disk + '/' + name
		os.mkdir(saved)!
		for leaf in ['index.json', 'index.sig']! {
			os.cp(enrollment_source + '/' + leaf, saved + '/' + leaf)!
		}
	}
	select_enrollment_index('exact')!
	before := observe_package_disk()!
	mut review := pkgprotocol.decode_repository_review(package_root_cli(['--offline', 'repo-review',
		...enrollment_arguments(field)])!)!
	approval := review.fingerprint.clone()
	assert review.sequence == 2 && review.remembered_sequence == 0 && review.previous_url == ''
	review.close()
	assert observe_package_disk()! == before
	return EnrollmentCutRecord{ before: before, repository: field, approval: approval }
}

fn select_enrollment_index(name string) ! {
	for leaf in ['index.json', 'index.sig']! {
		text := os.read_file(package_disk + '/' + name + '/' + leaf)!
		pkgcore.atomic_write(enrollment_source + '/' + leaf, text)!
	}
}

fn reject_enrollment_command(arguments []string, diagnostic string) {
	result := run(['/usr/bin/vinix-package', '--root', package_test_root, '--offline', ...arguments],
		'', none, none)
	assert result.status == 1 && result.output.contains(diagnostic), result.output
}

fn qualify_package_enrollment_recovery(mut t Test) ! {
	package_disk_mount()!
	phase := t.scenario.all_after_last('-')
	if !os.is_file(enrollment_record) {
		record := prepare_enrollment_cut()!
		pkgcore.atomic_write(enrollment_record, json2.encode(record))!
		// Only preparation syncs globally. The CLI supplies its own durability.
		C.sync()
		result := run(['/usr/share/package-fixtures/enrollment-cut-cli', '--root', package_test_root,
			'--offline', 'repo-apply', record.approval, ...enrollment_arguments(record.repository)], '', none, none)
		return error('enrollment CLI exited before QEMU was killed: ' + result.output)
	}
	record := json2.decode[EnrollmentCutRecord](os.read_file(enrollment_record)!)!
	before := record.before
	recovered := observe_package_disk()!
	assert recovered.active == before.active && recovered.current == before.current && recovered.catalog == before.catalog
	assert os.is_dir(enrollment_workspace)
	config := pkgcore.load_config(package_test_root)!
	baseline := json2.decode[pkgcore.Config](before.config)!
	enabled := phase == 'configuration'
	expected_repositories := if enabled { [record.repository, ...baseline.repositories] } else { baseline.repositories }
	assert config.repositories == expected_repositories && config.architecture == baseline.architecture
	assert config.launch_user == baseline.launch_user && config.policy == baseline.policy
	assert (recovered.config != before.config) == enabled
	expected := os.read_file(package_disk + '/exact/index.json')!
	field_floor := pkgcore.RepositoryFloor{ id: record.repository.id, public_key: record.repository.public_key,
		sequence: 2, index_sha256: sha256.hexhash(expected) }
	old_history := json2.decode[pkgcore.TrustHistory](before.history)!
	status := json2.decode[pkgcore.RepositoryStatus](package_root_cli(['--json', 'repo-list'])!)!
	assert status.repositories == expected_repositories
	assert status.history == [field_floor, ...old_history.repositories]
	package_root_cli(['--offline', 'verify'])!

	intent := enrollment_arguments(record.repository)
	for name in ['older', 'equivocated']! {
		select_enrollment_index(name)!
		reject_enrollment_command(['repo-review', ...intent], 'repository rollback or sequence equivocation refused')
		assert observe_package_disk()! == recovered
	}
	select_enrollment_index('exact')!
	reject_enrollment_command(['repo-apply', record.approval, ...intent], 'repository review is stale')
	assert observe_package_disk()! == recovered
	t.say('PACKAGE ENROLLMENT RETAINED ${phase} durable floor and expected trust configuration PASS')

	review := pkgprotocol.decode_repository_review(package_root_cli(['--offline', 'repo-review', ...intent])!)!
	assert review.sequence == 2 && review.remembered_sequence == 2 && review.fingerprint != record.approval
	assert review.index_sha256 == field_floor.index_sha256
	assert (review.previous_public_key == record.repository.public_key) == enabled
	package_root_cli(['--offline', 'repo-apply', review.fingerprint, ...intent])!
	confirmed := observe_package_disk()!
	assert confirmed.history == recovered.history && confirmed.catalog == before.catalog
	assert confirmed.active == before.active && confirmed.current == before.current && !os.exists(enrollment_workspace)
	assert pkgcore.load_config(package_test_root)!.repositories == [record.repository, ...baseline.repositories]
	package_root_cli(['--offline', 'update', record.repository.id])!
	package_root_cli(['--offline', 'info', 'field-app'])!
	package_root_cli(['--offline', 'verify'])!
	refreshed := observe_package_disk()!
	snapshots := pkgcore.read_snapshots(package_state)!
	old_snapshots := json2.decode[[]pkgcore.Snapshot](before.catalog)!
	signature := os.read_file(package_disk + '/exact/index.sig')!.trim_space()
	assert snapshots.len == 2 && snapshots[1] == old_snapshots[0]
	assert snapshots[0] == pkgcore.Snapshot{ repository: record.repository, text: expected, signature: signature }
	assert refreshed.active == before.active && refreshed.current == before.current
	assert refreshed.config == confirmed.config && refreshed.history == confirmed.history
	assert os.ls(package_state + '/generations')! == ['1']
	t.say('PACKAGE ENROLLMENT RECOVERY ${phase} new review restored the signed catalog and retained generation PASS')
}

fn scenario_package_enrollment_recovery(mut t Test) {
	qualify_package_enrollment_recovery(mut t) or { t.check(false, err.msg()) }
}
