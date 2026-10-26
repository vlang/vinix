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
	observe() or {
		eprintln(err)
		exit(1)
	}
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
