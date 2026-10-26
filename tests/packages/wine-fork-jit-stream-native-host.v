// SPDX-License-Identifier: GPL-2.0-or-later
// Host-only build/control receipt. It never invokes the target controller.
module main

import crypto.sha256
import json2
import os
import time
import tools.packages.winejitstream

#include <unistd.h>
#include <signal.h>
#include <sys/wait.h>
#include <sys/resource.h>
#include <fcntl.h>
#define wine_native_host_rlimit rlimit
#define wine_native_host_setrlimit setrlimit

fn C.fork() int
fn C.setpgid(int, int) int
fn C.execv(&char, &&char) int
fn C.waitpid(int, &int, int) int
fn C.kill(int, int) int
fn C._exit(int)

struct C.wine_native_host_rlimit {
	rlim_cur u64
	rlim_max u64
}

fn C.wine_native_host_setrlimit(int, &C.wine_native_host_rlimit) int

const clang = '/opt/homebrew/opt/llvm/bin/clang'

struct Pin {
	digest    string
	canonical string
	link      string
}

struct Step {
	argv       []string
	df         string
	run        winejitstream.NativeRun
	output_pin string
}

struct Cooperative {
	argv             []string
	df               string
	leader_pid       int
	wait_status      int
	duration_ms      u64
	overrun          bool
	forwarded_signal int
	injected_signal  bool
	reason           string
}

fn pin(path string) !Pin {
	return Pin{
		digest:    sha256.sum(os.read_bytes(path)!).hex()
		canonical: os.real_path(path)
		link:      if os.is_link(path) {
			os.readlink(path)!
		} else {
			''
		}
	}
}

fn tree(path string, mut pins map[string]Pin) ! {
	for name in os.ls(path)! {
		entry := path + '/' + name
		if os.is_dir(entry) && !os.is_link(entry) {
			tree(entry, mut pins)!
		} else if os.is_file(entry) {
			pins[entry] = pin(entry)!
		} else {
			return error('unsupported input')
		}
	}
}

fn checked_df(state string) !string {
	mut child := os.new_process('/bin/df')
	defer { child.close() }
	child.set_args(['-k', state])
	child.set_redirect_stdio_merged()
	child.run()
	child.wait()
	text := child.stdout_slurp()
	if child.code != 0 { return error('df failed') }
	lines := text.trim_space().split_into_lines()
	if lines.len != 2 { return error('df format') }
	fields := lines[1].fields()
	if fields.len < 4 || fields[3].u64() < 550 * 1024 { return error('df floor') }
	return text
}

fn main() {
	if os.args.len > 1 && os.args[1].starts_with('--policy') {
		policy_observe() or { eprintln(err); exit(1) }
		return
	}
	observe() or {
		eprintln(err)
		exit(1)
	}
}

// Fixed small policy qualification. Never invokes the target controller.
const policy_base = '/Users/alex/Library/Caches/vinix-codex/section14'
const policy_compiler = '/Users/alex/code/vinix/build/package-https-runtime-work/toolchain/v'
const policy_compiler_sha = 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
const policy_limit = u64(64 * 1024 * 1024)

struct PolicyBinding {
	entries int
	digest string
}

fn policy_binding(pins map[string]winejitstream.NativePin) PolicyBinding {
	mut keys := pins.keys()
	keys.sort()
	mut hash := sha256.new()
	for key in keys { hash.write((json2.encode(key) + ':' + json2.encode(pins[key]) + '\n').bytes()) or { panic(err) } }
	mut sum := []u8{len: sha256.size}
	hash.checksum_into(mut sum)
	return PolicyBinding{entries: keys.len, digest: sum.hex()}
}

fn policy_inputs(root string) !map[string]winejitstream.NativePin {
	mut pins := map[string]winejitstream.NativePin{}
	for path in [policy_compiler, os.dir(policy_compiler) + '/v.mod',
		os.dir(policy_compiler) + '/snapshot.json', clang, os.executable(),
		root + '/tests/packages/wine-fork-jit-stream-native.v',
		root + '/tests/packages/wine-fork-jit-stream-native-host.v'] {
		winejitstream.native_input_add(path, mut pins)!
	}
	for path in [os.dir(policy_compiler) + '/vlib', os.dir(policy_compiler) + '/thirdparty',
		root + '/tools/packages/winejitstream', root + '/tests/hardware-platform/hwhost'] {
		winejitstream.native_input_tree(path, mut pins)!
	}
	return pins
}

