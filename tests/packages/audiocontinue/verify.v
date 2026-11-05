// SPDX-License-Identifier: GPL-2.0-or-later
// Read-only frozen preparation validation. This is never native acceptance.
module audiocontinue

import json2
import os
import tests.packages.audioinputs
import tests.packages.audiokernel
import tools.packages.pkgcore
import nativeguard

#include <errno.h>

struct AuditCheck2 {
	format int = 1
	result string = 'PASS'
	audit audiokernel.Audit
	log_sha256 string
}

fn expected_fresh2() map[string]Fresh2 {
	mut result := map[string]Fresh2{}
	for key, path in {
		'controller': 'inputs/controller'
		'adapter': 'cross-cc'
		'sandbox-generator': 'sandbox-build/security-compiler'
	} { result[key] = Fresh2{path: path, kind: 'host'} }
	for key, path in {
		'adapter-c': 'cross-cc.c'
		'sandbox-generator-c': 'sandbox-build/security-compiler.c'
	} { result[key] = Fresh2{path: path, kind: 'generated'} }
	for key, path in {
		'cross-probe': 'cross-probe'
		'sandbox': 'sandbox-build/vinix-sandbox'
		'tone': 'tone-build/tone'
		'guest': 'guest-build/init'
		'package-cli': 'tools/program-0/vinix-package'
		'account-cli': 'tools/program-1/vinix-account'
		'session-cli': 'tools/program-2/vinix-session'
		'authd': 'tools/program-3/vinix-authd'
	} { result[key] = Fresh2{path: path, kind: 'target'} }
	for path in ['cross-probe.c', 'sandbox-build/sandbox.c', 'tone-build/tone.c',
		'guest-build/init.c', 'tools/program-0/vinix-package.c',
		'tools/program-1/vinix-account.c', 'tools/program-2/vinix-session.c',
		'tools/program-3/vinix-authd.c'] {
		result['generated/' + path] = Fresh2{path: path, kind: 'generated'}
	}
	for key in ['source-before', 'source-after', 'donor-before', 'donor-after',
		'legacy-before', 'legacy-after', 'source-manifest',
		'external-source-before', 'external-source-after'] {
		result[key] = Fresh2{path: key + '.json', kind: 'metadata'}
	}
	for key, path in {
		'public-key': 'inputs/public-key'
		'config': 'inputs/config.json'
		'publisher': 'publisher-files.json'
		'extras': 'extras-files.json'
		'kernel-audit-before': 'audits/before.log.checked.json'
		'kernel-audit-after': 'audits/after.log.checked.json'
	} { result[key] = Fresh2{path: path, kind: 'metadata'} }
	for name in ['cp', 'tar', 'mformat', 'mmd', 'mcopy', 'limine'] {
		result['runtime/' + name] = Fresh2{path: 'runtime/' + name, kind: 'host'}
	}
	return result
}

fn preparation_bindings2(preparation Preparation2, plan Plan2, path string, candidate bool) ! {
	expected_leaf := if candidate { 'preparation2.pending.json' } else { 'preparation2.json' }
	other_leaf := if candidate { 'preparation2.json' } else { 'preparation2.pending.json' }
	if preparation.format != 2 || preparation.profile != format2_profile
		|| preparation.architecture != 'aarch64' || preparation.state_root != plan.state_root
		|| preparation.completed_at <= 0
		|| path != plan.state_root + '/' + expected_leaf
		|| preparation.donor_manifest_path != plan.donor_manifest_path
		|| preparation.donor_manifest_sha256 != plan.donor_manifest_sha256
		|| preparation.legacy_plan_path != plan.legacy_plan_path
		|| preparation.legacy_plan_sha256 != plan.legacy_plan_sha256
		|| preparation.source_manifest_path != plan.source_manifest_path
		|| preparation.source_manifest_sha256 != plan.source_manifest_sha256
		|| preparation.source_root != plan.source_root
		|| preparation.source_base_revision != plan.source_base_revision
		|| preparation.controller_sha256 != plan.controller_sha256
		|| preparation.scenarios != ['packages-audio-basic', 'packages-audio-lifecycle', 'packages-audio-seat']
		|| preparation.extras_path != 'tools/root' {
		return error('preparation is not the exact separate format-2 Plan and fixed scenario profile')
	}
	if os.exists(plan.state_root + '/' + other_leaf) || os.is_link(plan.state_root + '/' + other_leaf) {
		return error('preparation publication state differs from its exact candidate/final mode')
	}
	if os.exists(plan.state_root + '/refusal2.json') || os.is_link(plan.state_root + '/refusal2.json') {
		return error('refused attempt cannot become a completed preparation')
	}
}

