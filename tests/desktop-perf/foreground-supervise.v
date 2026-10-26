// SPDX-License-Identifier: GPL-2.0-or-later
// Foreground owner for the maintained x86 prepared performance adapter.
@[has_globals]
module main

import crypto.sha256
import json2
import os
import perfconsole
import perfreport
import perfrunner
import sourcecommand
import time

#include <errno.h>
#include <signal.h>
#include <unistd.h>
fn C.getpgid(i32) i32
fn C.getppid() i32
fn C.fork() i32

struct Profile {
	adapter string
	prepared_state string
	prepared_sha256 string
	directory string
	timeout_seconds int
	log_limit_bytes int
	charged_roots []string
	input_roots []string
}

struct PreparedView {
	root string
	arguments []string
	command []string
	inputs map[string]string
}

struct Inventory { mut: count int }

struct Watch {
	state string
	profile Profile
mut:
	pid int
	started u64
	next_budget u64
	reason string
	budgets []string
	stopped i32
	failed i32
	tasks []thread
}

__global active_watch = unsafe { &Watch(nil) }

fn require(ok bool, text string) ! { if !ok { return error(text) } }
fn never() bool { return false }
fn inside(path string, root string) bool { return path == root || path.starts_with(root + '/') }
fn hash_bounded(path string, deadline u64) !string {
	mut file := os.open(path)!; defer { file.close() }
	mut sum := sha256.new(); defer { unsafe { sum.free() } }
	mut buffer := []u8{len: 1024 * 1024}; defer { unsafe { buffer.free() } }
	for {
		if time.sys_mono_now() > deadline { return error('file digest deadline') }
		n := file.read(mut buffer) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }; sum.write(buffer[..n])!
	}
	return sum.sum([]u8{}).hex()
}
fn hash(path string) !string { return hash_bounded(path, time.sys_mono_now() + 120 * u64(time.second)) }

fn command(argv []string) !string {
	result := sourcecommand.capture(argv, os.environ(), 3, 1024 * 1024, never)!
	if result.status != 0 { return error('observation failed: ' + argv.str() + result.stderr) }
	return result.stdout
}

fn number(text string) !i64 {
	if text == '' || text.len > 15 || !text.bytes().all(it >= `0` && it <= `9`) { return error('invalid size') }
	return text.i64()
}

fn budget(profile Profile, state string, admission bool) !string {
	df := command(['/bin/df', '-k', os.dir(state)])!
	rows := df.trim_space().split_into_lines()
	if rows.len != 2 || rows[1].fields().len < 4 { return error('unexpected df output') }
	minimum := if admission { i64(2097152) } else { i64(1048576) }
	if number(rows[1].fields()[3])! < minimum { return error('actual df below required floor') }
	mut roots := profile.charged_roots.clone()
	if os.exists(state) && !roots.any(inside(state, it)) { roots << state }
	mut usage := ''
	mut total := i64(0)
	if roots.len > 0 {
		usage = command(['/usr/bin/du', '-sk', ...roots])!
		for line in usage.trim_space().split_into_lines() {
			fields := line.fields()
			if fields.len < 2 { return error('unexpected du output') }
			total += number(fields[0])!
		}
	}
	if total > 524288 { return error('512 MiB charged-root budget exceeded') }
	return df + '\n' + usage
}

fn inventory(path string, ancestors []string, deadline u64, mut context Inventory, mut values map[string]string) ! {
	context.count++
	if context.count > 250000 || time.sys_mono_now() > deadline { return error('input inventory entry/deadline limit') }
	if ancestors.len > 128 { return error('input nesting limit') }
	info := os.lstat(path)!
	values['mode:' + path] = info.mode.str()
	if info.get_filetype() == .regular { values[path] = hash_bounded(path, deadline)!; return }
	if info.get_filetype() == .symbolic_link {
		values['link:' + path] = os.readlink(path)!
		resolved := os.real_path(path)
		if resolved == '' || resolved == path || resolved in ancestors { return error('dangling/cyclic input') }
		values['resolved:' + path] = resolved
		inventory(resolved, ancestors, deadline, mut context, mut values)!
		return
	}
	if info.get_filetype() != .directory { return error('special input: ' + path) }
	resolved := os.real_path(path)
	if resolved in ancestors { return error('cyclic directory') }
	mut next := ancestors.clone(); next << resolved
	mut names := os.ls(path)!; names.sort()
	for name in names { inventory(path + '/' + name, next, deadline, mut context, mut values)! }
}

