// SPDX-License-Identifier: GPL-2.0-or-later
module audiocontinue

import json2
import os
import time
import nativeguard

#include <errno.h>

fn boundary_cleanup2(path string) {
	if os.getenv('AUDIO_CONTINUATION_RETAIN_FIXTURES') != '1' { os.rmdir_all(path) or {} }
}

fn boundary_root2() !string {
	parent := os.getenv('AUDIO_CONTINUATION_TEST_ROOT')
	ordinary2(parent, 'directory')!
	root := parent + '/boundary2-' + os.getpid().str() + '-' + time.sys_mono_now().str()
	os.mkdir(root, mode: 0o700)!
	return root
}

fn boundary_plan2(root string) Plan2 {
	return Plan2{state_root: root, source_root: root + '-source',
		donor_manifest_path: root + '-donor.json', donor_manifest_sha256: '1'.repeat(64),
		legacy_plan_path: root + '-legacy.json', legacy_plan_sha256: reviewed_legacy_plan2,
		source_manifest_path: root + '-source.json', source_manifest_sha256: '2'.repeat(64),
		source_base_revision: 'a'.repeat(40), controller_sha256: '3'.repeat(64),
		preparation_reserve_bytes: u64(200) << 20, receipt_reserve_bytes: u64(64) << 20,
		wall_ms: 3000000}
}

fn boundary_preparation2(p Plan2) Preparation2 {
	return Preparation2{state_root: p.state_root, completed_at: 1,
		donor_manifest_path: p.donor_manifest_path, donor_manifest_sha256: p.donor_manifest_sha256,
		legacy_plan_path: p.legacy_plan_path, legacy_plan_sha256: p.legacy_plan_sha256,
		source_manifest_path: p.source_manifest_path, source_manifest_sha256: p.source_manifest_sha256,
		source_root: p.source_root, source_base_revision: p.source_base_revision,
		controller_sha256: p.controller_sha256, extras_path: 'tools/root',
		scenarios: ['packages-audio-basic', 'packages-audio-lifecycle', 'packages-audio-seat']}
}

fn test_schema_rejects_wrong_format_unknown_duplicate_or_noncanonical_fields() {
	p := boundary_plan2('/charged/fixture')
	text := json2.encode(p) + '\n'
	assert (decode_plan2(text) or { panic(err) }) == p
	for changed in [text.replace('"format":2', '"format":1'),
		text[..text.len - 2] + ',"unexpected":true}\n',
		text.replace('"format":2', '"format":2,"format":2'), text.trim_space(),
		text.replace('"source_base_revision":"' + p.source_base_revision + '"', '"source_revision":"' + p.source_base_revision + '"')] {
		assert changed != text
		mut refused := false
		decode_plan2(changed) or { refused = true; Plan2{} }
		assert refused
	}
}

fn test_frozen_schema_and_candidate_mode_are_separate() {
	root := boundary_root2() or { panic(err) }
	defer { boundary_cleanup2(root) }
	p := boundary_plan2(root)
	prepared := boundary_preparation2(p)
	text := json2.encode(prepared) + '\n'
	assert (decode_preparation2(text) or { panic(err) }) == prepared
	for changed in [text.replace('"format":2', '"format":1'),
		text[..text.len - 2] + ',"native_qualification":true}\n'] {
		mut refused := false
		decode_preparation2(changed) or { refused = true; Preparation2{} }
		assert refused
	}
	write_new2(root + '/preparation2.pending.json', text) or { panic(err) }
	preparation_bindings2(prepared, p, root + '/preparation2.pending.json', true) or { panic(err) }
	mut refused := false
	preparation_bindings2(prepared, p, root + '/preparation2.json', false) or { refused = true }
	assert refused
	write_new2(root + '/preparation2.json', text) or { panic(err) }
	refused = false
	preparation_bindings2(prepared, p, root + '/preparation2.pending.json', true) or { refused = true }
	assert refused
}