fn policy_account(state string, reserve u64) !u64 {
	mut historical := u64(0)
	for name in ['wine-jit-stream-native-host-01', 'wine-jit-stream-native-host-02',
		'wine-jit-stream-native-host-03', 'wine-jit-stream-native-host-04', 'wine-jit-stream-native-host-05',
		'wine-jit-stream-native-arm-01.launch-refusal.json', 'wine-jit-stream-native-arm-01.launch-02.json'] {
		historical += winejitstream.static_state_bytes(policy_base + '/' + name)!
	}
	if historical != 7638328 { return error('historical selected evidence changed') }
	current := winejitstream.static_state_bytes(state)!
	if current > 20 * 1024 * 1024 { return error('current policy host state exceeds 20 MiB') }
	selected := winejitstream.static_host_states_bytes(policy_base)!
		+ winejitstream.static_state_bytes(policy_base + '/wine-jit-stream-native-inputs-01')!
		+ winejitstream.static_state_bytes(policy_base + '/wine-jit-stream-native-host-06')!
		+ current
	return policy_budget(historical + selected, reserve)
}

fn policy_budget(selected u64, reserve u64) !u64 {
	if selected > policy_limit || reserve > policy_limit - selected {
		return error('host policy would exceed cumulative 64 MiB')
	}
	return selected + reserve
}

fn policy_observe() ! {
	bootstrap := os.args.len == 7 && os.args[1] == '--policy-bootstrap-record'
	if !bootstrap && (os.args.len != 4 || os.args[1] != '--policy') {
		return error('usage: native-host --policy ROOT EXISTING_HOST_07_STATE')
	}
	root := os.real_path(os.args[2])
	state := os.args[3]
	if state != policy_base + '/wine-jit-stream-native-host-07'
		|| os.real_path(state) != state || (os.lstat(state)!).get_filetype() != .directory {
		return error('requires fixed ordinary host-07 state')
	}
	if os.read_file(@FILE)! != $embed_file('wine-fork-jit-stream-native-host.v').to_string() {
		return error('compiled policy observer source differs')
	}
	if os.read_file(root + '/tools/packages/winejitstream/native_policy.v')!
		!= $embed_file('../../tools/packages/winejitstream/native_policy.v').to_string() {
		return error('compiled native compiler policy source differs')
	}
	if winejitstream.native_input_digest(policy_compiler)! != policy_compiler_sha {
		return error('selected private compiler changed')
	}
	winejitstream.native_require_free(state, winejitstream.native_free_floor(true))!
	policy_account(state, 2 * 1024 * 1024)!
	if bootstrap {
		policy_bootstrap(root, state)!
		return
	}
	policy_qualify(root, state)!
}

fn policy_bootstrap(root string, state string) ! {
	if os.args[4] != 'bootstrap-02.log' || os.executable() != state + '/host-02' {
		return error('requires fixed second bootstrap log and executable')
	}
	winejitstream.static_require_absent(state + '/bootstrap-02.json')!
	mut environment := map[string]string{}
	for name in ['V', 'VEXE', 'VINIX_V_COMPILER', 'V_MACOS_V3_CALLER_VEXE',
		'V_MACOS_V3_CALLER_VEXE_PRESENT', 'V_MACOS_V3_CALLER_VCHILD_PRESENT',
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT', 'V_MACOS_V3_NO_FALLBACK',
		'V_C_ERROR_BUG_REPORT_DISABLED', 'TMPDIR', 'VTMP', 'LC_ALL', 'LANG', 'VFLAGS',
		'VCHILD', 'V_MACOS_V3_CALLER_VCHILD', 'V_MACOS_V3_CALLER_NO_FALLBACK',
		'V_MACOS_V3_CHILD_VEXE_PRESENT', 'CFLAGS', 'LDFLAGS', 'VTEST_ONLY_FN', 'V3CACHE',
		'CPATH', 'C_INCLUDE_PATH', 'CPLUS_INCLUDE_PATH', 'OBJC_INCLUDE_PATH',
		'OBJCPLUS_INCLUDE_PATH', 'LIBRARY_PATH', 'COMPILER_PATH', 'GCC_EXEC_PREFIX',
		'CCC_OVERRIDE_OPTIONS', 'CLANG_CONFIG_FILE_SYSTEM_DIR', 'CLANG_CONFIG_FILE_USER_DIR',
		'SDKROOT', 'MACOSX_DEPLOYMENT_TARGET'] {
		environment[name] = os.getenv_opt(name) or { '<unset>' }
	}
	os.write_file(state + '/bootstrap-02.json', json2.encode({
		'kind': 'Posthoc completed external tool observation; bootstrap outside its own guard, observed with 300-second stop policy.'
		'exit_code': os.args[5]
		'observed_elapsed_ms': os.args[6]
		'argv': json2.encode([policy_compiler, '-nocache', '-cc', clang, '-prod', '-gc', 'none', '-manualfree',
			'-path', '@vlib|' + root + '|@vmodules', '-o', state + '/host-02',
			root + '/tests/packages/wine-fork-jit-stream-native-host.v'])
		'environment': json2.encode(environment)
		'log_sha256': winejitstream.native_input_digest(state + '/bootstrap-02.log')!
		'observer_sha256': winejitstream.native_input_digest(os.executable())!
		'selected_binding_after': json2.encode(policy_binding(policy_inputs(root)!))
	}))!
	policy_account(state, 2 * 1024 * 1024)!
}