fn fresh_file2(preparation Preparation2, key string) !string {
	value := preparation.fresh[key] or { return error('missing fresh artifact role: ' + key) }
	if !hex2(value.sha256, 64) { return error('fresh role has no exact file identity') }
	path := leaf2(preparation.state_root, value.path, 'file')!
	if os.lstat(path)!.nlink != 1 || digest2(path)! != value.sha256 {
		return error('fresh file differs or has a mutable alias: ' + key)
	}
	return path
}

fn target_elf2(path string) ! {
	ordinary2(path, 'file')!
	if os.lstat(path)!.mode & 0o111 == 0 { return error('target ELF lacks execute permission: ' + path) }
	mut file := os.open(path)!
	mut header := []u8{len: 64}
	n := file.read(mut header) or { file.close(); return err }
	file.close()
	if n != 64 || header[..7] != [u8(127), `E`, `L`, `F`, 2, 1, 1]
		|| header[16] != 2 || header[17] != 0 || header[18] != 183 || header[19] != 0 {
		return error('fresh target requires AArch64 little-endian ELF64 ET_EXEC: ' + path)
	}
}

fn targets2(preparation Preparation2) ! {
	for key in ['cross-probe', 'sandbox', 'tone', 'guest', 'package-cli', 'account-cli',
		'session-cli', 'authd'] {
		path := fresh_file2(preparation, key)!
		target_elf2(path)!
	}
}

fn equality_text2(preparation Preparation2, role string, expected string) ! {
	path := fresh_file2(preparation, role)!
	if os.lstat(path)!.size > 32 << 20 || os.read_file(path)! != expected {
		return error('complete retained inventory differs: ' + role)
	}
}

fn copied_source2(preparation Preparation2, source Source2, donor Donor2) ! {
	root := leaf2(preparation.state_root, 'inputs/source', 'directory')!
	actual := capture_owned2(root, [], donor)!
	for role in ['source-before', 'source-after'] {
		equality_text2(preparation, role, json2.encode(actual) + '\n')!
	}
	mut original := map[string]DonorEntry2{}
	for entry in source.entries {
		if entry.kind == 'file' && source_selected2(entry.path) { original[entry.path] = entry }
	}
	mut copied := map[string]bool{}
	for entry in actual {
		if entry.kind != 'file' { continue }
		before := original[entry.path] or { return error('unexpected fresh source leaf: ' + entry.path) }
		if entry.sha256 != before.sha256 || entry.mode != before.mode
			|| (entry.dev == before.dev && entry.inode == before.inode) {
			return error('new source copy differs or shares an immutable source inode')
		}
		copied[entry.path] = true
	}
	if copied.len != original.len { return error('new selected source closure is incomplete') }
	for path in engine2_files {
		if !copied[path] { return error('new copied source lacks fixed required file') }
	}
	for tree in engine2_trees {
		if !copied.keys().any(it.starts_with(tree + '/')) { return error('new copied source lacks fixed required tree') }
	}
}

