// SPDX-License-Identifier: GPL-2.0-or-later
// Resume only host controls from the interrupted, reviewed six-build attempt.
module main

import crypto.sha256
import json2
import nativeguard
import os
import recoveryguard
import time
import tests.packages.audioprepare

#include <errno.h>

const state = '/Users/alex/Library/Caches/vinix-codex/section14/package-audio-portal/a4-matched-host-01'
const prior = state + '/qualification-04'
const compiler = '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v'
const clang = '/opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23'
const evidence = '/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-kernel-20261026'
const original = '/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-20261026'
const manifest = '/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-20261026-seal-01/complete/inventory.json'
const checker = '/Users/alex/Library/Caches/vinix-codex/section14/alloc-track-frame-kernel-20261026-seal-02/frame-page-seal'
const legacy = '/Users/alex/Library/Caches/vinix-codex/section14/audio-peer-login-20261026/kernel-evidence'
const selected = 'e805a73154d61503d6427f1ccc4d19b1eb9ec802ed38255e059e0b2bd1e83174'
const cap = u64(1280) << 20
const sources = {'runner': 'audio-portal-prepare-run.v', 'controller': 'audio-portal-runtime-check.v',
	'retainer': 'audio-portal-retain.v', 'prepare-check': 'audio-portal-prepare-check.v',
	'evidence-check': 'audio-portal-evidence-check.v', 'kernel-check': 'audio-kernel-check.v'}
// In order: executable, generated C, exact build argv, successful build result.
const pins = {
	'runner': ['83c623d90ab667886123bc25bac907b7ac5f8a854ab3317631d8da3dad99d05f', '7589ddeb1cec3c36af94f967382a0a1366c2cf7de7e0ceca9390134ef8bc0d6b', 'eca8f60e82badd7cc86771d31024fe83a7b893bb2f818d5197fa6e28559b43aa', 'cd31ffd576153f94b2b192a669e8558dfb3b7df4ca0ff0b7ecb416855652d2d2']
	'controller': ['4bd12d84f6f633d3bff58485ded313d804f38d1a920072083cafe634b8d77c1b', '0d9b88b88f253c65a93fde37193299ae80a59bb7eadac40db1996b7ee5279f2b', '4cef14730720f20b5b9f4d94072067c25ed78f74db70ab1260e151be4ebe7095', '8f689c3f902748c27e9f964c6770e9039c94b11adf430f3a6da05587b4addaba']
	'retainer': ['4502c140bc0410c53e0bc13318cbb3997ca875c2f9b961a04d41f293bd8ffff3', 'bdb548cbfba44cc6660a826dd466f43339839d2492527c9bc9de1a217c4fe379', '0b21333ca61dd6f5e5e785ac8b3276f55a8557cf3335fd8eedb442404b1f3efc', '59b99cc47d603eb932acfc1a0791d1771ee5c9cddda8e21ad898911dbefbc1bd']
	'prepare-check': ['c957c73dc0aaf1da4ab63061b2534110de0ccb61d2f443707cea1adc8997509e', 'e1bcd27c98de0d71054d9bec9e6c0a70d04a20a2ee872a0d15908e0f11888033', '802c8c398e7c15f4ebae7ba1061d7936bdcc8185212cbc96cf8bf442b26ff20b', '3974d520a8dda78318a40c912693a6706640ddc2061365d7b107ce2cb351acf2']
	'evidence-check': ['a3cbb00e13f0e03354fe4bd39f3a46d277d132702ea75dacaf7bdb9514aff976', 'deca6a1fb85231c1f8570256e82c2c1acb39d925f38dce9aaea9d0afcc53b70b', 'ff4205567e24001ebd4ca486ed0de6d0f035de9eec0d316d81ba4934ec8b5193', '38d219773776a63ed6d98898d7cf12d5a1f6d773560592a43d9be29a66c3b8b5']
	'kernel-check': ['f0ae81d110d3b3db2810cf4958dffb1680155310724c428316ea61610c3c261f', 'f37b98f71433d292afa12c244befbba46dc168502ca2563b81b6e537580827e0', '1f72ecc83e2ec0834306d852d4519fe451b9cecf71a21bbe997a60bede084a59', 'e7b15edfdd8e16253cef35aa5b58a73cedb1e7ea7d9ccb9b65ea57f476308574']
}

fn digest(path string) !string { return audioprepare.digest(path) }

fn canonical(path string) ! {
	if !os.is_abs_path(path) || os.real_path(path) != path || path.bytes().any(it < 32 || it == 127) {
		return error('requires canonical absolute path: ' + path)
	}
}