struct BoundaryCompletion2 {
	root string
	fail string
}

fn (c BoundaryCompletion2) gate(name string) ! {
	if os.exists(c.root + '/preparation2.json') { return error('completion visible before ' + name) }
	if c.fail == name { return error('injected real completion gate refusal: ' + name) }
}

fn (c BoundaryCompletion2) verify_candidate() ! { c.gate('candidate')! }
fn (c BoundaryCompletion2) verify_resources() ! { c.gate('resources')! }
fn (c BoundaryCompletion2) verify_cancellation() ! { c.gate('cancellation')! }
fn (c BoundaryCompletion2) verify_deadline() ! { c.gate('deadline')! }

fn test_every_late_gate_failure_keeps_completion_absent_even_if_refusal_write_fails() {
	base := boundary_root2() or { panic(err) }
	defer { boundary_cleanup2(base) }
	for failure in ['candidate', 'resources', 'cancellation', 'deadline'] {
		root := base + '/' + failure
		os.mkdir(root) or { panic(err) }
		write_new2(root + '/preparation2.pending.json', 'pending-only\n') or { panic(err) }
		write_new2(root + '/refusal2.json', 'preserved earlier diagnostic\n') or { panic(err) }
		mut refused := false
		complete_candidate2(root, '1'.repeat(64), BoundaryCompletion2{root: root, fail: failure}) or {
			refused = true
			''
		}
		assert refused
		refused = false
		write_new2(root + '/refusal2.json', 'this reporting write must fail\n') or { refused = true }
		assert refused
		assert !os.exists(root + '/preparation2.json')
		assert (os.read_file(root + '/preparation2.pending.json') or { panic(err) }) == 'pending-only\n'
	}
}

fn test_successful_publication_is_exclusive_and_has_no_pending_alias() {
	root := boundary_root2() or { panic(err) }
	defer { boundary_cleanup2(root) }
	write_new2(root + '/preparation2.pending.json', 'verified candidate bytes\n') or { panic(err) }
	sha := digest2(root + '/preparation2.pending.json') or { panic(err) }
	assert (complete_candidate2(root, sha, BoundaryCompletion2{root: root}) or { panic(err) }) == sha
	assert !os.exists(root + '/preparation2.pending.json')
	assert (digest2(root + '/preparation2.json') or { panic(err) }) == sha
	assert (os.lstat(root + '/preparation2.json') or { panic(err) }).nlink == 1
}

fn test_exclusive_publication_preserves_existing_destination_and_pending_evidence() {
	root := boundary_root2() or { panic(err) }
	defer { boundary_cleanup2(root) }
	write_new2(root + '/preparation2.pending.json', 'pending\n') or { panic(err) }
	write_new2(root + '/preparation2.json', 'existing destination\n') or { panic(err) }
	mut refused := false
	publish_candidate2(root) or { refused = true }
	assert refused
	assert (os.read_file(root + '/preparation2.json') or { panic(err) }) == 'existing destination\n'
	assert (os.read_file(root + '/preparation2.pending.json') or { panic(err) }) == 'pending\n'
}

fn boundary_elf2(path string) ! {
	mut bytes := []u8{len: 64}
	for i, value in [u8(127), `E`, `L`, `F`, 2, 1, 1] { bytes[i] = value }
	bytes[16] = 2
	bytes[18] = 183
	os.write_file(path, bytes.bytestr())!
	os.chmod(path, 0o755)!
}

fn test_each_of_eight_frozen_targets_requires_execute_permission() {
	root := boundary_root2() or { panic(err) }
	defer { boundary_cleanup2(root) }
	mut fresh := map[string]Fresh2{}
	roles := ['cross-probe', 'sandbox', 'tone', 'guest', 'package-cli', 'account-cli', 'session-cli', 'authd']
	for role in roles {
		boundary_elf2(root + '/' + role) or { panic(err) }
		fresh[role] = Fresh2{path: role, kind: 'target', sha256: digest2(root + '/' + role) or { panic(err) }}
	}
	p := Preparation2{state_root: root, fresh: fresh}
	targets2(p) or { panic(err) }
	for role in roles {
		os.chmod(root + '/' + role, 0o644) or { panic(err) }
		mut refused := false
		targets2(p) or { refused = true }
		assert refused
		os.chmod(root + '/' + role, 0o755) or { panic(err) }
	}
}

