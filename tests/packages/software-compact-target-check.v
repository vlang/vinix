// SPDX-License-Identifier: GPL-2.0-or-later
// Own the unchanged target recipe's complete subprocess group and state budget.
module main

import crypto.sha256
import json2
import os
import time
import tools.sourcecommand

#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <errno.h>

const compact_sources = ['desktop/software_app.v', 'desktop/software_launch.v',
	'desktop/software_launch_navigation.v']!
const state_limit = u64(768 * 1024 * 1024)
const log_limit = u64(16 * 1024 * 1024)

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn write_json(path string, value map[string]string) ! { os.write_file(path, json2.encode(value) + '\n')! }

struct Budget {
mut:
	bytes u64
	entries int
}

// Transient compiler scratch entries may disappear while observed. Never follow
// a symlink, and charge directory/link metadata as well as all regular bytes.
fn charge(path string, depth int, deadline u64, mut budget Budget) ! {
	require(depth <= 128 && budget.entries < 250000 && time.sys_mono_now() < deadline,
		'state inventory bound exceeded')!
	info := os.lstat(path) or { if err.code() == C.ENOENT { return }; return err }
	budget.entries++
	require(info.size <= state_limit - budget.bytes, 'inclusive state exceeded 768 MiB')!
	budget.bytes += info.size
	match info.get_filetype() {
		.regular {
			if path.ends_with('.log') { require(info.size <= log_limit, 'log exceeded 16 MiB: ' + path)! }
		}
		.symbolic_link {}
		.directory {
			names := os.ls(path) or { if err.code() == C.ENOENT { return }; return err }
			for name in names { charge(path + '/' + name, depth + 1, deadline, mut budget)! }
		}
		else { return error('unsupported state object: ' + path) }
	}
}

struct Phase {
	roots []string
	limit int
mut:
	pid int
	peak u64
	samples int
}

fn sample(mut phase Phase) ! {
	mut budget := Budget{}
	deadline := time.sys_mono_now() + 2 * u64(time.second)
	for root in phase.roots { charge(root, 0, deadline, mut budget)! }
	if budget.bytes > phase.peak { phase.peak = budget.bytes }
	phase.samples++
}

fn observe(pid int, context voidptr) ! {
	mut phase := unsafe { &Phase(context) }
	phase.pid = pid
	require(pid > 1 && C.getpgid(pid) == pid && pid != C.getpgid(0), 'child group not private')!
	started := time.sys_mono_now()
	mut next_sample := u64(0)
	for {
		now := time.sys_mono_now()
		if now >= next_sample { sample(mut phase)!; next_sample = now + 250 * u64(time.millisecond) }
		if sourcecommand.child_exited(pid)! { sample(mut phase)!; return }
		require(now - started < u64(phase.limit) * u64(time.second), 'owned phase deadline exceeded')!
		time.sleep(10 * time.millisecond)
	}
}

fn retired(pid int) ! {
	require(pid > 1 && pid != C.getpgid(0), 'invalid retirement identity')!
	deadline := time.sys_mono_now() + 5 * u64(time.second)
	for {
		if C.kill(-pid, 0) == -1 && C.errno == C.ESRCH { break }
		require(time.sys_mono_now() < deadline, 'owned group remained')!
		time.sleep(10 * time.millisecond)
	}
	mut status := i32(0)
	require(C.waitpid(-1, &status, C.WNOHANG) == -1 && C.errno == C.ECHILD, 'waitable child remained')!
}

