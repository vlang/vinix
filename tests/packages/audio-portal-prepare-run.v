// SPDX-License-Identifier: GPL-2.0-or-later
// Reviewed host preparation only. This program has no resume or QEMU command.
module main

import crypto.sha256
import json2
import nativeguard
import os
import recoveryguard
import time
import tests.packages.audioprepare

#include <errno.h>

const qualified_v = '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v'
const root_roles = ['source', 'compiler', 'sysroot', 'gcc', 'kernel-evidence', 'llvm-runtime', 'cross-runtime', 'sdk']
const file_roles = ['runner', 'controller', 'host-build-receipt', 'clang', 'backend', 'qemu',
	'firmware', 'firmware-vars', 'limine', 'git', 'cp', 'tar', 'mformat', 'mmd', 'mcopy',
	'sh', 'cc', 'arch', 'uname', 'file', 'mktemp', 'rm', 'df', 'cc1', 'collect2', 'as', 'ld',
	'lto-wrapper', 'lto-plugin', 'overlay-before', 'overlay-changes', 'overlay-bundle',
	'audit-checker', 'audit-checker-source', 'audit-manifest']

struct Plan {
	format int
	profile string
	source_revision string
	state_root string
	audit_root string
	kernel_seal_sha256 string
	kernel_sha256 string
	roots map[string]string
	files map[string]string
	inputs map[string]map[string]string
	charged_roots []string
	cap_bytes u64
	prepare_wall_ms int
}

struct Prepared {
	scenarios []string
}

struct CompilerPin {
	path string
	sha256 string
}

