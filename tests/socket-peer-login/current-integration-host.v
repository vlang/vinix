// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed host profile. All child ownership is the unchanged nativeguard API.
@[has_globals]
module main

import crypto.sha256
import dylibclosure
import json2
import nativeguard
import os
import sourcecommand
import time

#include <errno.h>

const repository = '/Users/alex/code/vinix'
const worktree = repository + '/build/package-peer-frame-current-20261105-worktree'
const git_admin = repository + '/.git/worktrees/package-peer-frame-current-20261105-worktree'
const donor = repository + '/build/package-peer-login-atomic-fresh-worktree'
const state = '/Users/alex/Library/Caches/vinix-codex/section14/current-peer-frame-integration-20261105-01'
const host = state + '/host-bootstrap-01'
const sources = host + '/source'
const compiler = '/Users/alex/.cache/vinix-waitpid-width-20261026-02/toolchain/v'
const kernel_compiler = repository + '/build/package-https-runtime-work/toolchain/v'
const clang = '/opt/homebrew/Cellar/llvm/23.1.0/bin/clang-23'
const sdk = '/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk'
const profile = worktree + '/tests/socket-peer-login/current-head-profile'
const host_cap = u64(64) << 20
const host_reserve = u64(16) << 20
const cumulative_cap = u64(512) << 20
const cumulative_tail = u64(1) << 20
const map_limit = 4 * 1024 * 1024

struct Scan {
mut:
	entries int
	started i64 = time.sys_mono_now()
}

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn present(path string) bool { return os.exists(path) || os.is_link(path) }
fn never() bool { return false }
fn sum(body string) string { return sha256.sum(body.bytes()).hex() }
fn roots() []string { return [worktree, state, git_admin, donor] }
fn host_roots() []string { return [host, state + '/controller-reproduction-01'] }

fn digest(path string) !string {
	before := os.lstat(path)!
	require(before.mode & 0o170000 == 0o100000, 'ordinary digest input required: ' + path)!
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		hash.write(buffer[..n])!
	}
	after := os.lstat(path)!
	require(before.dev == after.dev && before.inode == after.inode && before.mode == after.mode
		&& before.uid == after.uid && before.gid == after.gid && before.size == after.size
		&& before.mtime == after.mtime && before.ctime == after.ctime,
		'input changed during digest: ' + path)!
	return hash.sum([]u8{}).hex()
}

fn tree(path string, ancestors []string, mut scan Scan, mut result map[string]string) ! {
	scan.entries++
	require(scan.entries <= 100000 && ancestors.len <= 128
		&& time.sys_mono_now() - scan.started <= 120 * time.second, 'input inventory bound')!
	info := os.lstat(path)!
	kind := info.mode & 0o170000
	mode := (info.mode & 0o177777).str()
	if kind == 0o100000 { result[path] = mode + ':' + digest(path)! }
	else if kind == 0o040000 {
		require(path !in ancestors, 'cyclic input directory')!
		result[path] = mode + ':directory'
		mut next := ancestors.clone(); next << path
		mut names := os.ls(path)!; names.sort()
		for name in names { tree(path + '/' + name, next, mut scan, mut result)! }
	} else if kind == 0o120000 {
		resolved := os.real_path(path)
		require(resolved != '' && resolved != path && resolved !in ancestors, 'cyclic/dangling input link')!
		result[path] = mode + ':link:' + os.readlink(path)! + ':resolved:' + resolved
		mut next := ancestors.clone(); next << path
		tree(resolved, next, mut scan, mut result)!
	} else { return error('unsupported input type: ' + path) }
}

fn checked(argv []string) !string {
	result := sourcecommand.capture_combined(argv, os.environ(), 10, 4 * 1024 * 1024, never)!
	require(result.status == 0, 'bounded read-only probe failed: ' + argv.str())!
	return result.stdout
}

fn snapshot() !map[string]string {
	mut result := map[string]string{}
	mut scan := Scan{}
	tools := [compiler, kernel_compiler, clang,
		'/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-ar',
		'/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-readelf',
		'/opt/homebrew/Cellar/llvm/23.1.0/bin/llvm-nm',
		'/opt/homebrew/Cellar/lld/23.1.0/bin/ld.lld', os.executable()]
	for path in [sources, worktree, git_admin, os.dir(compiler), os.dir(kernel_compiler),
		sdk + '/SDKSettings.json', sdk + '/SDKSettings.plist',
		checked([clang, '-print-resource-dir'])!.trim_space() + '/include',
		'/bin/df', '/usr/bin/du', '/usr/bin/xcrun', '/usr/bin/otool', '/usr/bin/file',
		'/bin/sh', '/usr/bin/env', '/opt/homebrew/bin/timeout', ...tools] {
		tree(path, [], mut scan, mut result)!
	}
	loaded := dylibclosure.closure(tools, checked)!
	for path in loaded.paths { tree(path, [], mut scan, mut result)! }
	for key, value in loaded.metadata { result['loader:' + key] = value }
	result['scope'] = 'Complete named source/tool trees and loaded libraries; SDK metadata and clang resource headers, not a hermetic SDK inventory.'
	require(json2.encode(result).len <= map_limit, 'complete input map exceeds retained bound')!
	return result
}