fn inputs(paths []string) !map[string]string {
	mut result := map[string]string{}
	mut context := Inventory{}
	deadline := time.sys_mono_now() + 120 * u64(time.second)
	for path in paths { inventory(path, [], deadline, mut context, mut result)! }
	return result
}

fn group_absent(pid int) ! {
	require(pid > 1 && pid != C.getpgid(0), 'invalid child group')!
	deadline := time.sys_mono_now() + 5 * u64(time.second)
	for {
		if C.kill(-pid, 0) == -1 {
			if C.errno == C.ESRCH { return }
			if C.errno != C.EPERM { return os.error_posix() }
		}
		if time.sys_mono_now() > deadline { return error('child group remains after owner retirement') }
		time.sleep(10 * time.millisecond)
	}
}

fn no_children() !string {
	mut raw := i32(0)
	result := C.waitpid(-1, &raw, C.WNOHANG); saved := C.errno
	if result != -1 || saved != C.ECHILD { return error('waitable child remains: ' + result.str()) }
	return 'waitpid(-1,WNOHANG)=-1;errno=ECHILD'
}

fn budget_watch(mut watch Watch) {
	for unsafe { C.__atomic_load_n(&watch.stopped, C.__ATOMIC_RELAXED) } == 0 {
		if time.sys_mono_now() >= watch.next_budget {
			observation := budget(watch.profile, watch.state, false) or {
				watch.reason = err.msg()
				unsafe { C.__atomic_store_n(&watch.failed, 1, C.__ATOMIC_RELEASE) }
				return
			}
			watch.budgets << observation
			os.write_file(watch.state + '/budgets.json', json2.encode(watch.budgets) + '\n') or {
				watch.reason = err.msg()
				unsafe { C.__atomic_store_n(&watch.failed, 1, C.__ATOMIC_RELEASE) }
				return
			}
			watch.next_budget = time.sys_mono_now() + 5 * u64(time.second)
		}
		time.sleep(20 * time.millisecond)
	}
}

fn cancel() bool {
	return perfconsole.cancelled() || unsafe { C.__atomic_load_n(&active_watch.failed, C.__ATOMIC_ACQUIRE) } != 0
}

fn log_chunk(chunk string, context voidptr) ! {
	watch := unsafe { &Watch(context) }
	mut log := os.open_append(watch.state + '/command.log')!; defer { log.close() }
	log.write_string(chunk)!
}

fn observe(pid int, context voidptr) ! {
	mut watch := unsafe { &Watch(context) }
	watch.pid = pid
	watch.started = time.sys_mono_now()
	watch.next_budget = watch.started
	os.write_file(watch.state + '/child.json', json2.encode({'pid': pid.str(), 'ownership': 'SDK private process group; leader reserved with WNOWAIT until retirement'}) + '\n')!
	watch.tasks << spawn budget_watch(mut watch)
}