fn policy_qualify(root string, state string) ! {
	for name in ['guarded', 'scratch', 'steps.json', 'environment.json', 'policy-receipt.json'] {
		winejitstream.static_require_absent(state + '/' + name)!
	}
	os.mkdir(state + '/guarded')!
	os.mkdir(state + '/scratch')!
	mut environment := winejitstream.native_clear_compiler_environment()
	for pair in ['V=' + policy_compiler, 'VEXE=' + policy_compiler,
		'VINIX_V_COMPILER=' + policy_compiler, 'V_MACOS_V3_CALLER_VEXE=' + policy_compiler,
		'V_MACOS_V3_CALLER_VEXE_PRESENT=1', 'V_MACOS_V3_CALLER_VCHILD_PRESENT=0',
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT=0', 'V_MACOS_V3_NO_FALLBACK=1',
		'V_C_ERROR_BUG_REPORT_DISABLED=1', 'TMPDIR=' + state + '/scratch',
		'VTMP=' + state + '/scratch', 'LC_ALL=C', 'LANG=C'] {
		at := pair.index('=') or { return error('invalid fixed policy environment') }
		os.setenv(pair[..at], pair[at + 1..], true)
		environment[pair[..at]] = pair[at + 1..]
	}
	for name in ['VCHILD', 'V_MACOS_V3_CALLER_VCHILD', 'V_MACOS_V3_CALLER_NO_FALLBACK',
		'V_MACOS_V3_CHILD_VEXE_PRESENT', 'VINIX_WINE_POLICY_ASSERT_SENTINEL'] {
		os.unsetenv(name)
		environment[name] = '<unset>'
	}
	os.write_file(state + '/environment.json', json2.encode(environment))!
	before := policy_inputs(root)!
	os.write_file(state + '/binding-before.json', json2.encode(policy_binding(before)))!
	limits := winejitstream.NativeLimits{timeout_ms: 60000, file_bytes: 20 * 1024 * 1024,
		total_bytes: 20 * 1024 * 1024, log_bytes: 256 * 1024, serial_bytes: 256 * 1024,
		min_free_kib: winejitstream.native_free_floor(false)}
	mut steps := map[string]Step{}
	for name in ['controller', 'policy-test', 'policy-test-prod'] {
		controller := name == 'controller'
		source := if controller { root + '/tests/packages/wine-fork-jit-stream-native.v' }
			else { root + '/tools/packages/winejitstream/native_policy_test.v' }
		mut argv := [policy_compiler, '-nocache', '-cc', clang]
		if name != 'policy-test' { argv << '-prod' }
		argv << ['-gc', 'none', '-manualfree', '-path', '@vlib|' + root
			+ if controller { '|' + root + '/tests/hardware-platform' } else { '' }
			+ '|@vmodules', '-o', state + '/guarded/' + name, source]
		df := checked_df(state)!
		winejitstream.native_require_free(state, winejitstream.native_free_floor(true))!
		policy_account(state, 2 * 1024 * 1024)!
		run := winejitstream.native_guard(argv, state + '/guarded', name + '.build.log', limits)!
		steps[name + '.build'] = Step{argv: argv, df: df, run: run}
		os.write_file(state + '/steps.json', json2.encode(steps))!
		policy_account(state, 2 * 1024 * 1024)!
		if !run.stopped || run.wait_status != 0 || run.timed_out || run.size_limited || run.reason != '' {
			return error('policy build failed; raw result retained: ' + name)
		}
		if (os.lstat(state + '/guarded/' + name)!).get_filetype() != .regular {
			return error('policy build output not ordinary')
		}
		steps[name + '.build'] = Step{argv: argv, df: df, run: run,
			output_pin: winejitstream.native_input_digest(state + '/guarded/' + name)!}
		os.write_file(state + '/steps.json', json2.encode(steps))!
	}
	for name in ['policy-test', 'policy-test-prod', 'policy-sentinel', 'policy-sentinel-prod'] {
		sentinel := name.starts_with('policy-sentinel')
		if sentinel { os.setenv('VINIX_WINE_POLICY_ASSERT_SENTINEL', '1', true) }
		else { os.unsetenv('VINIX_WINE_POLICY_ASSERT_SENTINEL') }
		argv := [state + '/guarded/' + if name.ends_with('-prod') { 'policy-test-prod' } else { 'policy-test' }]
		df := checked_df(state)!
		winejitstream.native_require_free(state, winejitstream.native_free_floor(true))!
		policy_account(state, 2 * 1024 * 1024)!
		run := winejitstream.native_guard(argv, state + '/guarded', name + '.run.log', limits)!
		steps[name + '.run'] = Step{argv: argv, df: df, run: run}
		os.write_file(state + '/steps.json', json2.encode(steps))!
		policy_account(state, 2 * 1024 * 1024)!
		expected := if sentinel { 256 } else { 0 }
		if !run.stopped || run.wait_status != expected || run.timed_out || run.size_limited || run.reason != '' {
			return error('policy control failed; raw result retained: ' + name)
		}
		if sentinel && !os.read_file(state + '/guarded/' + name + '.run.log')!.contains('wine-native-policy intentional assertion sentinel') {
			return error('policy assertion sentinel missing')
		}
	}
	os.unsetenv('VINIX_WINE_POLICY_ASSERT_SENTINEL')
	after := policy_inputs(root)!
	if before != after { return error('selected policy source/compiler inputs changed') }
	os.write_file(state + '/binding-after.json', json2.encode(policy_binding(after)))!
	measured := policy_account(state, 2 * 1024 * 1024)!
	receipt := json2.encode({
		'argv': json2.encode(os.args)
		'environment': json2.encode(environment)
		'selected_binding': json2.encode(policy_binding(after))
		'steps': json2.encode(steps)
		'inclusive_state_plus_2MiB_reserve_before_receipt': measured.str()
		'scope': 'Host-only target-policy controller build and explicit normal/production controls. No target build, staging, image or VM. Full selected private compiler libraries and source trees re-enumerated/hashed before/after. Bootstrap observed outside its own guard. Host SDK and dynamic libraries are not frozen. Separate compiler scratch counted without following links before/after each guarded child; cumulative selected historical/composed/host-06/current state <=64MiB with 2MiB reserve. This profile does not change the static composer 32MiB contract.'
	})
	policy_budget(measured, u64(receipt.len))!
	os.write_file(state + '/policy-receipt.json', receipt)!
	policy_account(state, 2 * 1024 * 1024)!
	winejitstream.native_require_free(state, winejitstream.native_free_floor(false))!
	println('PASS host-only native compiler policy controls')
}