fn hex(value string, size int) bool {
	return value.len == size && value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn exact_keys(actual []string, expected []string) ! {
	mut a := actual.clone()
	mut b := expected.clone()
	a.sort()
	b.sort()
	if a != b { return error('unknown or missing fields/roles: ' + a.str()) }
}

fn canonical(path string) ! {
	if !os.is_abs_path(path) || os.real_path(path) != path || path.contains('\n') || path.contains('|') {
		return error('requires canonical absolute path: ' + path)
	}
}

fn covers(roots []string, path string) bool {
	return roots.any(path == it || path.starts_with(it + '/'))
}

fn digest(path string) !string {
	audioprepare.regular(path)!
	return audioprepare.digest(path)
}

fn inventory(path string, independent bool, depth int, started i64, mut result map[string]string) ! {
	if depth > 64 || result.len > 250000 || recoveryguard.deadline_expired(started, 120000) {
		return error('input inventory exceeds bounded scope')
	}
	if path in result { return }
	if path.contains('|') || path.bytes().any(it < 32 || it == 127) { return error('invalid input path') }
	stat := os.lstat(path)!
	kind := stat.mode & 0o170000
	if kind == 0o040000 {
		result[path] = 'directory|' + (stat.mode & 0o7777).str()
		mut names := os.ls(path)!
		names.sort()
		for name in names {
			if independent && depth == 0 && name == '.git' { continue }
			inventory(path + '/' + name, independent, depth + 1, started, mut result)!
		}
	} else if kind == 0o100000 {
		if independent && stat.nlink != 1 { return error('source must be an independent ordinary copy: ' + path) }
		result[path] = 'file|' + (stat.mode & 0o7777).str() + '|' + digest(path)!
	} else if kind == 0o120000 && independent {
		// Unselected Git compatibility/fixture links are identities, not inputs to
		// traverse. The producer admits only ordinary files in its source closure.
		result[path] = 'link|' + os.readlink(path)!
	} else if kind == 0o120000 {
		real := os.real_path(path)
		result[path] = 'link|' + os.readlink(path)! + '|' + real
		inventory(real, false, depth + 1, started, mut result)!
	} else { return error('nonordinary selected input: ' + path) }
}

fn inputs(p Plan) !map[string]map[string]string {
	mut result := map[string]map[string]string{}
	for role, root in p.roots {
		mut entries := map[string]string{}
		inventory(root, role == 'source', 0, time.sys_mono_now(), mut entries)!
		result['tree:' + role] = entries
	}
	for role, path in p.files {
		mut entries := map[string]string{}
		inventory(path, false, 0, time.sys_mono_now(), mut entries)!
		if os.lstat(path)!.mode & 0o170000 != 0o100000 { return error('named tool must be an ordinary canonical file: ' + role) }
		result['file:' + role] = entries
	}
	return result
}

fn store_inventory(store string) !map[string]string {
	mut result := map[string]string{}
	started := time.sys_mono_now()
	for name in os.ls(store)! {
		if result.len > 250000 || recoveryguard.deadline_expired(started, 120000) { return error('content store exceeds bounded scope') }
		if !hex(name, 64) || digest(store + '/' + name)! != name { return error('content store is not digest-addressed: ' + name) }
		result[name] = name
	}
	return result
}

fn command(p Plan, output string, label string, argv []string, wall_ms int) ! {
	os.write_file(output + '/' + label + '.argv.json', json2.encode(argv))!
	mut failure := ''
	result := nativeguard.supervise(argv, p.roots['source'], output, p.charged_roots,
		output + '/' + label + '.log', output + '/' + label + '-df', nativeguard.Limits{
			start_bytes: u64(2) << 30, floor_bytes: u64(1) << 30,
			cap_bytes: p.cap_bytes - (u64(2) << 20), wall_ms: wall_ms, sample_ms: 1000
		}) or { failure = recoveryguard.bounded_message(err.msg()); nativeguard.Result{} }
	os.write_file(output + '/' + label + '.result.json', json2.encode(result))!
	os.write_file(output + '/' + label + '.error.json', json2.encode({'error': failure}))!
	if failure != '' || result.reason != '' || !result.group_observed || !result.cleanup.reaped
		|| !result.cleanup.group_empty || result.cleanup.final_wait != -1
		|| result.cleanup.final_errno != C.ECHILD || result.cleanup.exit_code != 0 {
		return error('command or inherited-group cleanup refused: ' + label)
	}
}

fn environment(p Plan, output string) map[string]string {
	return {'HOME': '/Users/alex', 'USER': 'alex', 'LOGNAME': 'alex', 'LANG': 'en_US.UTF-8',
		'PATH': '/opt/homebrew/opt/llvm/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin',
		'V': qualified_v, 'VEXE': qualified_v, 'VINIX_V_COMPILER': qualified_v,
		'V_MACOS_V3_CALLER_VEXE': qualified_v, 'V_MACOS_V3_CALLER_VEXE_PRESENT': '1',
		'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0', 'V_MACOS_V3_NO_FALLBACK': '1',
		'V_MACOS_V3_CALLER_NO_FALLBACK': '1', 'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1',
		'VFLAGS': '-nocache', 'VTMP': output + '/tmp', 'TMPDIR': output + '/tmp',
		'VMODULES': output + '/modules', 'VINIX_ROOT': p.roots['source'],
		'VINIX_AUDIO_KERNEL_EVIDENCE': p.roots['kernel-evidence'],
		'VINIX_AUDIO_CC_SOURCE': p.roots['source'] + '/tests/packages/audio-cross-cc.v',
		'VINIX_AUDIO_BACKEND_CC': p.files['backend'], 'CC_AARCH64': p.files['clang'],
		'VINIX_QEMU_AARCH64': p.files['qemu'], 'VINIX_OVMF_CODE_AARCH64': p.files['firmware'],
		'VINIX_OVMF_VARS_AARCH64': p.files['firmware-vars'], 'VINIX_LIMINE_BOOTAA64': p.files['limine']}
}

fn check() ! {
	$if prod {} $else { return error('compile this runner with -prod') }
	if digest(@FILE)! != sha256.hexhash($embed_file('audio-portal-prepare-run.v').to_string()) {
		return error('runner source differs from compiled source')
	}
	if os.args.len != 5 || os.args[1] !in ['--inspect', '--prepare'] {
		return error('use audio-portal-prepare-run --inspect|--prepare PLAN PLAN_SHA256 NEW_COMMAND_DIRECTORY')
	}
	plan_path := os.args[2]
	canonical(plan_path)!
	if !hex(os.args[3], 64) || digest(plan_path)! != os.args[3] { return error('reviewed plan digest differs') }
	text := os.read_file(plan_path)!
	exact_keys(json2.decode[json2.Any](text)!.as_map().keys(), ['format', 'profile', 'source_revision',
		'state_root', 'audit_root', 'kernel_seal_sha256', 'kernel_sha256', 'roots', 'files', 'inputs',
		'charged_roots', 'cap_bytes', 'prepare_wall_ms'])!
	p := json2.decode[Plan](text)!
	// Round-tripping also rejects duplicate fields/map keys and ignored fields.
	if text != json2.encode(p) + '\n' { return error('requires canonical typed plan JSON followed by one newline') }
	if p.format != 1 || p.profile != 'matched-peer-frame-atomic-fresh-20261026' || !hex(p.source_revision, 40)
		|| !hex(p.kernel_seal_sha256, 64) || !hex(p.kernel_sha256, 64)
		|| p.prepare_wall_ms <= 0 || p.prepare_wall_ms > 3000000 || p.cap_bytes < u64(16) << 20 {
		return error('invalid fixed preparation profile or limits')
	}
	exact_keys(p.roots.keys(), root_roles)!
	exact_keys(p.files.keys(), file_roles)!
	for _, path in p.roots {
		canonical(path)!
		if os.lstat(path)!.mode & 0o170000 != 0o040000 { return error('named input root must be an ordinary directory') }
	}
	for _, path in p.files { canonical(path)! }
	for path in [p.state_root, p.audit_root, os.args[4]] { canonical(path)! }
	output := os.args[4]
	if os.exists(output) || os.is_link(output) || os.exists(p.state_root) || os.is_link(p.state_root)
		|| os.lstat(os.dir(output))!.mode & 0o170000 != 0o040000 {
		return error('requires fresh preparation and command state below existing ordinary parents')
	}
	if p.roots['compiler'] != os.dir(qualified_v) || p.files['runner'] != os.executable()
		|| digest(qualified_v)! != 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
		|| digest(p.files['overlay-before'])! != '65b8b8322a34407c4b16762803c618e2fe8f414cc0bc5ccb10144bf20292786f'
		|| digest(p.files['overlay-changes'])! != '4941c055c018c321d7a4cc94c054b26ba6494bc6be7fa508d99a1bb10b7b2b21'
		|| digest(p.files['overlay-bundle'])! != '32d8bc5f46c953aeb5e9ad1ad63e182f10752fe270983943a22c040016617976'
		|| digest(p.roots['kernel-evidence'] + '/kernel-seal.json')! != p.kernel_seal_sha256
		|| digest(p.roots['kernel-evidence'] + '/kernel-aarch64/bin/vinix')! != p.kernel_sha256 {
		return error('qualified compiler, runner or matched kernel binding differs')
	}
	for root in p.charged_roots {
		canonical(root)!
		if p.charged_roots.filter(it == root).len != 1
			|| p.charged_roots.any(it != root && root.starts_with(it + '/')) { return error('duplicate or overlapping charged roots') }
	}
	store := os.dir(p.state_root) + '/audio-input-store'
	for path in [p.roots['source'], p.roots['kernel-evidence'], p.audit_root, p.state_root,
		store, output, os.executable(), plan_path, p.files['audit-manifest']] {
		if !covers(p.charged_roots, path) { return error('phase input/output is not charged: ' + path) }
	}
	os.mkdir(output, mode: 0o700)!
	nativeguard.watch_interrupts()!
	for name, _ in os.environ() { os.unsetenv(name) }
	for name in ['tmp', 'modules'] { os.mkdir(output + '/' + name, mode: 0o700)! }
	env := environment(p, output)
	for name, value in env { os.setenv(name, value, true) }
	os.write_file(output + '/environment.json', json2.encode(env))!
	os.cp(plan_path, output + '/plan.json')!
	for name in ['git', 'cp', 'tar', 'mformat', 'mmd', 'mcopy', 'sh', 'cc', 'arch', 'uname', 'file', 'mktemp', 'rm', 'df'] {
		if os.real_path(os.find_abs_path_of_executable(name)!) != p.files[name] { return error('fixed PATH resolves another tool: ' + name) }
	}
	before := inputs(p)!
	mut compiler_expected := map[string]string{}
	for pin in json2.decode[[]CompilerPin](os.read_file(p.files['overlay-before'])!)! {
		if pin.path in compiler_expected { return error('duplicate compiler overlay path') }
		compiler_expected[pin.path] = pin.sha256
	}
	mut compiler_actual := map[string]string{}
	for path, entry in before['tree:compiler'] {
		if path == p.roots['compiler'] { continue }
		name := path.all_after(p.roots['compiler'] + '/')
		if entry.starts_with('directory|') { compiler_actual[name] = 'directory' }
		else if entry.starts_with('file|') { compiler_actual[name] = entry.all_after_last('|') }
		else { return error('qualified compiler root contains an unqualified link') }
	}
	if compiler_expected != compiler_actual { return error('complete qualified compiler root differs from retained overlay map') }
	os.write_file(output + '/inputs-before.json', json2.encode(before))!
	store_before := store_inventory(store)!
	os.write_file(output + '/store-before.json', json2.encode(store_before))!
	admission := nativeguard.actual_df(output, output + '/admission-df.log')!
	allocation := nativeguard.allocated(p.charged_roots, os.lstat(output)!.dev)!
	os.write_file(output + '/admission.json', json2.encode({'available_bytes': admission.available.str(),
		'pathname_allocated_bytes': allocation.str(), 'cap_bytes': p.cap_bytes.str(),
		'metric': 'Inclusive nonfollowing pathname allocation; repeated hardlinks count repeatedly. This is not exclusive physical growth.'}))!
	if admission.available < u64(2) << 30 || allocation > p.cap_bytes - (u64(16) << 20) { return error('actual df or namespace admission refused') }
	if os.args[1] == '--inspect' {
		println('INSPECTED selected inputs and inclusive namespace; no target or guest executed')
		return
	}
	if before != p.inputs { return error('complete reviewed selected input map differs') }
	command(p, output, 'revision', [p.files['git'], '-C', p.roots['source'], 'rev-parse', 'HEAD'], 30000)!
	command(p, output, 'status', [p.files['git'], '-C', p.roots['source'], 'status', '--porcelain'], 30000)!
	if os.read_file(output + '/revision.log')!.trim_space() != p.source_revision || os.read_file(output + '/status.log')! != '' {
		return error('requires selected clean committed independent source worktree')
	}
	command(p, output, 'audit', [p.files['audit-checker'], 'check', p.audit_root, p.files['audit-manifest']], 300000)!
	for role, option in {'sysroot': '-print-sysroot', 'gcc': '-print-libgcc-file-name',
		'cc1': '-print-prog-name=cc1', 'collect2': '-print-prog-name=collect2', 'as': '-print-prog-name=as',
		'ld': '-print-prog-name=ld', 'lto-wrapper': '-print-prog-name=lto-wrapper', 'lto-plugin': '-print-prog-name=liblto_plugin.so'} {
		command(p, output, 'backend-' + role, [p.files['backend'], option], 30000)!
		reported := os.read_file(output + '/backend-' + role + '.log')!.trim_space()
		resolved := if reported.contains('/') { os.real_path(reported) } else { os.real_path(os.find_abs_path_of_executable(reported)!) }
		expected := if role in ['sysroot', 'gcc'] { p.roots[role] } else { p.files[role] }
		actual := if role == 'gcc' { os.dir(resolved) } else { resolved }
		if actual != expected { return error('cross backend resolved another input: ' + role) }
	}
	argv := [p.files['controller'], '--prepare-only', '--arch', 'aarch64', '--kernel',
		p.roots['kernel-evidence'] + '/kernel-aarch64/bin/vinix', '--state-dir', p.state_root]
	mut failure := ''
	command(p, output, 'prepare', argv, p.prepare_wall_ms) or { failure = err.msg() }
	after := inputs(p)!
	os.write_file(output + '/inputs-after.json', json2.encode(after))!
	store_after := store_inventory(store)!
	os.write_file(output + '/store-after.json', json2.encode(store_after))!
	if before != after { return error('selected original input changed') }
	for name, value in store_before { if store_after[name] != value { return error('preexisting store entry changed or disappeared') } }
	if failure != '' { return error(failure) }
	prepared_sha := digest(p.state_root + '/preparation.json')!
	if json2.decode[Prepared](os.read_file(p.state_root + '/preparation.json')!)!.scenarios
		!= ['packages-audio-basic', 'packages-audio-lifecycle', 'packages-audio-seat'] { return error('preparation must retain all three fixed scenarios') }
	prepared_tree := audioprepare.capture(p.state_root, [])!
	command(p, output, 'verify', [p.files['controller'], '--verify-prepared', p.state_root, '--prepared-sha256', prepared_sha], 300000)!
	if audioprepare.capture(p.state_root, [])! != prepared_tree || inputs(p)! != before
		|| store_inventory(store)! != store_after || os.ls(output + '/modules')!.len != 0 {
		return error('read-only verification, originals, store or private modules changed')
	}
	os.write_file(output + '/receipt.pending.json', json2.encode({'result': 'PASS',
		'plan_sha256': os.args[3], 'preparation_sha256': prepared_sha,
		'runner_source_sha256': digest(@FILE)!, 'scope': 'Eight-program AArch64 preparation plus read-only verification; no guest executed'}))!
	final_df := nativeguard.actual_df(output, output + '/final-df.log')!
	if final_df.available < u64(1) << 30 || nativeguard.allocated(p.charged_roots, os.lstat(output)!.dev)! > p.cap_bytes {
		return error('final namespace cap or actual df floor refused')
	}
	os.mv(output + '/receipt.pending.json', output + '/receipt.json')!
	println('PREPARED AND VERIFIED ' + prepared_sha + ' (no guest executed)')
}

fn main() { check() or { eprintln('audio-portal-prepare-run: ' + recoveryguard.bounded_message(err.msg())); exit(1) } }
