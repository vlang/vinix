// SPDX-License-Identifier: GPL-2.0-or-later
// Bounded host qualification for matched-kernel audio preparation; no guest.
module main

import crypto.sha256
import json2
import nativeguard
import os
import recoveryguard
import time
import tests.packages.audioprepare

#include <errno.h>

const compiler = '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v'
const clang = '/opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23'
const original_audit = '/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-fresh-20261026'
const original_manifest = '/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-fresh-20261026-seal-01/complete/inventory.json'
const audit_checker = '/Users/alex/Library/Caches/vinix-codex/section14/alloc-track-frame-kernel-20261026-seal-02/frame-page-seal'
const legacy_kernel = '/Users/alex/Library/Caches/vinix-codex/section14/audio-peer-login-20261026/kernel-evidence'
const cap = u64(2048) << 20

struct Pin {
	path string
	sha256 string
}

fn digest(path string) !string { return audioprepare.digest(path) }

fn canonical(path string) ! {
	if !os.is_abs_path(path) || os.real_path(path) != path || path.bytes().any(it < 32 || it == 127) {
		return error('requires canonical absolute host path: ' + path)
	}
}

fn tree(path string, depth int, started i64, mut result map[string]string) ! {
	if depth > 64 || result.len > 250000 || recoveryguard.deadline_expired(started, 120000) {
		return error('host input inventory exceeds bounded scope')
	}
	stat := os.lstat(path)!
	kind := stat.mode & 0o170000
	if kind == 0o040000 {
		result[path] = 'directory|' + (stat.mode & 0o7777).str()
		mut names := os.ls(path)!
		names.sort()
		for name in names {
			if depth == 0 && name == '.git' { continue }
			tree(path + '/' + name, depth + 1, started, mut result)!
		}
	} else if kind == 0o100000 {
		result[path] = 'file|' + (stat.mode & 0o7777).str() + '|' + digest(path)!
	} else if kind == 0o120000 { result[path] = 'link|' + os.readlink(path)! }
	else { return error('nonordinary selected host input: ' + path) }
}

fn inputs(root string, evidence string) !map[string]string {
	mut result := map[string]string{}
	for path in [root, os.dir(compiler), evidence, legacy_kernel] { tree(path, 0, time.sys_mono_now(), mut result)! }
	for path in [os.executable(), clang, original_manifest, audit_checker,
		os.real_path(os.find_abs_path_of_executable('git')!),
		'/Users/alex/code/vinix/tests/kernel-allocs/frame-page-seal.v',
		os.dir(os.dir(compiler)) + '/overlay-before.json', os.dir(os.dir(compiler)) + '/changes.json',
		os.dir(os.dir(compiler)) + '/bundle.json', '/usr/bin/cc', '/usr/bin/arch', '/bin/sh',
		'/bin/df', '/usr/bin/uname', '/usr/bin/file', '/usr/bin/mktemp', '/bin/rm'] {
		result[path] = 'file|' + (os.lstat(path)!.mode & 0o7777).str() + '|' + digest(path)!
	}
	if digest(compiler)! != 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
		|| digest(clang)! != '4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8'
		|| digest(os.dir(os.dir(compiler)) + '/overlay-before.json')! != '65b8b8322a34407c4b16762803c618e2fe8f414cc0bc5ccb10144bf20292786f'
		|| digest(os.dir(os.dir(compiler)) + '/changes.json')! != '4941c055c018c321d7a4cc94c054b26ba6494bc6be7fa508d99a1bb10b7b2b21'
		|| digest(os.dir(os.dir(compiler)) + '/bundle.json')! != '32d8bc5f46c953aeb5e9ad1ad63e182f10752fe270983943a22c040016617976'
		|| digest(evidence + '/kernel-seal.json')! != '7634b22ea52902e1d923f91543703398e46d3e679694f52c880fef7e25e44ddf'
		|| digest(evidence + '/kernel-aarch64/bin/vinix')! != 'a9d79c09a0d575facafc23b2f65be8e94ffa423cb92e183b5d4c73719f13a469'
		|| digest(original_manifest)! != 'e82671ca13c4d46b18d1d9762d661f4f392be0ee888d0fb20d1de21f540c54f0'
		|| digest(audit_checker)! != 'fcc0e1f0d557e980a99dbcaf68d45ed8da851b07bf0810e8c99c931c865001b6'
		|| digest('/Users/alex/code/vinix/tests/kernel-allocs/frame-page-seal.v')! != '8cd5e58df42e07760d0e1b73c49807b0ee2c7e353412e7d54aca34a7597577d4' {
		return error('qualified host compiler differs')
	}
	mut expected := map[string]string{}
	for pin in json2.decode[[]Pin](os.read_file(os.dir(os.dir(compiler)) + '/overlay-before.json')!)! {
		if pin.path in expected { return error('duplicate compiler input path') }
		expected[pin.path] = pin.sha256
	}
	mut actual := map[string]string{}
	for path, value in result {
		if !path.starts_with(os.dir(compiler) + '/') { continue }
		if value.starts_with('directory|') { actual[path.all_after(os.dir(compiler) + '/')] = 'directory' }
		else if value.starts_with('file|') { actual[path.all_after(os.dir(compiler) + '/')] = value.all_after_last('|') }
		else { return error('compiler root contains unqualified link') }
	}
	if expected != actual { return error('complete compiler root differs from overlay map') }
	return result
}