fn state_bytes(path string) !u64 {
	mut total := u64(0)
	for name in os.ls(path)! {
		entry := path + '/' + name
		info := os.lstat(entry)!
		match info.get_filetype() {
			.directory { total += state_bytes(entry)! }
			.regular { total += info.size }
			.symbolic_link { total += info.size }
			else { return error('unsupported host scratch type') }
		}
	}
	if total >= 20 * 1024 * 1024 { return error('host state >=20MiB') }
	return total
}

// Nested fixture groups need their controls leader alive to clean them.
// Forward signals and wait cooperatively. An overrun at 60s requests SIGTERM;
// it is recorded honestly and is not a hard outer deadline.
fn host_bytes(state string, previous string) !u64 {
	mut total := state_bytes(state)!
	if previous != '' { total += state_bytes(previous)! }
	if total >= 20 * 1024 * 1024 { return error('combined host state >=20MiB') }
	return total
}

fn cooperative_controls(binary string, output string, state string, previous string, cancellation bool) !Cooperative {
	mut argv := [binary]
	if cancellation { argv << '--cancel-check' }
	argv << output
	df := checked_df(state)!
	log := state + '/guarded/' + if cancellation {
		'controls.cancel.log'
	} else {
		'controls.run.log'
	}
	fd := C.open(log.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL | C.O_NOFOLLOW, 0o600)
	if fd < 0 { return error('cooperative log open failed') }
	mut exec_arguments := []&char{len: argv.len + 1, init: unsafe { nil }}
	for index, argument in argv { exec_arguments[index] = &char(argument.str) }
	started := time.sys_mono_now()
	pid := C.fork()
	if pid < 0 {
		C.close(fd)
		return error('cooperative controls fork failed')
	}
	if pid == 0 {
		if C.setpgid(0, 0) != 0 { C._exit(120) }
		limit := C.wine_native_host_rlimit{ rlim_cur: 20 * 1024 * 1024, rlim_max: 20 * 1024 * 1024 }
		core_limit := C.wine_native_host_rlimit{}
		if C.wine_native_host_setrlimit(C.RLIMIT_FSIZE, &limit) != 0
			|| C.wine_native_host_setrlimit(C.RLIMIT_CORE, &core_limit) != 0
			|| C.dup2(fd, 1) != 1 || C.dup2(fd, 2) != 2 {
			C._exit(121)
		}
		if fd > 2 { C.close(fd) }
		C.execv(argv[0].str, &exec_arguments[0])
		C._exit(125)
	}
	C.close(fd)
	mut status := int(-1)
	mut forwarded := 0
	mut injected := false
	mut overrun := false
	mut reason := ''
	mut next_free := u64(0)
	for {
		elapsed := (time.sys_mono_now() - started) / 1000000
		if elapsed >= next_free {
			winejitstream.native_require_free(state, 550 * 1024) or { reason = err.msg() }
			host_bytes(state, previous) or { reason = err.msg() }
			next_free = elapsed + 1000
		}
		if elapsed >= 60000 { overrun = true }
		marker := output + '/timeout-descendant/worker.log'
		if cancellation && !injected && os.is_file(marker)
			&& (os.read_file(marker) or { '' }).starts_with('NATIVE GUARD descendant pid=') {
			if C.kill(os.getpid(), C.SIGTERM) != 0 {
				reason = 'wrapper cancellation injection failed'
			}
			injected = true
		}
		mut signal := winejitstream.native_interruption_signal()
		if signal == 0 && (overrun || reason != '') { signal = C.SIGTERM }
		if signal != 0 && forwarded == 0 {
			if C.kill(pid, signal) == 0 { forwarded = signal }
		}
		waited := C.waitpid(pid, &status, C.WNOHANG)
		if waited == pid { break }
		if waited < 0 && C.errno != C.EINTR { return error('cooperative controls wait failed') }
		time.sleep(10 * time.millisecond)
	}
	return Cooperative{
		argv:             argv
		df:               df
		leader_pid:       pid
		wait_status:      status
		duration_ms:      (time.sys_mono_now() - started) / 1000000
		overrun:          overrun
		forwarded_signal: forwarded
		injected_signal:  injected
		reason:           reason
	}
}

