// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.pkgcore
import tools.packages.pkgprotocol

const revocation_record = package_disk + '/revocation-cut.json'
const revocation_source = package_disk + '/repository'
const revocation_offline_source = package_disk + '/publisher-offline'
const revocation_data = package_test_root + '/home/alex/.local/share/vinix-apps/recovery-app'

struct RevocationCutRecord {
	before   PackageDiskState
	approval string
}

fn prepare_revocation_cut() !RevocationCutRecord {
	config := package_disk_setup()!
	package_root_cli(['--offline', 'upgrade'])!
	publisher := config.repositories[0]
	state := pkgcore.read_state(package_state, config.architecture)!
	assert state.generation == 2 && state.previous == 1
	os.rename(revocation_source, revocation_offline_source)!
	before := observe_package_disk()!
	mut review := pkgprotocol.decode_repository_review(package_root_cli(['--offline', 'repo-review',
		'revoke', publisher.id])!)!
	approval := review.fingerprint.clone()
	assert review.operation == 'revoke' && review.id == publisher.id
	assert review.url == publisher.url && review.public_key == publisher.public_key
	review.close()
	assert observe_package_disk()! == before
	return RevocationCutRecord{ before: before, approval: approval }
}

fn check_revocation_launch(config pkgcore.Config, revoked bool) ! {
	mut state := pkgcore.read_state(package_state, config.architecture)!
	defer { state.close() }
	if mut launch := pkgcore.launch_plan(config, package_state, state, 'recovery-app',
		revocation_data, 1000, 1000, []) {
		defer { launch.close() }
		assert !revoked && launch.program == '/usr/bin/vinix-sandbox'
	} else {
		assert revoked && err.msg().contains('publisher key has been revoked'), err.msg()
	}
}

fn qualify_package_revocation_recovery(mut t Test) ! {
	package_disk_mount()!
	phase := t.scenario.all_after_last('-')
	if !os.is_file(revocation_record) {
		record := prepare_revocation_cut()!
		pkgcore.atomic_write(revocation_record, json2.encode(record))!
		// Flush preparation only. The revocation CLI supplies its own durability.
		C.sync()
		result := run(['/usr/share/package-fixtures/revocation-cut-cli', '--root', package_test_root,
			'--offline', 'repo-apply', record.approval, 'revoke', 'fixture'], '', none, none)
		return error('revocation CLI exited before QEMU was killed: ' + result.output)
	}

	record := json2.decode[RevocationCutRecord](os.read_file(revocation_record)!)!
	before := record.before
	recovered := observe_package_disk()!
	baseline := json2.decode[pkgcore.Config](before.config)!
	publisher := baseline.repositories[0]
	config := pkgcore.load_config(package_test_root)!
	committed := phase == 'configuration'
	assert recovered.history == before.history && recovered.catalog == before.catalog
	assert recovered.active == before.active && recovered.current == before.current
	assert config.architecture == baseline.architecture && config.launch_user == baseline.launch_user
	assert config.policy == baseline.policy
	assert config.repositories == if committed { []pkgcore.Repository{} } else { baseline.repositories }
	assert (recovered.config != before.config) == committed
	assert !os.exists(revocation_source) && os.is_dir(revocation_offline_source)
	package_root_cli(['--offline', 'verify'])!
	check_revocation_launch(config, committed)!

	apply := ['repo-apply', record.approval, 'revoke', publisher.id]
	if committed {
		expect_package_root_refusal(apply, 'repository is not enrolled')
		assert observe_package_disk()! == recovered
	} else {
		package_root_cli(['--offline', 'review', 'rollback'])!
		assert observe_package_disk()! == before
		package_root_cli(['--offline', ...apply])!
	}
	revoked := pkgcore.load_config(package_test_root)!
	assert revoked.repositories.len == 0
	check_revocation_launch(revoked, true)!
	expect_package_root_refusal(['rollback'], 'rollback repository key is no longer trusted')
	disabled := observe_package_disk()!
	assert disabled.history == before.history && disabled.catalog == before.catalog
	assert disabled.active == before.active && disabled.current == before.current
	t.say('PACKAGE REVOCATION RETAINED ${phase} expected trust and exact history catalog generation PASS')

	package_root_cli(['--offline', 'update'])!
	assert pkgcore.read_snapshots(package_state)!.len == 0
	package_root_cli(['--offline', 'remove', 'recovery-app'])!
	assert pkgcore.read_state(package_state, config.architecture)!.packages.len == 0
	assert !os.exists(package_state + '/current/share/applications/vinix-recovery-app.desktop')
	expect_package_root_refusal(['rollback'], 'rollback repository key is no longer trusted')
	maintained := observe_package_disk()!
	assert maintained.config == disabled.config && maintained.history == before.history
	data := revocation_data + '/personal.txt'
	assert read_text(data) == 'personal data survives\n' && owner_of(data) == 1000
	assert mode_of(data) == 0o600

	os.rename(revocation_offline_source, revocation_source)!
	mut review := pkgprotocol.decode_repository_review(package_root_cli(['--offline', 'repo-review',
		'enroll', publisher.id, publisher.url, publisher.public_key])!)!
	assert review.sequence == 2 && review.remembered_sequence == 2
	review.close()
	pkgcore.publish(revocation_source, publisher.id, package_disk + '/signing-seed', 1,
		time.now().unix() + 3600)!
	expect_package_root_refusal(['repo-review', 'enroll', publisher.id, publisher.url,
		publisher.public_key], 'repository rollback or sequence equivocation refused')
	assert observe_package_disk()! == maintained
	t.say('PACKAGE REVOCATION RECOVERY ${phase} disabled launch and rollback retained data removal replay floor PASS')
}

fn scenario_package_revocation_recovery(mut t Test) {
	qualify_package_revocation_recovery(mut t) or { t.check(false, err.msg()) }
}
