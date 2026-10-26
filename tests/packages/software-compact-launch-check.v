// SPDX-License-Identifier: GPL-2.0-or-later
// Headless host checks with copied project/UI inputs, not a hermetic toolchain.
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

const driver_path = 'tests/packages/software-compact-launch-check.v'
const focused_marker = 'Software compact launch: PASS'
const entry_marker = 'Software compact launch entry: PASS'
const state_limit = u64(512 * 1024 * 1024)
const log_limit = u64(16 * 1024 * 1024)

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

struct Budget {
mut:
	bytes u64
	entries int
}

// Charge every observed object without following links. Compiler scratch files
// can disappear during an inventory; all other filesystem errors refuse it.
fn charge(path string, depth int, deadline u64, mut budget Budget) ! {
	require(depth <= 128 && budget.entries < 250000 && time.sys_mono_now() < deadline,
		'state inventory bound exceeded')!
	info := os.lstat(path) or { if err.code() == C.ENOENT { return }; return err }
	budget.entries++
	require(info.size <= state_limit - budget.bytes, 'inclusive state exceeded 512 MiB')!
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
	group_observation string
}

fn sample(mut phase Phase) ! {
	mut budget := Budget{}
	deadline := time.sys_mono_now() + 2 * u64(time.second)
	for root in phase.roots { charge(root, 0, deadline, mut budget)! }
	if budget.bytes > phase.peak { phase.peak = budget.bytes }
	phase.samples++
}

fn observe_phase(pid int, context voidptr) ! {
	mut phase := unsafe { &Phase(context) }
	phase.pid = pid
	require(pid > 1 && pid != C.getpgid(0), 'invalid child group identity')!
	started := time.sys_mono_now()
	mut next_sample := u64(0)
	for {
		now := time.sys_mono_now()
		if now >= next_sample { sample(mut phase)!; next_sample = now + 250 * u64(time.millisecond) }
		if phase.group_observation == '' {
			group := C.getpgid(pid)
			group_error := C.errno
			if group == pid {
				phase.group_observation = 'private process group observed'
			} else {
				// Spawn configured the private group atomically. Darwin can remove
				// it just before publishing a fast leader's WNOWAIT exit record.
				require(group < 0 && group_error == C.ESRCH, 'child group not private')!
				if sourcecommand.child_exited(pid)! {
					phase.group_observation = 'leader exit observed with WNOWAIT after getpgid ESRCH'
					sample(mut phase)!
					return
				}
				require(time.sys_mono_now() - started < 5 * u64(time.second), 'child group exit observation timed out')!
				time.sleep(time.millisecond)
				continue
			}
		}
		if sourcecommand.child_exited(pid)! { sample(mut phase)!; return }
		require(time.sys_mono_now() - started < u64(phase.limit) * u64(time.second), 'phase deadline exceeded')!
		time.sleep(10 * time.millisecond)
	}
}

fn phase_retired(pid int) ! {
	require(pid > 1 && pid != C.getpgid(0), 'invalid phase group')!
	deadline := time.sys_mono_now() + 5 * u64(time.second)
	for {
		if C.kill(-pid, 0) == -1 && C.errno == C.ESRCH { break }
		require(time.sys_mono_now() < deadline, 'phase group remained after retirement')!
		time.sleep(10 * time.millisecond)
	}
	mut raw := i32(0)
	result := C.waitpid(-1, &raw, C.WNOHANG)
	require(result == -1 && C.errno == C.ECHILD, 'waitable phase child remained')!
}