fn cancellation_cleanup(output string) ! {
	run := json2.decode[winejitstream.NativeRun](os.read_file(output + '/timeout-descendant/run.json')!)!
	if !run.stopped || run.reason != 'native guard interrupted' || run.timed_out || run.size_limited || run.leader_pid <= 0 || run.wait_status <= 0 {
		return error('cooperative inner cleanup not confirmed')
	}
	text := os.read_file(output + '/timeout-descendant/worker.log')!.trim_space()
	prefix := 'NATIVE GUARD descendant pid='
	if !text.starts_with(prefix) { return error('cancellation descendant missing') }
	pid_text := text[prefix.len..]
	pid := pid_text.int()
	if pid <= 0 || pid.str() != pid_text || C.kill(pid, 0) >= 0 || C.errno != C.ESRCH {
		return error('cancelled descendant survived')
	}
	for member in [run.leader_pid, -run.leader_pid] {
		if C.kill(member, 0) >= 0 || C.errno != C.ESRCH {
			return error('cancelled fixture leader/group survived')
		}
	}
	if os.exists(output + '/leader-exit-descendant') || os.exists(output + '/results.json') {
		return error('cancelled controls started later cases')
	}
}

fn observe() ! {
	if os.args.len !in [4, 5] {
		return error('usage: native-host ROOT EXISTING_STATE V_COMPILER [PREVIOUS_STATE]')
	}
	root := os.real_path(os.args[1])
	state := os.real_path(os.args[2])
	compiler := os.real_path(os.args[3])
	previous := if os.args.len == 5 { os.real_path(os.args[4]) } else { '' }
	if previous == state || (previous != '' && (state.starts_with(previous + '/') || previous.starts_with(state + '/'))) {
		return error('host observation state roots overlap')
	}
	if !os.is_dir(state) || os.is_link(state) {
		return error('requires existing ordinary host state directory')
	}
	if sha256.hexhash(os.read_file(@FILE)!) != sha256.hexhash($embed_file('wine-fork-jit-stream-native-host.v').to_string()) {
		return error('compiled host runner source differs')
	}
	os.chdir(root)!
	if os.exists(state + '/guarded') || os.is_link(state + '/guarded') || os.exists(state + '/receipt.json') || os.is_link(state + '/receipt.json') {
		return error('host observation output already exists')
	}
	for name in ['steps.json', 'inputs-before.json', 'environment.json', 'controller.build.log'] {
		if os.exists(state + '/first-attempt.' + name) || os.is_link(state + '/first-attempt.' + name) {
			return error('first-attempt preservation destination already exists')
		}
	}
	for name in ['steps.json', 'inputs-before.json', 'environment.json', 'controller.build.log'] {
		if os.exists(state + '/' + name) {
			os.mv(state + '/' + name, state + '/first-attempt.' + name)!
		}
	}
	os.mkdir(state + '/guarded')!
	mut environment := map[string]string{}
	for pair in ['V=' + compiler, 'VEXE=' + compiler, 'V_MACOS_V3_CALLER_VEXE=' + compiler,
		'V_MACOS_V3_CALLER_VEXE_PRESENT=1', 'V_MACOS_V3_CALLER_VCHILD_PRESENT=0',
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT=0', 'V_MACOS_V3_NO_FALLBACK=1',
		'V_C_ERROR_BUG_REPORT_DISABLED=1', 'TMPDIR=' + state + '/tmp', 'LC_ALL=C', 'LANG=C'] {
		split := pair.index('=') or { return error('invalid environment literal') }
		name := pair[..split]
		value := pair[split + 1..]
		os.setenv(name, value, true)
		environment[name] = value
	}
	for name in ['VCHILD', 'V_MACOS_V3_CALLER_VCHILD', 'V_MACOS_V3_CALLER_NO_FALLBACK',
		'V_MACOS_V3_CHILD_VEXE_PRESENT'] {
		os.unsetenv(name)
		environment[name] = '<unset>'
	}
	mut pins := map[string]Pin{}
	for path in [@FILE, os.executable(), compiler, clang, os.real_path(clang),
		root + '/tests/packages/wine-fork-jit-stream-native.v',
		root + '/tests/packages/wine-fork-jit-stream-native-controls.v'] {
		pins[path] = pin(path)!
	}
	tree(root + '/tools/packages/winejitstream', mut pins)!
	tree(root + '/tests/hardware-platform/hwhost', mut pins)!
	for path in [compiler + 'lib/os/os_nix.c.v', compiler + 'lib/os/os.c.v',
		compiler + 'lib/os/process_nix.c.v'] {
		pins[path] = pin(path)!
	}
	os.write_file(state + '/inputs-before.json', json2.encode(pins))!
	os.write_file(state + '/environment.json', json2.encode(environment))!
	limits := winejitstream.NativeLimits{ timeout_ms: 60000, file_bytes: 20 * 1024 * 1024, total_bytes: 20 * 1024 * 1024, log_bytes: 256 * 1024, serial_bytes: 256 * 1024, min_free_kib: 550 * 1024 }
	mut steps := map[string]Step{}
	for name in ['controller', 'controls', 'native-test'] {
		source := match name {
			'controller' { root + '/tests/packages/wine-fork-jit-stream-native.v' }
			'controls' { root + '/tests/packages/wine-fork-jit-stream-native-controls.v' }
			else { root + '/tools/packages/winejitstream/native_guard_test.v' }
		}
		modules := '@vlib|' + root + if name == 'controller' {
			'|' + root + '/tests/hardware-platform'
		} else {
			''
		} + '|@vmodules'
		argv := [compiler, '-cc', clang, '-prod', '-gc', 'none', '-manualfree', '-path', modules,
			'-o', state + '/' + name, source]
		df := checked_df(state)!
		os.write_file(state + '/' + name + '.build.argv.json', json2.encode(argv))!
		host_bytes(state, previous)!
		run := winejitstream.native_guard(argv, state + '/guarded', name + '.build.log', limits)!
		// Keep the raw run even when compilation produced no output.
		steps[name + '.build'] = Step{ argv: argv, df: df, run: run }
		os.write_file(state + '/steps.json', json2.encode(steps))!
		host_bytes(state, previous)!
		if !run.stopped || run.wait_status != 0 || run.timed_out || run.size_limited || run.reason != '' {
			return error(name + ' build failed')
		}
		if (os.lstat(state + '/' + name)!).get_filetype() != .regular {
			return error('host compiler output is not ordinary')
		}
		steps[name + '.build'] = Step{ argv: argv, df: df, run: run, output_pin: pin(state + '/' + name)!.digest }
		os.write_file(state + '/steps.json', json2.encode(steps))!
	}
	for name in ['native-test'] {
		argv := [state + '/' + name]
		host_bytes(state, previous)!
		df := checked_df(state)!
		run := winejitstream.native_guard(argv, state + '/guarded', name + '.run.log', limits)!
		steps[name + '.run'] = Step{ argv: argv, df: df, run: run }
		os.write_file(state + '/steps.json', json2.encode(steps))!
		host_bytes(state, previous)!
		if !run.stopped || run.wait_status != 0 || run.timed_out || run.size_limited || run.reason != '' {
			return error(name + ' run failed')
		}
	}
	mut cooperative := map[string]Cooperative{}
	for cancellation in [false, true] {
		name := if cancellation { 'cancellation' } else { 'normal' }
		output := state + '/control-results-' + name
		observation := cooperative_controls(state + '/controls', output, state, previous, cancellation)!
		cooperative[name] = observation
		os.write_file(state + '/cooperative.json', json2.encode(cooperative))!
		host_bytes(state, previous)!
		if observation.overrun || observation.reason != '' {
			return error('controls cooperation exceeded expectations')
		}
		if cancellation {
			if observation.wait_status != (1 << 8) || observation.forwarded_signal != C.SIGTERM || !observation.injected_signal {
				return error('wrapper SIGTERM forwarding was not observed')
			}
			cancellation_cleanup(output)!
		} else if observation.wait_status != 0 || observation.forwarded_signal != 0 {
			return error('normal controls failed or were interrupted')
		}
	}
	for path, expected in pins {
		if pin(path)! != expected { return error('input changed: ' + path) }
	}
	os.write_file(state + '/inputs-after.json', json2.encode(pins))!
	measured := host_bytes(state, previous)!
	receipt := json2.encode({
		'scope':                      'Host-only compiler/controls observation. No target binaries, staging, image or VM. Operation logs guarded; host compiler scratch isolated, measured no-follow before/after each step. Selected input hashes do not freeze host SDK or transitive dynamic libraries.'
		'observer_argv':              json2.encode(os.args)
		'steps':                      json2.encode(steps)
		'cooperative_controls':       json2.encode(cooperative)
		'environment':                json2.encode(environment)
		'inputs':                     json2.encode(pins)
		'state_bytes_before_receipt': measured.str()
		'previous_state':             previous
		'final_df':                   checked_df(state)!
	})
	if u64(receipt.len) >= u64(20 * 1024 * 1024) - measured {
		return error('combined host state plus receipt >=20MiB')
	}
	os.write_file(state + '/receipt.json', receipt)!
	host_bytes(state, previous)!
	checked_df(state)!
	println('PASS host-only receipt and source recheck')
}
