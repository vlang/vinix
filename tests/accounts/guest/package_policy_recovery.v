// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import tools.packages.pkgcore

const policy_cut_record = package_disk + '/policy-cut.json'
const policy_cut_document = package_disk + '/organization-policy.json'
const policy_cut_data = package_test_root + '/home/alex/.local/share/vinix-apps/recovery-app'

struct PolicyCutRecord {
	before          PackageDiskState
	previous_policy string
	approval        string
}

fn prepare_policy_cut() !PolicyCutRecord {
	config := package_disk_setup()!
	package_root_cli(['--offline', 'upgrade'])!
	mut state := pkgcore.read_state(package_state, config.architecture)!
	defer { state.close() }
	assert state.generation == 2 && state.previous == 1
	before := observe_package_disk()!
	previous_policy := package_root_cli(['--offline', 'policy'])!
	previous := json2.decode[pkgcore.PolicyDocument](previous_policy)!
	proposal := pkgcore.PolicyDocument{
		architecture: config.architecture
		policy: pkgcore.Policy{ ...previous.policy, allowed: ['organization-approved'] }
	}
	pkgcore.atomic_write(policy_cut_document, json2.encode(proposal))!
	mut review := pkgcore.decode_policy_review(package_root_cli(['--offline', 'policy-review', policy_cut_document])!)!
	defer { review.close() }
	assert review.generation == state.generation && review.rows.len == 1
	assert review.rows[0].id == 'recovery-app' && review.rows[0].diagnostic_before == ''
	assert review.rows[0].diagnostic_after.contains('blocked by organization allowlist')
	assert observe_package_disk()! == before
	return PolicyCutRecord{ before: before, previous_policy: previous_policy, approval: review.fingerprint.clone() }
}

fn check_policy_cut_launch(config pkgcore.Config, blocked bool) ! {
	mut state := pkgcore.read_state(package_state, config.architecture)!
	defer { state.close() }
	if mut launch := pkgcore.launch_plan(config, package_state, state, 'recovery-app',
		policy_cut_data, 1000, 1000, []) {
		defer { launch.close() }
		assert !blocked && launch.program == '/usr/bin/vinix-sandbox'
	} else {
		assert blocked && err.msg().contains('blocked by organization allowlist'), err.msg()
	}
}

fn qualify_package_policy_recovery(mut t Test) ! {
	package_disk_mount()!
	phase := t.scenario.all_after_last('-')
	if !os.is_file(policy_cut_record) {
		record := prepare_policy_cut()!
		pkgcore.atomic_write(policy_cut_record, json2.encode(record))!
		// Only preparation uses a global sync. The CLI flushes the policy change.
		C.sync()
		result := run(['/usr/share/package-fixtures/policy-cut-cli', '--root', package_test_root,
			'--offline', 'policy-apply', record.approval, policy_cut_document], '', none, none)
		return error('policy CLI exited before QEMU was killed: ' + result.output)
	}

	record := json2.decode[PolicyCutRecord](os.read_file(policy_cut_record)!)!
	before := record.before
	recovered := observe_package_disk()!
	baseline := json2.decode[pkgcore.Config](before.config)!
	proposal := json2.decode[pkgcore.PolicyDocument](os.read_file(policy_cut_document)!)!
	committed := phase == 'configuration'
	config := pkgcore.load_config(package_test_root)!
	expected := if committed { pkgcore.Config{ ...baseline, policy: proposal.policy } } else { baseline }
	assert config == expected && (recovered.config != before.config) == committed
	assert recovered == PackageDiskState{ ...before, config: recovered.config }
	package_root_cli(['--offline', 'verify'])!
	check_policy_cut_launch(config, committed)!

	apply := ['policy-apply', record.approval, policy_cut_document]
	if committed {
		expect_package_root_refusal(apply, 'organization policy review is stale')
		assert observe_package_disk()! == recovered
	} else {
		package_root_cli(['--offline', 'review', 'rollback'])!
		assert observe_package_disk()! == before
		package_root_cli(['--offline', ...apply])!
	}
	restricted := pkgcore.load_config(package_test_root)!
	assert restricted == pkgcore.Config{ ...baseline, policy: proposal.policy }
	check_policy_cut_launch(restricted, true)!
	expect_package_root_refusal(['rollback'], 'blocked by organization allowlist')
	package_root_cli(['--offline', 'verify'])!
	retained := observe_package_disk()!
	assert retained == PackageDiskState{ ...before, config: retained.config }
	t.say('PACKAGE POLICY RETAINED ${phase} expected policy and exact history catalog generation PASS')

	restore := json2.decode[pkgcore.PolicyDocument](record.previous_policy)!
	pkgcore.atomic_write(policy_cut_document, record.previous_policy)!
	mut review := pkgcore.decode_policy_review(package_root_cli(['--offline', 'policy-review', policy_cut_document])!)!
	defer { review.close() }
	assert review.generation == 2 && review.rows.len == 1
	assert review.rows[0].diagnostic_before.contains('blocked by organization allowlist')
	assert review.rows[0].diagnostic_after == ''
	package_root_cli(['--offline', 'policy-apply', review.fingerprint, policy_cut_document])!
	restored := pkgcore.load_config(package_test_root)!
	assert restored == pkgcore.Config{ ...baseline, policy: restore.policy }
	check_policy_cut_launch(restored, false)!
	package_root_cli(['--offline', 'rollback'])!
	package_root_cli(['--offline', 'verify'])!
	mut state := pkgcore.read_state(package_state, baseline.architecture)!
	defer { state.close() }
	assert state.packages.len == 1 && state.packages[0].package.version == '1.0.0'
	maintained := observe_package_disk()!
	assert maintained.catalog == before.catalog && maintained.history == before.history
	data := policy_cut_data + '/personal.txt'
	assert read_text(data) == 'personal data survives\n' && owner_of(data) == 1000
	assert mode_of(data) == 0o600
	t.say('PACKAGE POLICY RECOVERY ${phase} reviewed policy restored launch and rollback retained data PASS')
}

fn scenario_package_policy_recovery(mut t Test) {
	qualify_package_policy_recovery(mut t) or { t.check(false, err.msg()) }
}