fn tree(path string, depth int, started i64, mut result map[string]string) ! {
	if depth > 64 || result.len > 250000 || recoveryguard.deadline_expired(started, 120000) {
		return error('continuation inventory exceeds bounded scope')
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
	} else if kind == 0o100000 { result[path] = 'file|' + (stat.mode & 0o7777).str() + '|' + digest(path)! }
	else if kind == 0o120000 { result[path] = 'link|' + os.readlink(path)! }
	else { return error('nonordinary continuation input: ' + path) }
}

fn complete(result nativeguard.Result) ! {
	if result.reason != '' || !result.group_observed || result.held_pipe_after_leader_exit
		|| !result.cleanup.reaped || !result.cleanup.group_empty || result.cleanup.final_wait != -1
		|| result.cleanup.final_errno != C.ECHILD || result.cleanup.exit_code != 0 {
		return error('requires actual-zero reaped complete owned-group result')
	}
}

fn reused(root string) !map[string]string {
	if digest(prior + '/inputs-before.json')! != '4793180c49de684926f03d7b6b43c125d7292152de33ef2008c49a673db5e6e6'
		|| digest(prior + '/environment.json')! != 'd72fab73b2c8d8358370168343245d1f47c18cdc69c8ec698a95c3eb855c6d00' {
		return error('reviewed interrupted build input map or environment differs')
	}
	for name, source in sources {
		for index, path in [prior + '/' + name, prior + '/' + name + '.c',
			prior + '/build-' + name + '.argv.json', prior + '/build-' + name + '.result.json'] {
			if digest(path)! != pins[name][index] { return error('reviewed reusable build differs: ' + path) }
		}
		argv := [compiler, '-prod', '-nocache', '-keepc', '-backend', 'c', '-cc', clang,
			'-path', '@vlib|@vmodules|.|tests/hardware-platform|tests/software-hosted-x11|tests/software-hosted-x11/diagnostics',
			'-o', prior + '/' + name, root + '/tests/packages/' + source]
		if json2.decode[[]string](os.read_file(prior + '/build-' + name + '.argv.json')!)! != argv {
			return error('reusable build argv/source binding differs')
		}
		complete(json2.decode[nativeguard.Result](os.read_file(prior + '/build-' + name + '.result.json')!)!)!
		if os.lstat(prior + '/' + name)!.mode & 0o111 == 0 { return error('reused tool is not executable') }
	}
	mut result := map[string]string{}
	tree(prior, 0, time.sys_mono_now(), mut result)!
	return result
}

fn selected_inputs(root string, before map[string]string) !map[string]string {
	mut result := map[string]string{}
	for path in [root, os.dir(compiler), evidence, legacy] { tree(path, 0, time.sys_mono_now(), mut result)! }
	for path, _ in before { if path !in result { tree(path, 0, time.sys_mono_now(), mut result)! } }
	tree(os.executable(), 0, time.sys_mono_now(), mut result)!
	return result
}

fn run(root string, out string, charged []string, name string, argv []string) ! {
	os.write_file(out + '/' + name + '.argv.json', json2.encode(argv) + '\n')!
	mut failure := ''
	result := nativeguard.supervise(argv, root, out, charged, out + '/' + name + '.log',
		out + '/' + name + '-df', nativeguard.Limits{start_bytes: u64(2) << 30,
			floor_bytes: u64(1) << 30, cap_bytes: cap - (u64(4) << 20), wall_ms: 300000, sample_ms: 1000}) or {
		failure = recoveryguard.bounded_message(err.msg()); nativeguard.Result{}
	}
	os.write_file(out + '/' + name + '.result.json', json2.encode(result) + '\n')!
	os.write_file(out + '/' + name + '.error.json', json2.encode({'error': failure}) + '\n')!
	if failure != '' { return error(failure) }
	complete(result)!
}