fn invoke(argv []string, log string, roots []string) !(int, string) {
	os.write_file(log + '.argv.json', json2.encode(argv) + '\n')!
	mut phase := Phase{roots: roots, limit: if log.ends_with('.build.log') { 600 } else { 120 }}
	sample(mut phase)!
	mut refusal := ''
	output := sourcecommand.run_logged_owned(argv, os.environ(), unsafe { nil }, log, false, '', observe_phase, &phase, 0) or {
		refusal = err.msg(); sourcecommand.Output{}
	}
	mut receipt := {'exit_code': if refusal == '' { output.status.str() } else { 'unavailable after observer refusal' },
		'pid': phase.pid.str(), 'limit_seconds': phase.limit.str(), 'refusal': refusal,
		'group_observation': phase.group_observation,
		'sampled_peak_bytes': phase.peak.str(), 'samples': phase.samples.str(), 'cleanup': 'pending'}
	os.write_file(log + '.exit.json', json2.encode(receipt) + '\n')!
	if phase.pid > 1 { phase_retired(phase.pid)! }
	receipt['cleanup'] = if phase.pid > 1 { 'private process group absent; sole reap complete; ECHILD' } else { 'no child group started' }
	os.write_file(log + '.exit.json', json2.encode(receipt) + '\n')!
	require(refusal == '', refusal + '; see ' + log)!
	sample(mut phase)!
	require(os.file_size(log) <= log_limit, 'phase log exceeded 16 MiB')!
	text := os.read_file(log)!
	for forbidden in ['V panic:', 'ERROR: AddressSanitizer', 'SUMMARY: AddressSanitizer',
		'UndefinedBehaviorSanitizer', 'runtime error:'] {
		require(!text.contains(forbidden), 'runtime diagnostic; see ' + log)!
	}
	return output.status, text
}

fn project_sources(root string) ![]string {
	mut paths := [driver_path, 'desktop/tools/tests/heap_tracker.h']
	paths << 'tools/sourcecommand/abi.h'
	for directory in ['tools/packages', 'tools/accounts', 'desktop/packagecore', 'desktop/workflowcore',
		'desktop/reportcore', 'desktop/sessioncore', 'desktop/sessionipc', 'desktop/sessionruntime', 'compat/ios/plist', 'tools/sourcecommand']! {
		for path in os.walk_ext(root + '/' + directory, '.v') {
			if !path.ends_with('_test.v') { paths << path[root.len + 1..] }
		}
	}
	for name in os.ls(root + '/desktop')! {
		if name.starts_with('software_') && name.ends_with('.v') { paths << 'desktop/' + name }
	}
	for name in os.ls(root + '/tests/packages')! {
		if name.starts_with('software_') && name.ends_with('_fixture.v') && name != 'software_image_fixture.v' {
			paths << 'tests/packages/' + name
		}
	}
	paths.sort()
	return paths
}

fn ui_sources(modules string) []string {
	mut paths := ['ui2/v.mod']
	for path in os.walk_ext(modules + '/ui2/ui', '.v') {
		if !path.ends_with('_test.v') { paths << path[modules.len + 1..] }
	}
	paths.sort()
	return paths
}

fn inventory(root string, paths []string) !map[string]string {
	mut hashes := map[string]string{}
	for path in paths { hashes[path] = digest(root + '/' + path)! }
	return hashes
}

fn verify(root string, paths []string, expected map[string]string) ! {
	require(inventory(root, paths)! == expected, 'input bytes changed under ' + root)!
}

fn copy_inputs(root string, target string, paths []string) ! {
	for path in paths {
		os.mkdir_all(os.dir(target + '/' + path))!
		os.cp(root + '/' + path, target + '/' + path)!
	}
}

fn one_marker(text string, marker string) ! {
	require(text.split_into_lines().filter(it == marker).len == 1, 'PASS marker missing or duplicated: ' + marker)!
}