fn snapshot(root string, out string, entries map[string]string) ! {
	started := time.sys_mono_now()
	mut names := entries.keys().filter(it == root || it.starts_with(root + '/'))
	if names.len > 250000 { return error('source capture exceeds bounded entry scope') }
	names.sort()
	mut copied := u64(0)
	for path in names {
		if recoveryguard.deadline_expired(started, 120000) { return error('source capture exceeds time bound') }
		target := out + path[root.len..]
		stat := os.lstat(path)!
		kind := stat.mode & 0o170000
		if kind == 0o040000 { os.mkdir(target)! }
		else if kind == 0o100000 {
			if stat.size > (u64(128) << 20) - copied { return error('source capture exceeds independent copy bound') }
			copied += stat.size
			os.cp(path, target)!
			if os.lstat(target)!.nlink != 1 || digest(target)! != digest(path)! { return error('source capture is not independent and identical') }
		} else if kind == 0o120000 { os.symlink(os.readlink(path)!, target)! }
		else { return error('unexpected source capture entry') }
		if kind != 0o120000 { os.chmod(target, int(stat.mode & 0o7777))! }
	}
}

fn run(root string, out string, charged []string, name string, argv []string) ! {
	os.write_file(out + '/' + name + '.argv.json', json2.encode(argv) + '\n')!
	mut failure := ''
	result := nativeguard.supervise(argv, root, out, charged, out + '/' + name + '.log',
		out + '/' + name + '-df', nativeguard.Limits{
			start_bytes: u64(2) << 30, floor_bytes: u64(1) << 30,
			cap_bytes: cap - (u64(4) << 20), wall_ms: 300000, sample_ms: 1000
		}) or { failure = recoveryguard.bounded_message(err.msg()); nativeguard.Result{} }
	os.write_file(out + '/' + name + '.result.json', json2.encode(result) + '\n')!
	os.write_file(out + '/' + name + '.error.json', json2.encode({'error': failure}) + '\n')!
	if failure != '' || result.reason != '' || !result.group_observed || !result.cleanup.reaped
		|| !result.cleanup.group_empty || result.cleanup.final_wait != -1
		|| result.cleanup.final_errno != C.ECHILD || result.cleanup.exit_code != 0 {
		return error('host command or owned-group cleanup failed: ' + name)
	}
}