fn supervise(profile Profile, state string, argv []string) !int {
	guard := perfconsole.own_commands(); defer { guard.close() }
	mut watch := Watch{state: state, profile: profile}
	active_watch = &watch
	defer { active_watch = unsafe { nil } }
	os.write_file(state + '/argv.json', json2.encode(argv) + '\n')!
	os.write_file(state + '/environment.json', json2.encode(os.environ()) + '\n')!
	os.write_file(state + '/command.log', '')!
	mut failure := ''
	output := sourcecommand.capture_combined_owned(argv, os.environ(), f64(profile.timeout_seconds),
		profile.log_limit_bytes, cancel, log_chunk, observe, &watch, 30, profile.directory) or {
		failure = err.msg()
		sourcecommand.Output{}
	}
	unsafe { C.__atomic_store_n(&watch.stopped, 1, C.__ATOMIC_RELAXED) }
	for task in watch.tasks { task.wait() }
	if watch.reason != '' { failure = watch.reason }
	mut receipt := {
		'failure': failure
		'reason': watch.reason
		'owner_status': if failure == '' { output.status.str() } else { 'unavailable after observer refusal' }
		'elapsed_ns': (time.sys_mono_now() - watch.started).str()
		'pid': watch.pid.str()
		'cleanup': 'pending'
	}
	os.write_file(state + '/supervisor.json', json2.encode(receipt) + '\n')!
	if watch.pid > 1 { group_absent(watch.pid)! }
	receipt['cleanup'] = no_children()!
	os.write_file(state + '/supervisor.json', json2.encode(receipt) + '\n')!
	if failure != '' { return error(failure) }
	return output.status
}

fn fresh(state string) ! {
	require(state.starts_with('/') && os.real_path(os.dir(state)) == os.dir(state)
		&& !os.exists(state) && !os.is_link(state), 'fresh canonical external state required')!
}

fn validated(profile Profile, state string) !PreparedView {
	require(profile.adapter.starts_with('/') && os.is_file(profile.adapter), 'absolute adapter required')!
	require(profile.prepared_state == os.real_path(profile.prepared_state) && os.is_dir(profile.prepared_state), 'canonical prepared state required')!
	require(profile.directory == os.real_path(profile.directory) && os.is_dir(profile.directory), 'canonical working directory required')!
	require(profile.timeout_seconds >= 1800 && profile.timeout_seconds <= 7200, 'outer deadline must be 1800..7200 seconds')!
	require(profile.log_limit_bytes > 0 && profile.log_limit_bytes <= 32 * 1024 * 1024, 'log limit must be 1..32 MiB')!
	require(profile.input_roots.len > 0 && profile.charged_roots.len > 0, 'declared input and charged roots required')!
	for index, root in profile.charged_roots {
		require(root == os.real_path(root) && os.is_dir(root), 'canonical charged root required')!
		for other in profile.charged_roots[..index] { require(!inside(root, other) && !inside(other, root), 'overlapping charged roots')! }
	}
	require(profile.charged_roots.any(inside(profile.prepared_state, it)), 'prepared runtime must be covered by a charged root')!
	for root in profile.input_roots {
		require(root.starts_with('/') && (os.exists(root) || os.is_link(root)) && !inside(state, os.real_path(root)), 'input root missing or contains output state')!
	}
	receipt := profile.prepared_state + '/prepared.json'
	require(hash(receipt)! == profile.prepared_sha256, 'prepared receipt digest mismatch')!
	p := json2.decode[PreparedView](os.read_file(receipt)!)!
	require(!inside(state, p.root) && !inside(state, profile.prepared_state), 'supervisor state must be external to source and prepared state')!
	require(p.inputs[profile.adapter] == hash(profile.adapter)!, 'adapter must match prepared input pin')!
	plan := perfrunner.parse(p.arguments, p.root, p.root + '/tests/desktop-perf', '')!
	require(plan.scenarios.len == 6 && ['ops', 'churn', 'cache', 'idle', 'apps', 'drag'].all(it in plan.scenarios), 'all six performance scenarios required')!
	require(plan.timeout + 60 <= profile.timeout_seconds, 'outer deadline must include adapter timeout and 60 seconds cleanup')!
	require(p.command.len > 0 && p.command[0].starts_with('/'), 'absolute prepared QEMU required')!
	mut mux := false
	for index in 0 .. p.command.len - 1 { if p.command[index] == '-serial' && p.command[index + 1] == 'mon:stdio' { mux = true } }
	require(mux, 'prepared QEMU requires foreground serial monitor')!
	require(!os.exists(profile.prepared_state + '/results'), 'prepared adapter already executed')!
	require(!os.exists(profile.prepared_state + '/after-inputs.json'), 'stale adapter input receipt exists')!
	return p
}