fn qualify(root string, output string, bootstrap string, mut receipt map[string]string) ! {
	$if prod {} $else { return error('compile software-compact-launch-check with -prod') }
	embedded := sha256.sum($embed_file('software-compact-launch-check.v').to_bytes()).hex()
	require(digest(@FILE)! == embedded, 'driver source differs from executable')!
	v := os.real_path(os.args[1]); cc := os.real_path(os.args[2]); modules := os.real_path(os.args[3])
	require(os.is_file(v) && os.is_file(cc) && os.is_file(modules + '/ui2/v.mod'), 'provide V, Clang and UI modules')!
	for key in ['V', 'VEXE', 'V_MACOS_V3_CALLER_VEXE'] { os.setenv(key, v, true) }
	os.setenv('V_MACOS_V3_CALLER_VEXE_PRESENT', '1', true)
	os.setenv('V_MACOS_V3_CALLER_VCHILD_PRESENT', '0', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_MACOS_V3_CALLER_NO_FALLBACK', '1', true)
	os.setenv('V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('V_SKIP_VVMRC', '1', true)
	os.setenv('LLVM_BIN', os.dir(cc), true)
	os.setenv('PATH', '/opt/homebrew/bin:/opt/homebrew/opt/llvm/bin:/usr/bin:/bin:/usr/sbin:/sbin', true)
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0:abort_on_error=1', true)
	os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	for name in ['empty-vmodules', 'vtmp', 'tmp']! { os.mkdir(output + '/' + name)! }
	os.setenv('VMODULES', os.real_path(output + '/empty-vmodules'), true)
	os.setenv('VTMP', os.real_path(output + '/vtmp'), true)
	os.setenv('TMPDIR', os.real_path(output + '/tmp'), true)
	mut environment := map[string]string{}
	for key in ['V', 'VEXE', 'V_MACOS_V3_CALLER_VEXE', 'V_MACOS_V3_CALLER_VEXE_PRESENT',
		'V_MACOS_V3_CALLER_VCHILD_PRESENT', 'V_MACOS_V3_NO_FALLBACK', 'V_MACOS_V3_CALLER_NO_FALLBACK',
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT', 'V_C_ERROR_BUG_REPORT_DISABLED', 'V_SKIP_VVMRC',
		'LLVM_BIN', 'PATH', 'VMODULES', 'VTMP', 'TMPDIR', 'ASAN_OPTIONS', 'UBSAN_OPTIONS'] {
		environment[key] = os.getenv(key)
	}
	os.write_file(output + '/environment.json', json2.encode(environment) + '\n')!
	roots := [output, bootstrap]
	mut initial := Phase{roots: roots}
	sample(mut initial)!
	paths := project_sources(root)!; ui_paths := ui_sources(modules)
	hashes := inventory(root, paths)!; ui_hashes := inventory(modules, ui_paths)!
	require(hashes[driver_path] == embedded, 'captured driver differs from executable')!
	require(hashes['tools/sourcecommand/abi.h'] == sha256.sum($embed_file('../../tools/sourcecommand/abi.h').to_bytes()).hex()
		&& hashes['tools/sourcecommand/core.v'] == sha256.sum($embed_file('../../tools/sourcecommand/core.v').to_bytes()).hex()
		&& hashes['tools/sourcecommand/duplex.v'] == sha256.sum($embed_file('../../tools/sourcecommand/duplex.v').to_bytes()).hex()
		&& hashes['tools/sourcecommand/logged.v'] == sha256.sum($embed_file('../../tools/sourcecommand/logged.v').to_bytes()).hex()
		&& hashes['tools/sourcecommand/pty.v'] == sha256.sum($embed_file('../../tools/sourcecommand/pty.v').to_bytes()).hex()
		&& hashes['tools/sourcecommand/reader.v'] == sha256.sum($embed_file('../../tools/sourcecommand/reader.v').to_bytes()).hex(), 'command owner source differs from executable')!
	compiler_paths := [v, cc, os.real_path(os.executable())]
	mut compiler_pins := map[string]string{}
	for path in compiler_paths { compiler_pins[path] = digest(path)! }
	os.write_file(output + '/executables.json', json2.encode(compiler_pins) + '\n')!
	os.write_file(output + '/sources.json', json2.encode(hashes) + '\n')!
	os.write_file(output + '/ui-sources.json', json2.encode(ui_hashes) + '\n')!
	revision_code, revision := invoke(['/usr/bin/git', '-C', root, 'rev-parse', 'HEAD'], output + '/revision.log', roots)!
	require(revision_code == 0 && revision.trim_space().len == 40, 'cannot capture source revision')!
	// Exercise real fast success and failure through the same owned observer.
	// The explicit missing Git directory cannot inherit the caller's repository.
	refusal_code, refusal_text := invoke(['/usr/bin/git', '--git-dir=' + output + '/missing-git-dir',
		'rev-parse', '--verify', 'HEAD'], output + '/expected-git-refusal.log', roots)!
	require(refusal_code == 128 && refusal_text != '', 'expected missing-repository Git refusal')!
	receipt['observer_controls'] = 'Git revision exit 0 and explicit missing-repository Git exit 128'
	receipt['project_revision'] = revision.trim_space()
	receipt['driver_source_sha256'] = embedded
	receipt['v_executable'] = v; receipt['clang_executable'] = cc
	source := output + '/source'; pristine_ui := output + '/ui-source'
	ui := output + '/modules'; app := output + '/software'
	copy_inputs(root, source, paths)!; copy_inputs(modules, pristine_ui, ui_paths)!
	copy_inputs(pristine_ui, ui, ui_paths)!
	verify(source, paths, hashes)!; verify(pristine_ui, ui_paths, ui_hashes)!; verify(ui, ui_paths, ui_hashes)!
	// Match launcher-check.v: headless omits the platform backend and must
	// omit its native mounted-control helpers. Keep pristine and overlay pins.
	control := ui + '/ui2/ui/control_state.c.v'
	if os.is_file(control) {
		os.write_file(control, os.read_file(control)!.replace('$else $if macos {', '$else $if macos && !ui2_headless ? {')
			.replace('$else $if windows {', '$else $if windows && !ui2_headless ? {'))!
	}
	staged_ui := inventory(ui, ui_paths)!
	os.write_file(output + '/staged-ui-sources.json', json2.encode(staged_ui) + '\n')!
	os.mkdir(app)!
	for path in paths {
		if path.starts_with('desktop/software_') || (path.starts_with('tests/packages/software_') && path.ends_with('_fixture.v')) {
			name := if os.file_name(path) == 'software_fixture.v' { 'main.v' } else { os.file_name(path) }
			os.cp(source + '/' + path, app + '/' + name)!
		}
	}
	// The maintained fixture owns its production-safe focused entry point.
	require(os.read_file(app + '/main.v')!.contains("os.args[1] == 'launch-compact'"), 'fixture lacks launch-compact mode')!
	mut staged_paths := os.ls(app)!; staged_paths.sort()
	staged := inventory(app, staged_paths)!
	os.write_file(output + '/staged-sources.json', json2.encode(staged) + '\n')!
	verify(root, paths, hashes)!; verify(modules, ui_paths, ui_hashes)!
	for mode in ['normal', 'prod', 'sanitized']! {
		mut argv := [v, '-backend', 'c', '-keepc', '-nocache', '-no-skip-unused', '-cc', cc,
			'-gc', 'none', '-manualfree', '-enable-globals', '-d', 'ui2_headless',
			'-cflags', '-O1 -Wno-error=incompatible-pointer-types -I' + source + '/desktop',
			'-path', '@vlib|' + source + '|' + source + '/tools/accounts|' + ui + '|@vmodules']
		if mode == 'prod' { argv << '-prod' }
		if mode == 'sanitized' { argv << ['-d', 'no_segfault_handler', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined'] }
		argv << ['-o', output + '/' + mode, app]
		code, _ := invoke(argv, output + '/' + mode + '.build.log', roots)!
		require(code == 0, 'build failed; see ' + output + '/' + mode + '.build.log')!
		run_code, text := invoke([output + '/' + mode, 'launch-compact'], output + '/' + mode + '.run.log', roots)!
		require(run_code == 0, 'focused check failed; see ' + output + '/' + mode + '.run.log')!
		one_marker(text, focused_marker)!
		one_marker(text, entry_marker)!
		println('COMPACT LAUNCH ' + mode + ' build/check PASS')
	}
	// The historical fixture has assertion side effects and runs only normally.
	legacy_code, legacy := invoke([output + '/normal'], output + '/normal.historical.log', roots)!
	require(legacy_code == 0, 'historical normal Software fixture failed')!
	one_marker(legacy, 'Software UI: catalog, package/trust review, literal confirmation, revocation, URL paging, diagnostics and close guard passed')!
	one_marker(legacy, entry_marker)!
	require(project_sources(root)! == paths && ui_sources(modules) == ui_paths, 'source inventory changed')!
	verify(root, paths, hashes)!; verify(source, paths, hashes)!
	verify(modules, ui_paths, ui_hashes)!; verify(pristine_ui, ui_paths, ui_hashes)!; verify(ui, ui_paths, staged_ui)!
	mut final_staged_paths := os.ls(app)!; final_staged_paths.sort()
	require(final_staged_paths == staged_paths, 'staged source inventory changed')!
	verify(app, staged_paths, staged)!
	for path, hash in compiler_pins { require(digest(path)! == hash, 'executable changed: ' + path)! }
	receipt['focused_modes'] = 'normal, production, ASan/UBSan'
	receipt['supplementary_check'] = 'historical full Software fixture, normal build only'
	for name in ['sources.json', 'ui-sources.json', 'staged-ui-sources.json', 'staged-sources.json', 'executables.json']! {
		receipt[name + '_sha256'] = digest(output + '/' + name)!
	}
	mut final := Phase{roots: roots}
	sample(mut final)!
}

fn write_result(output string, mut receipt map[string]string) ! {
	mut artifacts := map[string]string{}
	for path in os.walk_ext(output, '') {
		if os.is_file(path) && path != output + '/result.json' && path != output + '/artifacts.json' {
			artifacts[path[output.len + 1..]] = digest(path)!
		}
	}
	os.write_file(output + '/artifacts.json', json2.encode(artifacts) + '\n')!
	receipt['artifact_inventory_sha256'] = digest(output + '/artifacts.json')!
	os.write_file(output + '/result.json', json2.encode(receipt) + '\n')!
}

// A refused tree can exceed the inventory bounds. Preserve it without walking
// or reading it again; the original complete sealer owns its later audit.
fn write_failure(output string, mut receipt map[string]string) ! {
	receipt.delete('artifact_inventory_sha256')
	receipt['artifact_inventory_status'] = 'not claimed after refusal; preserved state requires original full sealer'
	os.write_file(output + '/result.json', json2.encode(receipt) + '\n')!
}

fn main() {
	if os.args.len != 6 { eprintln('usage: software-compact-launch-check V_EXECUTABLE CLANG_EXECUTABLE UI_MODULE_DIRECTORY NEW_OUTPUT_DIRECTORY BOOTSTRAP_DIRECTORY'); exit(1) }
	root := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	bootstrap := os.args[5]
	if bootstrap != os.real_path(bootstrap) || !os.is_dir(bootstrap)
		|| bootstrap != os.real_path(os.dir(os.executable())) || bootstrap == root || bootstrap.starts_with(root + '/') {
		eprintln('provide the canonical external directory containing this owner'); exit(1)
	}
	requested := os.abs_path(os.args[4])
	if !os.is_dir(os.dir(requested)) { eprintln('output parent directory must exist'); exit(1) }
	output := os.join_path(os.real_path(os.dir(requested)), os.file_name(requested))
	if os.exists(output) || os.is_link(output) || output == root || output.starts_with(root + '/') {
		eprintln('provide a fresh external output directory'); exit(1)
	}
	if output == bootstrap || output.starts_with(bootstrap + '/') || bootstrap.starts_with(output + '/') {
		eprintln('output and bootstrap charge roots must be disjoint'); exit(1)
	}
	os.mkdir(output, mode: 0o700) or { eprintln(err); exit(1) }
	mut receipt := {
		'format': '1'
		'outcome': 'PASS'
		'output_directory': output
		'bootstrap_directory': bootstrap
		'state_limit_bytes': state_limit.str()
		'log_limit_bytes': log_limit.str()
		'source_binding': 'source inventories bind captured bytes including uncommitted edits; revision is provenance only'
		'scope': 'host headless compact Software launch controls; no guest rendering or wider section 14 qualification'
		'toolchain_limit': 'project/UI inputs and executable pins only; imported vlib/thirdparty, headers, linker and transitive tools are not frozen; not hermetic'
	}
	qualify(root, output, bootstrap, mut receipt) or {
		receipt['outcome'] = 'FAIL'; receipt['error'] = err.msg()
		write_failure(output, mut receipt) or { eprintln('cannot finish failure receipt: ' + err.msg()) }
		eprintln('COMPACT LAUNCH FAIL: ' + output + ': ' + err.msg()); exit(1)
	}
	write_result(output, mut receipt) or { eprintln(err); exit(1) }
	mut final := Phase{roots: [output, bootstrap]}
	sample(mut final) or {
		receipt['outcome'] = 'FAIL'; receipt['error'] = err.msg()
		write_failure(output, mut receipt) or { eprintln('cannot finish failure receipt: ' + err.msg()) }
		eprintln('COMPACT LAUNCH FAIL: ' + output + ': ' + err.msg()); exit(1)
	}
	println('COMPACT LAUNCH three focused host variants and historical normal PASS: ' + output)
}