fn test_target_rejects_truncated_and_wrong_architecture_elf() {
	root := boundary_root2() or { panic(err) }
	defer { boundary_cleanup2(root) }
	path := root + '/target'
	boundary_elf2(path) or { panic(err) }
	mut bytes := os.read_bytes(path) or { panic(err) }
	bytes[18] = 62
	os.write_file(path, bytes.bytestr()) or { panic(err) }
	mut refused := false
	target_elf2(path) or { refused = true }
	assert refused
	os.write_file(path, '\x7fELF') or { panic(err) }
	refused = false
	target_elf2(path) or { refused = true }
	assert refused
}

fn test_reviewed_source_content_is_authoritative_and_head_is_only_base_provenance() {
	base := boundary_root2() or { panic(err) }
	defer { boundary_cleanup2(base) }
	root := base + '/source'
	git := base + '/git-metadata'
	os.mkdir(root) or { panic(err) }
	os.mkdir(git) or { panic(err) }
	revision := 'a'.repeat(40)
	write_new2(git + '/HEAD', revision + '\n') or { panic(err) }
	write_new2(root + '/.git', 'gitdir: ' + git + '\n') or { panic(err) }
	write_new2(root + '/reviewed.v', 'reviewed patch content, no clean-commit claim\n') or { panic(err) }
	source := Source2{root: root, base_revision: revision,
		entries: inventory2({'source': root}) or { panic(err) }}
	assert (decode_source2(json2.encode(source) + '\n') or { panic(err) }) == source
	verify_source2(source) or { panic(err) }
	os.write_file(root + '/reviewed.v', 'unreviewed later mutation\n') or { panic(err) }
	mut refused := false
	verify_source2(source) or { refused = true }
	assert refused
	// A separately reviewed new complete manifest may intentionally contain a
	// patch on the same base; HEAD is not misrepresented as a content witness.
	reviewed := Source2{...source, entries: inventory2({'source': root}) or { panic(err) }}
	verify_source2(reviewed) or { panic(err) }
	refused = false
	decode_source2(json2.encode(Source2{...reviewed, content_contract: 'clean-commit'}) + '\n') or {
		refused = true
		Source2{}
	}
	assert refused
}

fn boundary_command_engine2(root string) Engine2 {
	return Engine2{plan: Plan2{state_root: root},
		legacy: LegacyPlan2{roots: {'compiler': '/qualified/compiler'},
			files: {'clang': '/qualified/clang', 'backend': '/qualified/backend'}},
		donor: Donor2{roots: {'capture': '/immutable/capture'}, roles: expected_roles2()},
		plan_path: '/charged/plan.json', plan_sha256: '1'.repeat(64)}
}

fn boundary_command_receipts2(root string, engine Engine2) !Preparation2 {
	result := nativeguard.Result{group_observed: true,
		cleanup: nativeguard.Cleanup{pid: 4242, reaped: true, group_empty: true,
			final_wait: -1, final_errno: C.ECHILD, exit_code: 0}}
	for spec in command_specs2(engine.command_context())! {
		path := root + '/' + spec.log_relative
		os.mkdir_all(os.dir(path))!
		write_new2(path, 'INTENTIONAL SYNTHETIC COMMAND RECEIPT FIXTURE\n')!
		write_new2(path + '.argv.json', json2.encode(spec.argv) + '\n')!
		write_new2(path + '.environment.json', json2.encode(spec.environment) + '\n')!
		write_new2(path + '.result.json', json2.encode(result) + '\n')!
		write_new2(path + '.error.json', json2.encode({'error': ''}) + '\n')!
	}
	return Preparation2{state_root: root, tree: capture_owned2(root, [], Donor2{})!}
}