fn completed(profile Profile, p PreparedView) ! {
	require(os.read_file(profile.prepared_state + '/results/status')! == '0\n', 'adapter completion receipt missing')!
	after := json2.decode[map[string]string](os.read_file(profile.prepared_state + '/after-inputs.json')!)!
	mut expected := p.inputs.clone()
	disk := profile.prepared_state + '/root.ext2'
	require(disk in expected, 'prepared mutable disk pin missing')!
	expected[disk] = hash(disk)!
	require(after == expected, 'adapter input verification receipt differs')!
	serial := os.read_file(profile.prepared_state + '/results/serial.log')!
	require(serial.split_into_lines().any(it.trim_space() == perfreport.done), 'guest completion marker missing')!
}

fn run(state string, profile_path string) !int {
	fresh(state)!
	profile_text := os.read_file(profile_path)!
	profile := json2.decode[Profile](profile_text)!
	p := validated(profile, state)!
	admission := budget(profile, state, true)!
	os.mkdir(state)!
	os.write_file(state + '/budget-before.log', admission)!
	os.write_file(state + '/profile.json', profile_text)!
	mut paths := profile.input_roots.clone()
	paths << [profile_path, profile.adapter, profile.prepared_state + '/prepared.json', p.command[0], os.executable(), @FILE]
	for path, _ in p.inputs { if path != profile.prepared_state + '/root.ext2' { paths << path } }
	before := inputs(paths)!
	require(before[profile_path] == sha256.sum(profile_text.bytes()).hex(), 'profile changed before inventory')!
	os.write_file(state + '/inputs-before.json', json2.encode(before) + '\n')!
	status := supervise(profile, state, [profile.adapter, 'run', profile.prepared_state, profile.prepared_sha256]) or {
		after := inputs(paths) or { map[string]string{} }
		os.write_file(state + '/inputs-after.json', json2.encode(after) + '\n')!
		return err
	}
	after := inputs(paths)!
	os.write_file(state + '/inputs-after.json', json2.encode(after) + '\n')!
	require(before == after, 'declared input identity changed')!
	os.write_file(state + '/budget-after.log', budget(profile, state, false)!)!
	require(status == 0, 'adapter exited ' + status.str())!
	completed(profile, p)!
	os.write_file(state + '/result.json', json2.encode({
		'verdict': 'PASS'
		'prepared_sha256': profile.prepared_sha256
		'inputs_sha256': hash(state + '/inputs-before.json')!
		'scope': 'maintained x86 prepared adapter; its own successful shutdown and input verification receipts required; no arbitrary escaped-descendant guarantee'
	}) + '\n')!
	println('PERF FOREGROUND PASS ' + hash(state + '/result.json')!)
	return 0
}

fn fixture(kind string) {
	match kind {
		'ok' { println('fixture complete') }
		'nonzero' { eprintln('fixture refused'); exit(23) }
		'timeout' { for { time.sleep(10 * time.millisecond) } }
		'output' { for { println('x'.repeat(8192)); time.sleep(1 * time.millisecond) } }
		'signal' { C.kill(C.getppid(), C.SIGTERM); for { time.sleep(10 * time.millisecond) } }
		'descendant' {
			child := C.fork()
			if child < 0 { exit(24) }
			if child == 0 { for { time.sleep(10 * time.millisecond) } }
			println('same-group descendant ' + child.str())
		}
		else { exit(25) }
	}
}

fn fake_profile(profile Profile, prepared PreparedView) !Profile {
	path := profile.prepared_state + '/prepared.json'
	os.write_file(path, json2.encode(prepared) + '\n')!
	return Profile{...profile, prepared_sha256: hash(path)!}
}