fn full_audit_receipts2(preparation Preparation2, donor Donor2, legacy LegacyPlan2) ! {
	seal := audiokernel.validate(borrow_path2(donor, 'kernel-evidence')!, 'aarch64', legacy.kernel_sha256)!
	for label in ['before', 'after'] {
		base := preparation.state_root + '/audits/' + label + '.log'
		ordinary2(base, 'file')!
		ordinary2(base + '.argv.json', 'file')!
		if os.read_file(base)! != 'FRAME-PAGE COMPLETE STATE CHECK PASS\n'
			|| os.read_file(base + '.argv.json')! != json2.encode([seal.audit.checker_path,
				'check', seal.audit.root, seal.audit.manifest_path]) + '\n' {
			return error('preparation lacks unmodified complete original audit invocation/output')
		}
		path := fresh_file2(preparation, 'kernel-audit-' + label)!
		text := os.read_file(path)!
		checked := json2.decode[AuditCheck2](text)!
		if text != json2.encode(checked) + '\n' || checked.format != 1 || checked.result != 'PASS'
			|| checked.audit != seal.audit || checked.log_sha256 != digest2(base)! {
			return error('preparation complete original audit receipt differs')
		}
	}
}

fn fresh_semantics2(preparation Preparation2, legacy LegacyPlan2) ! {
	root := preparation.state_root
	for name in ['cp', 'tar', 'mformat', 'mmd', 'mcopy', 'limine'] {
		if preparation.fresh['runtime/' + name].sha256 != digest2(legacy.files[name])! {
			return error('fresh runtime copy differs from exact original identity: ' + name)
		}
	}
	for key, relative in {'package-cli': 'usr/bin/vinix-package',
		'account-cli': 'usr/sbin/vinix-account', 'session-cli': 'usr/sbin/vinix-session',
		'authd': 'usr/sbin/vinix-authd', 'sandbox': 'usr/bin/vinix-sandbox'} {
		path := leaf2(root, 'tools/root/' + relative, 'file')!
		if digest2(path)! != preparation.fresh[key].sha256 || os.lstat(path)!.mode & 0o7777 != 0o755 {
			return error('root extras executable differs from fresh target: ' + key)
		}
	}
	for relative, text in {'etc/passwd': 'root:x:0:0:root:/root:/bin/sh\n',
		'etc/group': 'root:x:0:\ntty:x:5:\n', 'etc/vinix/auth.conf': 'scrypt_ln = 10\n'} {
		if os.read_file(leaf2(root, 'tools/root/' + relative, 'file')!)! != text {
			return error('root extras account/auth fixture differs')
		}
	}
	if os.lstat(leaf2(root, 'tools/root/tmp', 'directory')!)!.mode & 0o7777 != 0o1777 {
		return error('root extras temporary directory mode differs')
	}
	key_text := os.read_file(fresh_file2(preparation, 'public-key')!)!
	if key_text.len != 65 || !key_text.ends_with('\n') || !hex2(key_text[..64], 64) {
		return error('fresh publisher public key encoding differs')
	}
	config_text := os.read_file(fresh_file2(preparation, 'config')!)!
	config := json2.decode[pkgcore.Config](config_text)!
	expected := pkgcore.Config{architecture: 'aarch64', launch_user: 'sam',
		repositories: [pkgcore.Repository{id: 'audio-fixture',
			url: 'file:///usr/share/audio-publisher', public_key: key_text[..64]}],
		policy: pkgcore.Policy{offline: true, reserve_bytes: 0}}
	if config_text != json2.encode(expected) || config != expected
		|| os.read_file(leaf2(root, 'tools/root/etc/vinix-packages/config.json', 'file')!)! != config_text {
		return error('fresh publisher enrollment, offline policy or launch account differs')
	}
	index_text := os.read_file(leaf2(root, 'inputs/publisher/index.json', 'file')!)!
	signature := os.read_file(leaf2(root, 'inputs/publisher/index.sig', 'file')!)!
	index := pkgcore.verify_index(config.repositories[0], index_text, signature, preparation.completed_at)!
	if index.repository != 'audio-fixture' || index.sequence != 1 || index.packages.len != 2 {
		return error('fresh signed publisher requires exactly two fixture packages')
	}
	mut ids := map[string]bool{}
	for package in index.packages {
		if package.id !in ['tone', 'noaudio'] || ids[package.id] || package.architecture != 'aarch64'
			|| package.version != '1.0.0' || package.kind != 'native' || package.entrypoint != 'bin/tone'
			|| package.permissions != if package.id == 'tone' { ['audio'] } else { []string{} }
			|| package.files.len != 1 || package.files[0].path != 'bin/tone'
			|| package.files[0].sha256 != preparation.fresh['tone'].sha256 || !package.files[0].executable {
			return error('fresh signed tone/noaudio payload or audio permission distinction differs')
		}
		ids[package.id] = true
	}
	// Every action and publisher payload installed into extras is an independent
	// exact copy. Unknown extras remain bound by the complete owned tree.
	for pair in [['inputs/publisher', 'usr/share/audio-publisher'],
		['inputs/source/tools/accounts/actions', 'usr/share/vinix/actions']] {
		for value in preparation.tree {
			if value.kind != 'file' || !value.path.starts_with(pair[0] + '/') { continue }
			relative := value.path[pair[0].len + 1..]
			copy := leaf2(root, 'tools/root/' + pair[1] + '/' + relative, 'file')!
			if digest2(copy)! != value.sha256 || os.lstat(copy)!.mode != value.mode {
				return error('root extras publisher/action copy differs')
			}
		}
	}
}