fn test_frozen_command_wrapper_binds_source_flags_output_role_and_environment() {
	root := boundary_root2() or { panic(err) }
	defer { boundary_cleanup2(root) }
	engine := boundary_command_engine2(root)
	prepared := boundary_command_receipts2(root, engine) or { panic(err) }
	command_receipts2(prepared, engine) or { panic(err) }
	role := 'cross-adapter-build.log'
	spec := command_spec2(engine.command_context(), role) or { panic(err) }
	argv_path := root + '/' + role + '.argv.json'
	for kind in ['source', 'flag', 'output', 'extra', 'different-role'] {
		mut args := spec.argv.clone()
		if kind == 'source' { args[args.len - 1] = root + '/unreviewed-source.v' }
		if kind == 'flag' { args[1] = '-unreviewed-flag' }
		if kind == 'output' { args[args.index('-o') + 1] = root + '/unreviewed-output' }
		if kind == 'extra' { args << '-unreviewed-extra' }
		if kind == 'different-role' {
			args = (command_spec2(engine.command_context(), 'cross-probe-generate.log') or { panic(err) }).argv
		}
		os.write_file(argv_path, json2.encode(args) + '\n') or { panic(err) }
		mut refused := false
		command_receipts2(prepared, engine) or { refused = true }
		assert refused
	}
	os.write_file(argv_path, json2.encode(spec.argv) + '\n') or { panic(err) }
	mut environment := spec.environment.clone()
	environment['CPPFLAGS'] = '-I/unreviewed-header'
	os.write_file(root + '/' + role + '.environment.json', json2.encode(environment) + '\n') or { panic(err) }
	mut refused := false
	command_receipts2(prepared, engine) or { refused = true }
	assert refused
}

fn test_frozen_command_wrapper_refuses_failed_missing_and_extra_cleanup_results() {
	root := boundary_root2() or { panic(err) }
	defer { boundary_cleanup2(root) }
	engine := boundary_command_engine2(root)
	prepared := boundary_command_receipts2(root, engine) or { panic(err) }
	path := root + '/cross-adapter-build.log.result.json'
	original := os.read_file(path) or { panic(err) }
	result := json2.decode[nativeguard.Result](original) or { panic(err) }
	for failed in [nativeguard.Result{...result, group_observed: false},
		nativeguard.Result{...result, held_pipe_after_leader_exit: true},
		nativeguard.Result{...result, cleanup: nativeguard.Cleanup{...result.cleanup, reaped: false}},
		nativeguard.Result{...result, cleanup: nativeguard.Cleanup{...result.cleanup, group_empty: false}},
		nativeguard.Result{...result, cleanup: nativeguard.Cleanup{...result.cleanup, exit_code: 7}}] {
		os.write_file(path, json2.encode(failed) + '\n') or { panic(err) }
		mut refused := false
		command_receipts2(prepared, engine) or { refused = true }
		assert refused
	}
	os.rm(path) or { panic(err) }
	mut refused := false
	command_receipts2(prepared, engine) or { refused = true }
	assert refused
	write_new2(path, original) or { panic(err) }
	write_new2(root + '/extra.result.json', original) or { panic(err) }
	extra := Preparation2{...prepared, tree: capture_owned2(root, [], Donor2{}) or { panic(err) }}
	refused = false
	command_receipts2(extra, engine) or { refused = true }
	assert refused
}

fn test_real_engine_deadline_gate_refuses_expired_preparation() {
	gate := EngineCompletion2{engine: Engine2{plan: Plan2{wall_ms: 1},
		started: time.sys_mono_now() - i64(2000000)}}
	mut refused := false
	gate.verify_deadline() or { refused = true }
	assert refused
}