fn check() ! {
	$if prod {} $else { return error('compile host continuation with -prod') }
	if digest(@FILE)! != sha256.hexhash($embed_file('audio-portal-prepare-continue.v').to_string()) {
		return error('continuation source differs from compiled source')
	}
	if os.args.len != 2 { return error('use audio-portal-prepare-continue NEW_OUTPUT') }
	root := os.dir(os.dir(os.dir(@FILE)))
	out := os.args[1]
	for path in [root, out, state, os.executable(), prior] { canonical(path)! }
	if os.dir(out) != state || os.exists(out) || os.is_link(out) || os.dir(os.executable()) != state {
		return error('requires fresh charged continuation output and bootstrap')
	}
	charged := [root, evidence, original, os.dir(manifest), legacy, state]
	os.mkdir(out, mode: 0o700)!
	nativeguard.watch_interrupts()!
	mut env := json2.decode[map[string]string](os.read_file(prior + '/environment.json')!)!
	for name in ['tmp', 'modules'] { os.mkdir(out + '/' + name, mode: 0o700)! }
	env['VTMP'] = out + '/tmp'; env['TMPDIR'] = out + '/tmp'; env['VMODULES'] = out + '/modules'
	for name, _ in os.environ() { os.unsetenv(name) }
	for name, value in env { os.setenv(name, value, true) }
	os.write_file(out + '/environment.json', json2.encode(env) + '\n')!
	os.write_file(out + '/charged-roots.json', json2.encode(charged) + '\n')!
	reused_before := reused(root)!
	os.write_file(out + '/reused-before.json', json2.encode(reused_before) + '\n')!
	old := json2.decode[map[string]string](os.read_file(prior + '/inputs-before.json')!)!
	mut captured := map[string]string{}
	tree(prior + '/source', 0, time.sys_mono_now(), mut captured)!
	mut source := map[string]string{}
	for path, value in captured {
		if value.starts_with('file|') && os.lstat(path)!.nlink != 1 { return error('interrupted source snapshot is no longer independent') }
		source[root + path[(prior + '/source').len..]] = value
	}
	mut expected_source := map[string]string{}
	for path, value in old { if path == root || path.starts_with(root + '/') { expected_source[path] = value } }
	if source != expected_source { return error('interrupted independent source snapshot differs from reviewed build inputs') }
	before := selected_inputs(root, old)!
	mut expected := old.clone()
	if @FILE in old || os.executable() in old { return error('continuation additions already existed in prior map') }
	expected[@FILE] = 'file|' + (os.lstat(@FILE)!.mode & 0o7777).str() + '|' + digest(@FILE)!
	expected[os.executable()] = 'file|' + (os.lstat(os.executable())!.mode & 0o7777).str() + '|' + digest(os.executable())!
	if before != expected { return error('complete current selected map differs beyond explicit continuation additions') }
	os.write_file(out + '/inputs-before.json', json2.encode(before) + '\n')!
	if nativeguard.allocated(charged, os.lstat(out)!.dev)! > cap - (u64(464) << 20) {
		return error('continuation lacks inclusive controls and receipt reserve')
	}
	commands := {'original-audit-before': [checker, 'check', original, manifest],
		'prepare-controls': [prior + '/prepare-check', '--out=' + out + '/prepare-controls', '--controller=' + prior + '/controller', '--kernel-evidence=' + legacy],
		'strict-controls': [prior + '/evidence-check', '--self-test', prior + '/retainer', out + '/strict-controls', 'aarch64'],
		'kernel-controls': [prior + '/kernel-check', evidence, selected, out + '/kernel-controls'],
		'original-audit-after': [checker, 'check', original, manifest]}
	for name in ['original-audit-before', 'prepare-controls', 'strict-controls', 'kernel-controls', 'original-audit-after'] {
		run(root, out, charged, name, commands[name])!
		if selected_inputs(root, old)! != before || reused(root)! != reused_before {
			return error('selected source/tool map or reused interrupted evidence changed: ' + name)
		}
	}
	os.write_file(out + '/inputs-after.json', json2.encode(selected_inputs(root, old)!) + '\n')!
	os.write_file(out + '/reused-after.json', json2.encode(reused(root)!) + '\n')!
	if os.ls(out + '/modules')!.len != 0 { return error('private modules changed') }
	os.write_file(out + '/host-build.json', json2.encode({'result': 'PASS', 'source_root': root,
		'source_revision': '37ea063a412d3dfbe7f1eb2c77fc2bc152928255', 'prior_build_root': prior,
		'continuation_source_sha256': digest(@FILE)!, 'inputs_before_sha256': digest(out + '/inputs-before.json')!,
		'inputs_after_sha256': digest(out + '/inputs-after.json')!, 'reused_before_sha256': digest(out + '/reused-before.json')!,
		'reused_after_sha256': digest(out + '/reused-after.json')!, 'control_count': '149',
		'scope': 'Six pinned successful production builds reused read-only; fresh 88 preparation, 34 strict ARM evidence and 27 matched-kernel host controls. Prior controls were interrupted. No target or guest; host loader/SDK outside selected frozen closure.'}) + '\n')!
	final_df := nativeguard.actual_df(out, out + '/final-df.log')!
	allocation := nativeguard.allocated(charged, os.lstat(out)!.dev)!
	if final_df.available < u64(1) << 30 || allocation > cap { return error('final actual df or inclusive cap refused') }
	os.write_file(out + '/qualification.json', json2.encode({'result': 'PASS', 'pathname_allocated_bytes': allocation.str(),
		'cap_bytes': cap.str(), 'host_build_sha256': digest(out + '/host-build.json')!, 'scope': 'Host controls only; no target or guest'}) + '\n')!
	println('AUDIO PREPARATION HOST CONTINUATION PASS controls=149 (no target or guest executed)')
}

fn main() { check() or { eprintln('audio-portal-prepare-continue: ' + recoveryguard.bounded_message(err.msg())); exit(1) } }
