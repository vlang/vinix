// SPDX-License-Identifier: GPL-2.0-or-later
// Finish the final read-only audit after the preserved 149-control host run.
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
const prior = state + '/qualification-07'
const compiler = '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v'
const clang = '/opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23'
const evidence = '/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-kernel-20261026'
const original = '/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-20261026'
const manifest = '/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-20261026-seal-01/complete/inventory.json'
const checker = '/Users/alex/Library/Caches/vinix-codex/section14/alloc-track-frame-kernel-20261026-seal-02/frame-page-seal'
const legacy = '/Users/alex/Library/Caches/vinix-codex/section14/audio-peer-login-20261026/kernel-evidence'
const selected = '1111f8d6451a0ab94361c3ebf006e9ceed62baea9dd395ac0a5c3caa7fb3a254'
const cap = u64(2048) << 20
const sources = {'runner': 'audio-portal-prepare-run.v', 'controller': 'audio-portal-runtime-check.v',
	'retainer': 'audio-portal-retain.v', 'prepare-check': 'audio-portal-prepare-check.v',
	'evidence-check': 'audio-portal-evidence-check.v', 'kernel-check': 'audio-kernel-check.v'}
// Executable, generated C, exact build argv and actual successful result.
const pins = {
	'runner': ['ad1227907b326b96d9f0dfd10e97f45604d09155c448fc8d8ce79f7b1a7eddad', 'a771c23a22ee008371eb7cf6677e031315c82f5dd1d4d61fe925f465dea06749', 'd4123c71079069bf17d4ad30b170673ad935c28b71ba9090b8192121509126ef', 'b4be7268f06b0bca95adb9fad61ce2366f83cd3935601bb5278734f9783b3e05']
	'controller': ['0816faf0167379cb2a5fb92509310763527aab4de128af928818443242e6d766', 'ccac4dbab0dcd998c780a844091cd958255efb5b6ca1faa7e853f21f22d73690', '46ff9b3bb12e1672b5d9ec5c4282eb7820cbeccd7e1635186074241cbf80635d', 'c6b7a0436a66875d7ce056bf04e9489d9f6397d1badf2c22dcf2f2783a3dee06']
	'retainer': ['85b3da659b7e873b4e26d08088d851b3b2e7c9c57cd5095e24881074570c5a0b', '35c7f8ac8f6278b89d4cbaf980a7c2b3ea033ead535d84688c7745dd158e4ce3', '4bce4f48c7bc46766d1fbc654d025b84cb72ca92823b3c443f7a282486097355', '1b7970ee1b03b902a2c365cd81b9d69c97b3cd46d675a57b17a8770c13fe1fc7']
	'prepare-check': ['c957c73dc0aaf1da4ab63061b2534110de0ccb61d2f443707cea1adc8997509e', 'e1bcd27c98de0d71054d9bec9e6c0a70d04a20a2ee872a0d15908e0f11888033', 'cb79feadf056afa375e6f25c81df4b99480a9f302107d79ab7c1c4ce9b9122c7', 'f30c836b8f434a899e211132cc00b5123e09c7992a71695b5275fb2baa17d0ce']
	'evidence-check': ['a3cbb00e13f0e03354fe4bd39f3a46d277d132702ea75dacaf7bdb9514aff976', 'deca6a1fb85231c1f8570256e82c2c1acb39d925f38dce9aaea9d0afcc53b70b', '90b719f9dbfe51ae81f841c23f256c6651d6a6aaf421a01e3d52c50bb643773b', '1e7a049a88d87af2f0875b45cd36303bb0e1fbb88dfdef88652406581861ae7f']
	'kernel-check': ['9fd9f7a06167735e7da4f6845a0d06a0d09f5713f6f2aa67366c220116cee037', 'c0ee13a0bdaf9aa91024bcd9037936ee2a39255a57642a1750ebca12c1cd2568', '68d49f2c1ff14b2600539c48d9407df0627aaf8ff43e52060de85c6151e853ce', 'eea05ee5e7d5977ac02146fa7e58471bf84054f13a466096870f0e0347fc552d']
}
// Actual successful result and literal log for each reused check.
const checks = {
	'original-audit-before': ['788324fd3d6438de71a3abe5629f8b3c2c1d85803b0df760b8ef97d856cffc2c', 'a0f49b6703f4c067b1166aebd9cfe67bdc22b9c52ab17c7dbbacea91a20e82b7', 'FRAME-PAGE COMPLETE STATE CHECK PASS\n']
	'prepare-controls': ['44a350cf0021a39dffaed885164a4b254b4ce3ed59ad6a4d4a7abe71ae65f171', '6f542251a87306a708eb9b82418cbf0fb2142a3dd38fdfde72f8e7e2f023f812', 'AUDIO PREPARATION TREE PASS controls=88\n']
	'strict-controls': ['93dc75bdf66c20cddcb0f3311bd28b542d2494824ab8cfd04854ea3f82367eff', 'a5d2914770299f3426b387da73cabe52ccd75b46a818bec0d3a473fd7f12eb25', 'AUDIO PORTAL EVIDENCE PASS controls=34 platform=synthetic-audio-retainer-control\n']
	'kernel-controls': ['269563ecf3bc159488ac5cbedee1163d0035019e284b01f666def86991ed2b45', 'c3e3975a5a028cfe82fefe7260f87ab661d2754f8efcd4ff087a22599e899452', 'AUDIO KERNEL HOST CHECK PASS controls=27 (no guest executed)\n']
}