fn invoke(argv []string, log string, limit int, roots []string) ! {
	os.write_file(log + '.argv.json', json2.encode(argv) + '\n')!
	mut phase := Phase{roots: roots, limit: limit}
	sample(mut phase)!
	mut refusal := ''
	output := sourcecommand.run_logged_owned(argv, os.environ(), unsafe { nil }, log, false, '',
		observe, &phase, 0) or { refusal = err.msg(); sourcecommand.Output{} }
	mut receipt := {'exit': if refusal == '' { output.status.str() } else { 'unavailable' },
		'pid': phase.pid.str(), 'refusal': refusal, 'limit_seconds': limit.str(),
		'sampled_peak_bytes': phase.peak.str(), 'samples': phase.samples.str(), 'cleanup': 'pending'}
	write_json(log + '.exit.json', receipt)!
	if phase.pid > 1 { retired(phase.pid)! }
	receipt['cleanup'] = 'private group absent; sole reap complete; ECHILD'
	write_json(log + '.exit.json', receipt)!
	require(refusal == '', refusal + '; see ' + log)!
	sample(mut phase)!
	require(output.status == 0, 'command failed; see ' + log)!
}

fn owner_inputs(root string) !map[string]string {
	mut names := ['tests/packages/software-compact-target-check.v',
		'tests/packages/section14-target-build.v', 'build-support/find-v.sh', 'tools/sourcecommand/abi.h']
	for directory in ['tools/sourcecommand', 'desktop/tools/hosttest', 'desktop/tools/workflowbuild']! {
		for path in os.walk_ext(root + '/' + directory, '') {
			if os.is_file(path) && !path.ends_with('_test.v') { names << path[root.len + 1..] }
		}
	}
	names << compact_sources[..]
	mut result := map[string]string{}
	for name in names { result[name] = digest(root + '/' + name)! }
	return result
}