fn refuses(profile Profile, state string, expected string) ! {
	validated(profile, state) or { require(err.msg().contains(expected), 'different profile refusal: ' + err.msg())!; return }
	return error('profile control accepted: ' + expected)
}

fn completion_refuses(profile Profile, p PreparedView, expected string) ! {
	completed(profile, p) or { require(err.msg().contains(expected), 'different completion refusal: ' + err.msg())!; return }
	return error('completion control accepted: ' + expected)
}

fn profile_controls(state string) !string {
	root := state + '/fake-source'; prepared := state + '/fake-prepared'; output := state + '/fake-output'
	os.mkdir(root)!; os.mkdir(prepared)!
	os.write_file(prepared + '/root.ext2', 'fixture disk')!
	p := PreparedView{
		root: root
		arguments: ['fixture=' + os.executable(), '--scenarios=ops,churn,cache,idle,apps,drag', '--timeout=1800']
		command: [os.executable(), '-serial', 'mon:stdio']
		inputs: {os.executable(): hash(os.executable())!, prepared + '/root.ext2': hash(prepared + '/root.ext2')!}
	}
	base := Profile{adapter: os.executable(), prepared_state: prepared, directory: root, timeout_seconds: 1860,
		log_limit_bytes: 65536, charged_roots: [prepared], input_roots: [root]}
	valid := fake_profile(base, p)!
	validated(valid, output)!
	missing := PreparedView{...p, arguments: ['fixture=' + os.executable(), '--scenarios=ops,churn,cache,idle,apps', '--timeout=1800']}
	refuses(fake_profile(base, missing)!, output, 'six performance scenarios')!
	plain := PreparedView{...p, command: [os.executable(), '-serial', 'stdio']}
	refuses(fake_profile(base, plain)!, output, 'foreground serial monitor')!
	mut pins := p.inputs.clone(); pins[os.executable()] = 'wrong'
	refuses(fake_profile(base, PreparedView{...p, inputs: pins})!, output, 'prepared input pin')!
	restored := fake_profile(base, p)!
	refuses(Profile{...restored, charged_roots: [root]}, output, 'covered by a charged root')!
	os.write_file(prepared + '/after-inputs.json', '{}')!
	refuses(restored, output, 'stale adapter input receipt')!
	os.mkdir(prepared + '/results')!
	os.write_file(prepared + '/results/status', '0\n')!
	os.write_file(prepared + '/results/serial.log', perfreport.done + '\n')!
	completion_refuses(restored, p, 'input verification receipt differs')!
	os.write_file(prepared + '/after-inputs.json', json2.encode(p.inputs) + '\n')!
	completed(restored, p)!
	os.write_file(prepared + '/results/serial.log', 'almost ' + perfreport.done + '\n')!
	completion_refuses(restored, p, 'completion marker missing')!
	os.write_file(prepared + '/results/status', '23\n')!
	completion_refuses(restored, p, 'completion receipt missing')!
	return 'PASS ten profile/completion controls; fake prepared documents only; no adapter or QEMU execution'
}