fn digest(path string) !string { return audioprepare.digest(path) }

fn canonical(path string) ! {
	if !os.is_abs_path(path) || os.real_path(path) != path || path.bytes().any(it < 32 || it == 127) {
		return error('requires canonical absolute finalization path: ' + path)
	}
}

fn tree(path string, depth int, started i64, mut result map[string]string) ! {
	if depth > 64 || result.len > 250000 || recoveryguard.deadline_expired(started, 120000) {
		return error('finalization inventory exceeds bounded scope')
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
	else { return error('nonordinary finalization input: ' + path) }
}

fn complete(result nativeguard.Result) ! {
	if result.reason != '' || !result.group_observed || result.held_pipe_after_leader_exit
		|| !result.cleanup.reaped || !result.cleanup.group_empty || result.cleanup.final_wait != -1
		|| result.cleanup.final_errno != C.ECHILD || result.cleanup.exit_code != 0 {
		return error('requires actual-zero reaped complete owned-group result')
	}
}

fn reused(root string) !map[string]string {
	if digest(prior + '/inputs-before.json')! != '4aa4563ddc68a7ed9f6221cbd4ea0d661d236b9119d3e4a44983cd3c999bcb49'
		|| digest(prior + '/environment.json')! != '5ea32aa32ad2ce0fcbb96d2106a36b3cecef1f2c27738465a6c4680b54578bc7' {
		return error('reviewed07 input map or environment differs')
	}
	for name, source in sources {
		for index, path in [prior + '/' + name, prior + '/' + name + '.c',
			prior + '/build-' + name + '.argv.json', prior + '/build-' + name + '.result.json'] {
			if digest(path)! != pins[name][index] { return error('reviewed07 build differs: ' + path) }
		}
		argv := [compiler, '-prod', '-nocache', '-keepc', '-backend', 'c', '-cc', clang,
			'-path', '@vlib|@vmodules|.|tests/hardware-platform|tests/software-hosted-x11|tests/software-hosted-x11/diagnostics',
			'-o', prior + '/' + name, root + '/tests/packages/' + source]
		if json2.decode[[]string](os.read_file(prior + '/build-' + name + '.argv.json')!)! != argv {
			return error('reused07 build argv/source binding differs')
		}
		complete(json2.decode[nativeguard.Result](os.read_file(prior + '/build-' + name + '.result.json')!)!)!
		if os.lstat(prior + '/' + name)!.mode & 0o111 == 0 { return error('reused07 tool is not executable') }
	}
	commands := {'original-audit-before': [checker, 'check', original, manifest],
		'prepare-controls': [prior + '/prepare-check', '--out=' + prior + '/prepare-controls', '--controller=' + prior + '/controller', '--kernel-evidence=' + legacy],
		'strict-controls': [prior + '/evidence-check', '--self-test', prior + '/retainer', prior + '/strict-controls', 'aarch64'],
		'kernel-controls': [prior + '/kernel-check', evidence, selected, prior + '/kernel-controls']}
	for name, pin in checks {
		if digest(prior + '/' + name + '.result.json')! != pin[0]
			|| digest(prior + '/' + name + '.log')! != pin[1]
			|| os.read_file(prior + '/' + name + '.log')! != pin[2]
			|| json2.decode[[]string](os.read_file(prior + '/' + name + '.argv.json')!)! != commands[name] {
			return error('reviewed07 check argv/result/log differs: ' + name)
		}
		complete(json2.decode[nativeguard.Result](os.read_file(prior + '/' + name + '.result.json')!)!)!
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

fn check() ! {
	$if prod {} $else { return error('compile finalizer with -prod') }
	if digest(@FILE)! != sha256.hexhash($embed_file('audio-portal-prepare-finish.v').to_string()) { return error('finalizer source differs') }
	if os.args.len != 2 { return error('use audio-portal-prepare-finish NEW_OUTPUT') }
	root := os.dir(os.dir(os.dir(@FILE)))
	out := os.args[1]
	for path in [root, out, state, os.executable(), prior] { canonical(path)! }
	if os.dir(out) != state || os.exists(out) || os.is_link(out) || os.dir(os.executable()) != state {
		return error('requires fresh charged output and bootstrap')
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
		if value.starts_with('file|') && os.lstat(path)!.nlink != 1 { return error('07 source snapshot is no longer independent') }
		source[root + path[(prior + '/source').len..]] = value
	}
	mut expected_source := map[string]string{}
	for path, value in old { if path == root || path.starts_with(root + '/') { expected_source[path] = value } }
	if source != expected_source { return error('07 independent source snapshot differs from fixed build inputs') }
	before := selected_inputs(root, old)!
	mut expected := old.clone()
	if @FILE in old || os.executable() in old { return error('finalizer additions already existed in07 map') }
	expected[@FILE] = 'file|' + (os.lstat(@FILE)!.mode & 0o7777).str() + '|' + digest(@FILE)!
	expected[os.executable()] = 'file|' + (os.lstat(os.executable())!.mode & 0o7777).str() + '|' + digest(os.executable())!
	if before != expected { return error('complete current selected map differs beyond explicit finalizer additions') }
	os.write_file(out + '/inputs-before.json', json2.encode(before) + '\n')!
	if nativeguard.allocated(charged, os.lstat(out)!.dev)! > cap - (u64(64) << 20) { return error('finalizer lacks bounded receipt reserve') }
	argv := [checker, 'check', original, manifest]
	os.write_file(out + '/original-audit-after.argv.json', json2.encode(argv) + '\n')!
	mut failure := ''
	result := nativeguard.supervise(argv, root, out, charged, out + '/original-audit-after.log',
		out + '/original-audit-after-df', nativeguard.Limits{start_bytes: u64(2) << 30,
			floor_bytes: u64(1) << 30, cap_bytes: cap - (u64(4) << 20), wall_ms: 300000, sample_ms: 1000}) or {
		failure = recoveryguard.bounded_message(err.msg()); nativeguard.Result{}
	}
	os.write_file(out + '/original-audit-after.result.json', json2.encode(result) + '\n')!
	os.write_file(out + '/original-audit-after.error.json', json2.encode({'error': failure}) + '\n')!
	if failure != '' { return error(failure) }
	complete(result)!
	if os.read_file(out + '/original-audit-after.log')! != 'FRAME-PAGE COMPLETE STATE CHECK PASS\n' { return error('final original audit output differs') }
	after := selected_inputs(root, old)!
	reused_after := reused(root)!
	os.write_file(out + '/inputs-after.json', json2.encode(after) + '\n')!
	os.write_file(out + '/reused-after.json', json2.encode(reused_after) + '\n')!
	if before != after || reused_before != reused_after || os.ls(prior + '/modules')!.len != 0
		|| os.ls(out + '/modules')!.len != 0 { return error('selected inputs, reused07 evidence or modules changed') }
	final_df := nativeguard.actual_df(out, out + '/final-df.log')!
	allocation := nativeguard.allocated(charged, os.lstat(out)!.dev)!
	if final_df.available < u64(1) << 30 || allocation > cap { return error('final namespace or actual df refused') }
	os.write_file(out + '/qualification.json', json2.encode({'result': 'PASS', 'reused_host_root': prior,
		'source_revision': '37ea063a412d3dfbe7f1eb2c77fc2bc152928255', 'production_builds': '6', 'controls': '149',
		'reused_before_sha256': digest(out + '/reused-before.json')!, 'reused_after_sha256': digest(out + '/reused-after.json')!,
		'inputs_before_sha256': digest(out + '/inputs-before.json')!, 'inputs_after_sha256': digest(out + '/inputs-after.json')!,
		'original_audit_after_result_sha256': digest(out + '/original-audit-after.result.json')!,
		'pathname_allocated_bytes': allocation.str(), 'cap_bytes': cap.str(),
		'scope': 'Reused six actual-zero07 builds and149 controls; final original full audit and exact source/tool/evidence maps. No target or VM; host SDK and loader outside selected namespace.'}) + '\n')!
	println('AUDIO PREPARATION HOST FINALIZATION PASS builds=6 controls=149 (no target or guest executed)')
}

fn main() { check() or { eprintln('audio-portal-prepare-finish: ' + recoveryguard.bounded_message(err.msg())); exit(1) } }