fn run() ! {
	$if prod {} $else { return error('compile owner with -prod') }
	require(os.args.len == 7, 'use V LLVM_BIN DEPENDENCIES UI NEW-OUT BOOTSTRAP')!
	root := os.real_path(@DIR + '/../..')
	v := os.real_path(os.args[1]); llvm := os.real_path(os.args[2])
	dependencies := os.real_path(os.args[3]); ui := os.real_path(os.args[4])
	out := os.args[5]; bootstrap := os.args[6]
	require(out.starts_with('/') && !os.exists(out) && !os.is_link(out)
		&& os.real_path(os.dir(out)) == os.dir(out), 'output must be fresh under canonical parent')!
	require(bootstrap == os.real_path(bootstrap) && os.is_dir(bootstrap), 'bootstrap must be canonical')!
	require(bootstrap != out && !bootstrap.starts_with(out + '/') && !out.starts_with(bootstrap + '/'), 'charge roots must be disjoint')!
	inputs := owner_inputs(root)!
	require(inputs['tests/packages/software-compact-target-check.v'] == sha256.sum($embed_file('software-compact-target-check.v').to_bytes()).hex(), 'owner source changed')!
	for name, embedded in {
		'abi.h': $embed_file('../../tools/sourcecommand/abi.h').to_bytes()
		'core.v': $embed_file('../../tools/sourcecommand/core.v').to_bytes()
		'duplex.v': $embed_file('../../tools/sourcecommand/duplex.v').to_bytes()
		'logged.v': $embed_file('../../tools/sourcecommand/logged.v').to_bytes()
		'pty.v': $embed_file('../../tools/sourcecommand/pty.v').to_bytes()
		'reader.v': $embed_file('../../tools/sourcecommand/reader.v').to_bytes()
	} { require(inputs['tools/sourcecommand/' + name] == sha256.sum(embedded).hex(), 'command owner source changed')! }
	os.mkdir(out)!
	for name in ['empty-vmodules', 'vtmp', 'tmp', 'owner-inputs']! { os.mkdir(out + '/' + name)! }
	for name, _ in inputs {
		os.mkdir_all(os.dir(out + '/owner-inputs/' + name))!
		os.cp(root + '/' + name, out + '/owner-inputs/' + name)!
	}
	for key in ['V', 'VEXE', 'V_MACOS_V3_CALLER_VEXE'] { os.setenv(key, v, true) }
	for key in ['V_MACOS_V3_CALLER_VEXE_PRESENT', 'V_MACOS_V3_NO_FALLBACK',
		'V_MACOS_V3_CALLER_NO_FALLBACK', 'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT'] { os.setenv(key, '1', true) }
	os.setenv('V_MACOS_V3_CALLER_VCHILD_PRESENT', '0', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('V_SKIP_VVMRC', '1', true)
	os.setenv('LLVM_BIN', llvm, true)
	os.setenv('PATH', '/opt/homebrew/bin:/opt/homebrew/opt/llvm/bin:/usr/bin:/bin:/usr/sbin:/sbin', true)
	for name, key in {'empty-vmodules': 'VMODULES', 'vtmp': 'VTMP', 'tmp': 'TMPDIR'} {
		os.setenv(key, os.real_path(out + '/' + name), true)
	}
	mut environment := map[string]string{}
	for key in ['V', 'VEXE', 'V_MACOS_V3_CALLER_VEXE', 'V_MACOS_V3_CALLER_VEXE_PRESENT',
		'V_MACOS_V3_CALLER_VCHILD_PRESENT', 'V_MACOS_V3_NO_FALLBACK', 'V_MACOS_V3_CALLER_NO_FALLBACK',
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT', 'LLVM_BIN', 'PATH', 'VMODULES', 'VTMP', 'TMPDIR', 'V_SKIP_VVMRC'] {
		environment[key] = os.getenv(key)
	}
	write_json(out + '/environment.json', environment)!
	write_json(out + '/owner-inputs-before.json', inputs)!
	mut tools := map[string]string{}
	for path in [v, os.real_path(llvm + '/clang'), os.real_path('/opt/homebrew/bin/ld.lld'), os.real_path(os.executable())] {
		tools[path] = digest(path)!
	}
	write_json(out + '/owner-tools-before.json', tools)!
	roots := [out, bootstrap]
	runner := out + '/target-build'
	invoke([v, '-prod', '-nocache', '-cc', llvm + '/clang', '-path', '@vlib|' + root + '/desktop/tools|' + root + '|@vmodules',
		'-o', runner, root + '/tests/packages/section14-target-build.v'], out + '/runner.build.log', 240, roots)!
	invoke([runner, '--out=' + out + '/bundle', '--dependencies=' + dependencies, '--ui=' + ui], out + '/target.log', 1800, roots)!
	invoke([runner, '--check=' + out + '/bundle'], out + '/original-check.log', 240, roots)!
	before := json2.decode[map[string]string](os.read_file(out + '/bundle/source-before.json')!)!
	after := json2.decode[map[string]string](os.read_file(out + '/bundle/source-after.json')!)!
	for name in compact_sources {
		expected := inputs[name]
		require(before[name] == expected && after[name] == expected && digest(out + '/bundle/source/' + name)! == expected,
			'compact source capture mismatch: ' + name)!
		for arch in ['aarch64', 'x86_64']! {
			require(digest(out + '/bundle/' + arch + '/app/' + os.file_name(name))! == expected, 'compact staged source mismatch')!
		}
	}
	current := owner_inputs(root)!
	write_json(out + '/owner-inputs-after.json', current)!
	require(inputs == current, 'owner/build/source inputs changed')!
	mut after_tools := map[string]string{}
	for path, _ in tools { after_tools[path] = digest(path)! }
	write_json(out + '/owner-tools-after.json', after_tools)!
	require(tools == after_tools, 'compiler inputs changed')!
	write_json(out + '/result.json', {'outcome': 'PASS', 'scope': 'both full compositor static cross-links; no guest rendering',
		'inner_scope': 'unchanged release-save-policy named five-source scope; complete copied source and explicit compact-three byte equality',
		'compact_source_binding': 'owner-inputs-before/after and bundle source-before/after plus both staged apps',
		'state_limit_bytes': state_limit.str(), 'log_limit_bytes': log_limit.str(),
		'ownership': 'private group retained with WNOWAIT through retirement; sole reap; absent group and ECHILD',
		'toolchain_limit': 'selected executable/input receipts; imported vlib, headers, sysroot/tool transitive inputs not fully frozen; not hermetic'})!
	mut final := Phase{roots: roots}
	sample(mut final)!
	println('SOFTWARE COMPACT TARGET CHECK PASS')
}

fn main() { run() or { eprintln(err); exit(1) } }