fn environment(directory string) map[string]string {
	return {'HOME': '/Users/alex', 'USER': 'alex', 'LOGNAME': 'alex',
		'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'V': compiler, 'VEXE': compiler,
		'V_MACOS_V3_CALLER_VEXE': compiler, 'V_MACOS_V3_CALLER_VEXE_PRESENT': '1',
		'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0', 'V_MACOS_V3_NO_FALLBACK': '1',
		'V_MACOS_V3_CALLER_NO_FALLBACK': '1', 'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1',
		'VMODULES': directory + '/modules', 'V3CACHE': directory + '/cache',
		'XDG_CACHE_HOME': directory + '/cache', 'VTMP': directory + '/tmp',
		'TMPDIR': directory + '/tmp', 'SDKROOT': sdk,
		'DEVELOPER_DIR': '/Library/Developer/CommandLineTools'}
}

fn command(mode string) !([]string, int, u64) {
	mut build := [compiler, '-prod', '-nocache', '-keepc', '-cc', clang,
		'-cflags', '-Werror=incompatible-pointer-types']
	match mode {
		'preparer' {
			return [...build, '-o', host + '/preparer/prepare-current-integration-controller',
				sources + '/tests/socket-peer-login/prepare-current-integration-controller.v'], 300000, u64(16) << 20
		}
		'reproduce' { return [host + '/preparer/prepare-current-integration-controller'], 30000, u64(6) << 20 }
		'controller' {
			build << ['-enable-globals', '-o', host + '/controller/guarded-build-check', profile + '/guarded-build-check.v']
			return build, 300000, u64(16) << 20
		}
		'host-controls' { return [host + '/controller/guarded-build-check', '--host-controls', host + '/host-controls-output'], 120000, u64(8) << 20 }
		'closure-controls' { return [host + '/controller/guarded-build-check', '--closure-controls', host + '/closure-controls-output'], 120000, u64(8) << 20 }
		else { return error('only five fixed host operations are admitted') }
	}
}

fn endpoint(directory string, label string, admission bool) !map[string]string {
	device := os.lstat(state)!.dev
	allocated := nativeguard.allocated(roots(), device)!
	host_used := nativeguard.allocated(host_roots(), device)!
	text := checked(['/usr/bin/du', '-skAl', ...roots()])!
	mut apparent := u64(0)
	lines := text.trim_space().split_into_lines()
	require(lines.len == roots().len, 'complete apparent observation required')!
	for i, line in lines {
		fields := line.fields()
		require(fields.len == 2 && fields[1] == roots()[i]
			&& fields[0] != '' && fields[0].bytes().all(it >= `0` && it <= `9`), 'apparent du row differs')!
		part := fields[0].u64()
		require(part <= (cumulative_cap - apparent) / 1024, 'apparent cumulative cap exceeded')!
		apparent += part * 1024
	}
	observation := nativeguard.actual_df(state, directory + '/' + label + '-df.log')!
	os.write_file(directory + '/' + label + '-apparent.log', text)!
	result := {'allocated_bytes': allocated.str(), 'apparent_bytes': apparent.str(),
		'host_allocated_bytes': host_used.str(), 'free_bytes': observation.available.str(),
		'scope': 'Native allocated sample plus apparent endpoint only; no continuous apparent observation.'}
	os.write_file(directory + '/' + label + '-budget.json', json2.encode(result) + '\n')!
	require(allocated <= cumulative_cap - cumulative_tail && apparent <= cumulative_cap - cumulative_tail
		&& host_used <= host_cap && observation.available >= if admission { u64(2) << 30 } else { u64(1) << 30 },
		'host endpoint resource refusal; retain complete attempt')!
	return result
}

fn bindings() ! {
	require(os.read_file(@FILE)! == $embed_file('current-integration-host.v').to_string(), 'host profile source changed')!
	for path, expected in {
		sources + '/tests/software-hosted-x11/nativeguard/guard.v': '5aa9cea7b338b914f7548a9a63a86ae6874dabb373350a5605f068fa7f2858ce'
		sources + '/tests/software-hosted-x11/diagnostics/recoveryguard/recoveryguard.v': '924cf415fc8b73661700394f830dd56a421dac1f08fc3ca00421a561e520a154'
		compiler: 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
		kernel_compiler: 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
		clang: '4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8'
		profile + '/guarded-build-check.v': '46be2985c371399c6f1b6081fc58340cce9a67d20baf3bca1fc2efac4e2ccc31'
	} { require(digest(path)! == expected, 'fixed source/tool pin differs: ' + path)! }
}