fn selfcheck(state string, compiler string) ! {
	fresh(state)!
	require(compiler.starts_with('/') && os.is_file(compiler), 'absolute complete V executable required')!
	mut profile := Profile{directory: os.real_path(os.dir(state)), timeout_seconds: 2, log_limit_bytes: 65536}
	admission := budget(profile, state, true)!
	os.mkdir(state)!
	profile = Profile{...profile, charged_roots: [state]}
	os.write_file(state + '/budget-before.log', admission)!
	root := os.real_path(@DIR + '/../..')
	paths := [os.executable(), os.dir(compiler), root + '/tools', root + '/tests/desktop-perf', root + '/tests/hardware-platform/hwhost']
	before := inputs(paths)!
	os.write_file(state + '/inputs-before.json', json2.encode(before) + '\n')!
	for directory in ['tools', 'tests/desktop-perf', 'tests/hardware-platform/hwhost'] {
		os.mkdir_all(os.dir(state + '/source/' + directory))!
		os.cp_all(root + '/' + directory, state + '/source/' + directory, false)!
	}
	mut checks := map[string]string{}
	checks['profile_controls'] = profile_controls(state)!
	for kind in ['ok', 'nonzero', 'timeout', 'output', 'signal', 'descendant'] {
		work := state + '/' + kind; os.mkdir(work)!
		started := time.sys_mono_now()
		mut refused := ''
		status := supervise(profile, work, [os.executable(), '--fixture', kind]) or { refused = err.msg(); -1 }
		checks[kind] = 'status=' + status.str() + ';refusal=' + refused
		os.write_file(state + '/controls.json', json2.encode(checks) + '\n')!
		expected := match kind { 'timeout', 'descendant' { 'command timed out' } 'output' { 'command output exceeds limit' } 'signal' { 'command interrupted' } else { '' } }
		require(refused == expected, kind + ' refusal differs: ' + refused)!
		if expected == '' { require(status == if kind == 'nonzero' { 23 } else { 0 }, kind + ' status differs')! }
		require(time.sys_mono_now() - started < 10 * u64(time.second), kind + ' cleanup exceeded wall bound')!
		require(os.file_size(work + '/command.log') <= u64(profile.log_limit_bytes), kind + ' retained output exceeds hard limit')!
		if kind == 'nonzero' { require(os.read_file(work + '/command.log')! == 'fixture refused\n', 'combined pipe lost stderr')! }
		os.write_file(work + '/budget-after.log', budget(profile, state, false)!)!
	}
	checks['scope'] = 'host fixtures exercise actual SDK spawn, observer, TERM grace, group retirement and sole i32 reap; no guest executed'
	after := inputs(paths)!
	os.write_file(state + '/inputs-after.json', json2.encode(after) + '\n')!
	require(before == after, 'host control input identity changed')!
	checks['inputs_sha256'] = hash(state + '/inputs-before.json')!
	checks['verdict'] = 'PASS six process controls and ten profile/completion controls'
	os.write_file(state + '/qualification.json', json2.encode(checks) + '\n')!
	println('PERF FOREGROUND HOST PASS ' + hash(state + '/qualification.json')!)
}