fn command_receipts2(preparation Preparation2, engine Engine2) ! {
	mut expected_results := map[string]bool{}
	for spec in command_specs2(engine.command_context())! {
		relative := spec.log_relative
		root := preparation.state_root
		leaf2(root, relative, 'file')!
		result_path := leaf2(root, relative + '.result.json', 'file')!
		expected_results[relative + '.result.json'] = true
		if os.lstat(result_path)!.size > 1 << 20 { return error('command receipt exceeds bound') }
		text := os.read_file(result_path)!
		result := json2.decode[nativeguard.Result](text)!
		if text != json2.encode(result) + '\n' || result.reason != '' || !result.group_observed
			|| result.held_pipe_after_leader_exit || !result.cleanup.reaped || !result.cleanup.group_empty
			|| result.cleanup.final_wait != -1 || result.cleanup.final_errno != C.ECHILD
			|| result.cleanup.exit_code != 0 {
			return error('required command ownership/cleanup did not complete: ' + relative)
		}
		if os.read_file(leaf2(root, relative + '.error.json', 'file')!)! != json2.encode({'error': ''}) + '\n' {
			return error('command retained a refusal')
		}
		// Full shared specifications bind every flag, input/output path, role and
		// environment. Observed text is compared and never executed.
		argv_path := leaf2(root, relative + '.argv.json', 'file')!
		env_path := leaf2(root, relative + '.environment.json', 'file')!
		if os.lstat(argv_path)!.size > 1 << 20 || os.lstat(env_path)!.size > 1 << 20 {
			return error('command observations exceed bound')
		}
		argv_text := os.read_file(argv_path)!
		validate_command_spec2(engine.command_context(), spec.role, argv_text, os.read_file(env_path)!)!
	}
	for entry in preparation.tree {
		if entry.kind == 'file' && entry.path.ends_with('.result.json') && !expected_results[entry.path] {
			return error('unexpected command result outside the fixed twenty-command phase')
		}
	}
}