fn check() ! {
	$if prod {} $else { return error('compile audio-portal-prepare-host with -prod') }
	if digest(@FILE)! != sha256.hexhash($embed_file('audio-portal-prepare-host.v').to_string()) { return error('host qualifier source changed') }
	if os.args.len != 4 { return error('use audio-portal-prepare-host MATCHED_KERNEL_EVIDENCE ARM_KERNEL_SHA256 NEW_OUTPUT') }
	root := os.dir(os.dir(os.dir(@FILE)))
	evidence := os.args[1]
	selected := os.args[2]
	out := os.args[3]
	for path in [root, evidence, out, os.dir(out), os.executable()] { canonical(path)! }
	if os.exists(out) || os.is_link(out) || selected.len != 64
		|| selected != 'a9d79c09a0d575facafc23b2f65be8e94ffa423cb92e183b5d4c73719f13a469'
		|| !os.executable().starts_with(os.dir(out) + '/') || out.starts_with(root + '/') {
		return error('requires fresh external host output and charged bootstrap executable')
	}
	charged := [root, evidence, original_audit, os.dir(original_manifest), legacy_kernel, os.dir(out)]
	for path in charged {
		if charged.filter(it == path).len != 1 || charged.any(it != path && path.starts_with(it + '/')) { return error('charged host roots overlap') }
	}
	os.mkdir(out, mode: 0o700)!
	nativeguard.watch_interrupts()!
	for name, _ in os.environ() { os.unsetenv(name) }
	for name in ['tmp', 'modules'] { os.mkdir(out + '/' + name, mode: 0o700)! }
	env := {'HOME': '/Users/alex', 'USER': 'alex', 'LOGNAME': 'alex', 'LANG': 'en_US.UTF-8',
		'PATH': '/opt/homebrew/opt/llvm/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin',
		'V': compiler, 'VEXE': compiler, 'VINIX_V_COMPILER': compiler,
		'V_MACOS_V3_CALLER_VEXE': compiler, 'V_MACOS_V3_CALLER_VEXE_PRESENT': '1',
		'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0', 'V_MACOS_V3_NO_FALLBACK': '1',
		'V_MACOS_V3_CALLER_NO_FALLBACK': '1', 'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1',
		'VTMP': out + '/tmp', 'TMPDIR': out + '/tmp', 'VMODULES': out + '/modules',
		'VFLAGS': '-nocache', 'VINIX_ROOT': root, 'VINIX_AUDIO_KERNEL_EVIDENCE': evidence}
	for name, value in env { os.setenv(name, value, true) }
	os.write_file(out + '/environment.json', json2.encode(env) + '\n')!
	os.write_file(out + '/charged-roots.json', json2.encode(charged) + '\n')!
	before := inputs(root, evidence)!
	os.write_file(out + '/inputs-before.json', json2.encode(before) + '\n')!
	if nativeguard.allocated(charged, os.lstat(out)!.dev)! > cap - (u64(144) << 20) { return error('host namespace lacks bounded source capture reserve') }
	snapshot(root, out + '/source', before)!
	if nativeguard.allocated(charged, os.lstat(out)!.dev)! > cap - (u64(16) << 20) { return error('host namespace admission exceeds projected cap') }
	git := os.real_path(os.find_abs_path_of_executable('git')!)
	run(root, out, charged, 'repository-revision', [git, '-C', root, 'rev-parse', 'HEAD'])!
	run(root, out, charged, 'repository-status', [git, '-C', root, 'status', '--porcelain'])!
	run(root, out, charged, 'repository-diff', [git, '-C', root, 'diff', '--binary'])!
	run(root, out, charged, 'original-audit-before', [audit_checker, 'check', original_audit, original_manifest])!
	mut builds := map[string]string{}
	for name, source in {'runner': 'audio-portal-prepare-run.v', 'controller': 'audio-portal-runtime-check.v',
		'retainer': 'audio-portal-retain.v', 'prepare-check': 'audio-portal-prepare-check.v',
		'evidence-check': 'audio-portal-evidence-check.v', 'kernel-check': 'audio-kernel-check.v'} {
		if os.ls(out + '/modules')!.len != 0 { return error('private module directory changed') }
		argv := [compiler, '-prod', '-nocache', '-keepc', '-backend', 'c', '-cc', clang,
			'-path', '@vlib|@vmodules|.|tests/hardware-platform|tests/software-hosted-x11|tests/software-hosted-x11/diagnostics',
			'-o', out + '/' + name, root + '/tests/packages/' + source]
		run(root, out, charged, 'build-' + name, argv)!
		builds[name] = digest(out + '/' + name)!
		if inputs(root, evidence)! != before { return error('selected host inputs changed during compilation') }
	}
	run(root, out, charged, 'prepare-controls', [out + '/prepare-check', '--out=' + out + '/prepare-controls',
		'--controller=' + out + '/controller', '--kernel-evidence=' + legacy_kernel])!
	run(root, out, charged, 'strict-controls', [out + '/evidence-check', '--self-test', out + '/retainer', out + '/strict-controls', 'aarch64'])!
	run(root, out, charged, 'kernel-controls', [out + '/kernel-check', evidence, selected, out + '/kernel-controls'])!
	run(root, out, charged, 'original-audit-after', [audit_checker, 'check', original_audit, original_manifest])!
	after := inputs(root, evidence)!
	os.write_file(out + '/inputs-after.json', json2.encode(after) + '\n')!
	if before != after || os.ls(out + '/modules')!.len != 0 { return error('selected host inputs or private modules changed') }
	os.write_file(out + '/host-build.json', json2.encode({'result': 'PASS', 'builds': json2.encode(builds),
		'source_revision': os.read_file(out + '/repository-revision.log')!.trim_space(),
		'source_root': root, 'source_status_sha256': digest(out + '/repository-status.log')!,
		'source_diff_sha256': digest(out + '/repository-diff.log')!,
		'inputs_before_sha256': digest(out + '/inputs-before.json')!, 'inputs_after_sha256': digest(out + '/inputs-after.json')!,
		'selected_kernel_sha256': selected, 'charged_limit_bytes': cap.str(),
		'scope': 'Six production host tools and existing preparation/evidence plus matched-kernel controls. No target compilation or guest execution; host loader/SDK dependencies are outside the selected frozen closure.'}) + '\n')!
	final_df := nativeguard.actual_df(out, out + '/final-df.log')!
	allocation := nativeguard.allocated(charged, os.lstat(out)!.dev)!
	if final_df.available < u64(1) << 30 || allocation > cap { return error('final host namespace or actual df refused') }
	os.write_file(out + '/qualification.json', json2.encode({'result': 'PASS', 'pathname_allocated_bytes': allocation.str(),
		'cap_bytes': cap.str(), 'host_build_sha256': digest(out + '/host-build.json')!,
		'scope': 'Host qualification only; no target or guest executed'}) + '\n')!
	println('AUDIO PREPARATION HOST PASS (no target or guest executed)')
}

fn main() { check() or { eprintln('audio-portal-prepare-host: ' + recoveryguard.bounded_message(err.msg())); exit(1) } }