fn qualify(state string, compiler string) ! {
	fresh(state)!
	require(compiler == os.real_path(compiler) && os.is_file(compiler), 'canonical complete V executable required')!
	root := os.real_path(@DIR + '/../..')
	require(!inside(state, root) && !inside(root, state), 'qualifier state must be external to source')!
	mut profile := Profile{directory: root, timeout_seconds: 120, log_limit_bytes: 4 * 1024 * 1024, charged_roots: [root]}
	admission := budget(profile, state, true)!
	os.mkdir(state)!
	profile = Profile{...profile, charged_roots: [root, state]}
	os.write_file(state + '/budget-before.log', admission)!
	os.cp(os.executable(), state + '/bootstrap')!
	for name in ['tmp', 'modules', 'cache'] { os.mkdir(state + '/' + name)! }
	for key, _ in os.environ() { if key !in ['HOME', 'USER', 'LOGNAME'] { os.unsetenv(key) } }
	for key, value in {
		'PATH': '/usr/bin:/bin:/usr/sbin:/sbin'
		'DEVELOPER_DIR': '/Library/Developer/CommandLineTools'
		'V': compiler
		'VEXE': compiler
		'V_MACOS_V3_CALLER_VEXE': compiler
		'V_MACOS_V3_CALLER_VEXE_PRESENT': '1'
		'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0'
		'V_MACOS_V3_NO_FALLBACK': '1'
		'V_MACOS_V3_CALLER_NO_FALLBACK': '1'
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1'
		'VTMP': state + '/tmp'
		'TMPDIR': state + '/tmp'
		'VMODULES': state + '/modules'
		'V3CACHE': state + '/cache'
		'XDG_CACHE_HOME': state + '/cache'
	} { os.setenv(key, value, true) }
	clang := command(['/usr/bin/xcrun', '--find', 'clang'])!.trim_space()
	resource := command([clang, '-print-resource-dir'])!.trim_space()
	sdk := command(['/usr/bin/xcrun', '--show-sdk-path'])!.trim_space()
	os.setenv('SDKROOT', sdk, true)
	paths := [os.dir(compiler), root + '/tools', root + '/tests/desktop-perf', root + '/tests/hardware-platform/hwhost',
		os.executable(), clang, '/Library/Developer/CommandLineTools/usr/bin/ld', resource + '/include',
		sdk + '/SDKSettings.json', sdk + '/SDKSettings.plist', '/usr/bin/xcrun', '/bin/df', '/usr/bin/du']
	before := inputs(paths)!
	os.write_file(state + '/inputs-before.json', json2.encode(before) + '\n')!
	mut results := map[string]string{}
	for kind in ['normal', 'production'] {
		work := state + '/' + kind; os.mkdir(work)!
		build := work + '/build'; os.mkdir(build)!
		mut argv := [compiler, '-enable-globals', '-nocache', '-keepc', '-cc', clang, '-path',
			'@vlib|@vmodules|' + root + '/tools|' + root + '/tests/desktop-perf|' + root + '/tests/hardware-platform|' + root + '/tests/linuxkpi',
			'-o', work + '/foreground-supervise']
		if kind == 'production' { argv << '-prod' }
		argv << root + '/tests/desktop-perf/foreground-supervise.v'
		require(supervise(profile, build, argv)! == 0, kind + ' compile failed')!
		control := work + '/driver'; os.mkdir(control)!
		control_argv := [work + '/foreground-supervise', 'selfcheck', work + '/controls', compiler]
		require(supervise(profile, control, control_argv)! == 0, kind + ' controls failed')!
		results[kind + ':binary_sha256'] = hash(work + '/foreground-supervise')!
		results[kind + ':qualification_sha256'] = hash(work + '/controls/qualification.json')!
		os.write_file(state + '/progress.json', json2.encode(results) + '\n')!
	}
	after := inputs(paths)!
	os.write_file(state + '/inputs-after.json', json2.encode(after) + '\n')!
	require(before == after, 'build/control input identity changed')!
	os.write_file(state + '/budget-after.log', budget(profile, state, false)!)!
	results['inputs_sha256'] = hash(state + '/inputs-before.json')!
	results['verdict'] = 'PASS normal and production; sixteen controls each; no guest execution'
	results['scope'] = 'selected complete compiler, maintained sources and recorded host compiler/SDK metadata; installed loader and SDK dependency closure is not hermetic'
	os.write_file(state + '/qualification.json', json2.encode(results) + '\n')!
	println('PERF FOREGROUND QUALIFIED ' + hash(state + '/qualification.json')!)
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--fixture' { fixture(os.args[2]); return }
	if os.args.len == 4 && os.args[1] == 'selfcheck' {
		selfcheck(os.args[2], os.args[3]) or { eprintln(err); exit(1) }; return
	}
	if os.args.len == 4 && os.args[1] == 'qualify' {
		qualify(os.args[2], os.args[3]) or { eprintln(err); exit(1) }; return
	}
	if os.args.len == 4 && os.args[1] == 'run' {
		status := run(os.args[2], os.args[3]) or {
			if os.is_dir(os.args[2]) { os.write_file(os.args[2] + '/failure.txt', err.msg() + '\n') or {} }
			eprintln(err); exit(1)
		}; exit(status)
	}
	eprintln('usage: foreground-supervise run NEW-STATE PROFILE.json\n       foreground-supervise selfcheck|qualify NEW-STATE COMPLETE-V')
	exit(2)
}