fn validate_preparation_at2(path string, expected_sha string, candidate bool) !Preparation2 {
	text := pinned_text2(path, expected_sha, 32 << 20)!
	preparation := decode_preparation2(text)!
	plan := load_plan2(preparation.plan_path, preparation.plan_sha256)!
	preparation_bindings2(preparation, plan, path, candidate)!
	if os.lstat(path)!.nlink != 1 { return error('preparation receipt must have one independent name') }
	ignored := if candidate { ['preparation2.pending.json'] } else { ['preparation2.json'] }
	legacy := load_legacy2(plan)!
	donor := load_donor2(plan, legacy)!
	source := load_source2(plan)!
	if plan.receipt_reserve_bytes < proof_reserve2(legacy, donor, source)! {
		return error('preparation Plan lacks complete known after-proof reserve')
	}
	verify_legacy_inputs2(legacy)!
	if preparation.borrowed != donor.roles { return error('preparation immutable roles differ from complete donor') }
	mut expected := expected_fresh2()
	for name in audioinputs.trace_files() {
		expected['trace/' + name] = Fresh2{path: name, kind: 'trace'}
		object := trace_object2(plan.state_root, name)!
		expected['object/' + name] = Fresh2{path: object[plan.state_root.len + 1..], kind: 'object'}
	}
	if preparation.fresh.len != expected.len { return error('fresh artifact role coverage differs') }
	for key, shape in expected {
		actual := preparation.fresh[key] or { return error('missing fixed fresh artifact role') }
		if actual.path != shape.path || actual.kind != shape.kind { return error('fresh artifact role geometry differs: ' + key) }
		fresh_file2(preparation, key)!
	}
	if preparation.fresh['controller'].sha256 != plan.controller_sha256 { return error('fresh controller identity differs') }
	if capture_owned2(plan.state_root, ignored, donor)! != preparation.tree {
		return error('complete new state inventory differs')
	}
	for label in ['before', 'after'] {
		equality_text2(preparation, 'donor-' + label, json2.encode(donor) + '\n')!
		equality_text2(preparation, 'external-source-' + label, json2.encode(source) + '\n')!
		equality_text2(preparation, 'legacy-' + label, json2.encode(legacy.inputs) + '\n')!
	}
	equality_text2(preparation, 'source-manifest', json2.encode(source) + '\n')!
	copied_source2(preparation, source, donor)!
	equality_text2(preparation, 'publisher', json2.encode(capture_owned2(
		leaf2(plan.state_root, 'inputs/publisher', 'directory')!, [], donor)!) + '\n')!
	equality_text2(preparation, 'extras', json2.encode(capture_owned2(
		leaf2(plan.state_root, 'tools/root', 'directory')!, [], donor)!) + '\n')!
	targets2(preparation)!
	fresh_semantics2(preparation, legacy)!
	e := Engine2{plan: plan, legacy: legacy, donor: donor, source: source,
		plan_path: preparation.plan_path, plan_sha256: preparation.plan_sha256}
	command_receipts2(preparation, e)!
	allowed := e.headers()!
	for name in audioinputs.trace_files() {
		trace := fresh_file2(preparation, 'trace/' + name)!
		if os.lstat(trace)!.size > 16 << 20 { return error('target trace exceeds fixed text bound') }
		verify_trace2(os.read_file(trace)!, plan.state_root, borrow_path2(donor, 'sysroot')!,
			borrow_path2(donor, 'gcc')!, name, allowed)!
	}
	full_audit_receipts2(preparation, donor, legacy)!
	// Recheck every complete immutable input forest after all read-only checks.
	verify_donor2(donor)!
	verify_source2(source)!
	verify_legacy_inputs2(legacy)!
	if capture_owned2(plan.state_root, ignored, donor)! != preparation.tree
		|| digest2(path)! != expected_sha { return error('preparation changed during verification') }
	usage := usage2(legacy.charged_roots)!
	if usage.allocated > aggregate_cap2 || usage.apparent > aggregate_cap2 {
		return error('complete retained six-root namespace exceeds unchanged cap')
	}
	return preparation
}

fn decode_preparation2(text string) !Preparation2 {
	p := json2.decode[Preparation2](text, strict: true)!
	if text != json2.encode(p) + '\n' || p.format != 2 || p.profile != format2_profile
		|| p.architecture != 'aarch64' || p.completed_at <= 0 {
		return error('preparation requires exact format-2 typed encoding')
	}
	return p
}

pub fn validate_preparation2(path string, expected_sha string) !Preparation2 {
	return validate_preparation_at2(path, expected_sha, false)
}

fn validate_preparation_candidate2(path string, expected_sha string) !Preparation2 {
	return validate_preparation_at2(path, expected_sha, true)
}

// This command has no writer, claim, QEMU launch or qualification return type.
pub fn run_admission2(path string, expected_sha string) !u64 {
	preparation := validate_preparation2(path, expected_sha)!
	plan := load_plan2(preparation.plan_path, preparation.plan_sha256)!
	return check_budget2(plan, load_legacy2(plan)!, true)
}