fn run() ! {
	require(os.args.len == 2 && os.args[1] in ['inspect', 'preparer', 'reproduce', 'controller', 'host-controls', 'closure-controls'],
		'fixed host mode required')!
	nativeguard.watch_interrupts()!
	bindings()!
	mode := os.args[1]
	directory := host + '/' + mode
	require(!present(directory), 'fresh operation directory required')!
	os.mkdir(directory)!
	for name in ['modules', 'cache', 'tmp'] { os.mkdir(directory + '/' + name)! }
	for key in os.environ().keys() { os.unsetenv(key) }
	env := environment(directory)
	for key, value in env { os.setenv(key, value, true) }
	os.write_file(directory + '/environment.json', json2.encode(env) + '\n')!
	endpoint(directory, 'admission', true)!
	before := snapshot()!
	before_text := json2.encode(before) + '\n'
	if mode == 'inspect' {
		require(!present(host + '/inputs-before.json'), 'fresh complete baseline map required')!
		os.write_file(host + '/inputs-before.json', before_text)!
		endpoint(directory, 'final', false)!
		println('CURRENT INTEGRATION HOST INPUT MAP PASS ' + sum(before_text))
		return
	}
	baseline := os.read_file(host + '/inputs-before.json')!
	if before != json2.decode[map[string]string](baseline)! {
		os.write_file(directory + '/inputs-before-failure.json', before_text)!
		return error('complete pre-operation input map changed')
	}
	argv, wall, projection := command(mode)!
	device := os.lstat(state)!.dev
	host_used := nativeguard.allocated(host_roots(), device)!
	require(host_used <= host_cap - host_reserve && projection <= host_cap - host_reserve - host_used,
		'fixed operation does not fit host working projection and 16MiB reserve')!
	all_used := nativeguard.allocated(roots(), device)!
	require(all_used >= host_used, 'host allocation containment differs')!
	non_host := all_used - host_used
	require(non_host <= cumulative_cap - cumulative_tail - (host_cap - host_reserve), 'cumulative projected cap')!
	cap := non_host + host_cap - host_reserve
	action_pin := digest(argv[0])!
	os.write_file(directory + '/argv.json', json2.encode(argv) + '\n')!
	os.write_file(directory + '/action-input.json', json2.encode({'executable': argv[0],
		'executable_sha256': action_pin}) + '\n')!
	result := nativeguard.supervise(argv, worktree, state, roots(), directory + '/output.log', directory + '/df',
		nativeguard.Limits{start_bytes: u64(2) << 30, floor_bytes: u64(1) << 30,
			cap_bytes: cap, wall_ms: wall, sample_ms: 1000}) or {
		os.write_file(directory + '/supervisor-error.json', json2.encode({'error': err.msg()}))!
		return err
	}
	os.write_file(directory + '/result.json', json2.encode(result) + '\n')!
	after := snapshot() or {
		os.write_file(directory + '/input-inventory-error.json', json2.encode({'error': err.msg()}))!
		return err
	}
	after_text := json2.encode(after) + '\n'
	os.write_file(directory + '/inputs-after.json', after_text)!
	os.write_file(directory + '/status.json', json2.encode({'actual_child_exit': result.cleanup.exit_code.str(),
		'before_map_sha256': sum(baseline), 'after_map_sha256': sum(after_text),
		'action_executable_sha256': action_pin,
		'complete_input_maps_equal': (before == after).str(),
		'scope': 'Fixed host action under unchanged nativeguard; allocated samples and apparent endpoints only.'}) + '\n')!
	endpoint(directory, 'final', false)!
	require(nativeguard.allocated(host_roots(), device)! <= host_cap
		&& nativeguard.allocated(roots(), device)! <= cumulative_cap - cumulative_tail,
		'final receipts exceed allocated ceilings')!
	require(os.file_size(directory + '/output.log') <= 4 * 1024 * 1024, 'host output exceeds retained 4MiB endpoint limit')!
	require(result.reason == '' && result.group_observed && result.cleanup.exit_code == 0
		&& result.cleanup.reaped && result.cleanup.group_empty && result.cleanup.final_wait == -1
		&& result.cleanup.final_errno == int(C.ECHILD)
		&& digest(argv[0])! == action_pin && before == after, 'fixed host operation failed; retain all evidence')!
	println('CURRENT INTEGRATION HOST OPERATION PASS ' + mode)
}

fn main() { run() or { eprintln(err); exit(1) } }
