// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed owner for the supplemental ARM diagnostic and its host controls.
module main

import json2
import os
import time
import tools.packages.winejitstream
import tools.sourcecommand

#include <unistd.h>
#include <signal.h>

fn C.getpgrp() i32
fn C.getppid() i32
fn C.kill(i32, i32) i32
fn C.fork() i32
fn C.pause() i32
fn C.execv(&char, &&char) i32
fn C._exit(i32)

const base = '/Users/alex/Library/Caches/vinix-codex/section14'
const root = '/Users/alex/code/vinix/build/package-wine-adapter-worktree'
const overlay = '/Users/alex/.cache/vinix-waitpid-width-20261026-02'
const compiler = overlay + '/toolchain/v'
const clang = '/opt/homebrew/opt/llvm/bin/clang'
const host_state = base + '/wine-jit-stream-native-owner-host-01'
const controls_state = base + '/wine-jit-stream-native-owner-controls-02'
const native_state = base + '/wine-jit-stream-native-arm-02'
const controller = host_state + '/capture/controller'
const kernel = base + '/matched-peer-frame-20261026/build-05/aarch64/bin/vinix'
const receipt = base + '/wine-jit-stream-native-kernel-bind-01/kernel-binding.json'
const translator = '/Users/alex/code/vinix/build/package-wine-translation-fork-qualified-1/extras/qemu-x86_64'
const arm_sysroot = '/Users/alex/code/vinix/build/package-rollback-transaction-work/sysroot'
const arm_gcc = '/Users/alex/code/vinix/build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0'
const amd_sysroot = base + '/wine-jit-stream-native-inputs-01/x86_64-linux-musl'
const amd_gcc = base + '/wine-jit-stream-native-inputs-01/lib/gcc/x86_64-linux-musl/14.2.0'

struct OwnerPolicy {
	deadline_ms u64
	state_bytes u64
	file_bytes u64
	log_bytes u64
	serial_bytes u64
}

struct OwnerContext {
	state string
	policy OwnerPolicy
	started u64
mut:
	pid int
	peak_bytes u64
	next_free_ms u64
}

struct OwnerResult {
	argv []string
	policy OwnerPolicy
	pid int
	status int
	status_observed bool
	reason string
	elapsed_ms u64
	peak_admitted_bytes u64
	leader_absent bool
	group_absent bool
	cleanup_probe_attempts int
	leader_probe_status i32
	leader_probe_errno i32
	group_probe_status i32
	group_probe_errno i32
	cleanup string = 'sourcecommand retires the reserved private group before its sole leader reap; absence probed afterward without signaling a released identity'
}

fn ordinary_directory(path string) ! {
	if os.real_path(path) != path || os.lstat(path)!.get_filetype() != .directory {
		return error('requires a canonical ordinary directory: ' + path)
	}
}

fn source_check() ! {
	for relative, compiled in {
		'tests/packages/wine-fork-jit-stream-native-owner.v': $embed_file('wine-fork-jit-stream-native-owner.v').to_string()
		'tools/sourcecommand/core.v': $embed_file('../../tools/sourcecommand/core.v').to_string()
		'tools/sourcecommand/abi.h': $embed_file('../../tools/sourcecommand/abi.h').to_string()
		'tools/sourcecommand/logged.v': $embed_file('../../tools/sourcecommand/logged.v').to_string()
		'tools/sourcecommand/reader.v': $embed_file('../../tools/sourcecommand/reader.v').to_string()
		'tools/sourcecommand/pty.v': $embed_file('../../tools/sourcecommand/pty.v').to_string()
		'tools/sourcecommand/duplex.v': $embed_file('../../tools/sourcecommand/duplex.v').to_string()
		'tools/packages/winejitstream/native_guard.v': $embed_file('../../tools/packages/winejitstream/native_guard.v').to_string()
		'tools/packages/winejitstream/native_inputs.v': $embed_file('../../tools/packages/winejitstream/native_inputs.v').to_string()
		'tools/packages/winejitstream/native_policy.v': $embed_file('../../tools/packages/winejitstream/native_policy.v').to_string()
		'tools/packages/winejitstream/supervisor.v': $embed_file('../../tools/packages/winejitstream/supervisor.v').to_string()
	} {
		if os.read_file(root + '/' + relative)! != compiled {
			return error('compiled owner source differs: ' + relative)
		}
	}
}

fn hard_limits(bytes u64) ! {
	winejitstream.native_apply_file_limits(bytes)!
}

// Root names are limited to 32. Each ordinary subtree has the existing
// 512-entry bound and admits only its relative boot/qmp.sock socket.
fn sample(state string, policy OwnerPolicy) !u64 {
	ordinary_directory(state)!
	names := os.ls(state)!
	if names.len > 32 { return error('owner root exceeds 32 entries') }
	mut total := u64(0)
	for name in names {
		path := state + '/' + name
		info := os.lstat(path) or { if err.code() == C.ENOENT { continue }; return err }
		if info.get_filetype() == .directory {
			total += winejitstream.native_require_state(path, winejitstream.NativeLimits{
				file_bytes: policy.file_bytes, total_bytes: policy.state_bytes,
				log_bytes: policy.log_bytes, serial_bytes: policy.serial_bytes,
			})!
		} else if info.get_filetype() == .regular {
			cap := if name.ends_with('.log') { policy.log_bytes } else { policy.file_bytes }
			if info.size >= cap { return error('owner root file threshold reached: ' + name) }
			total += info.size
		} else { return error('owner root contains a link or unsupported entry') }
		if total > policy.state_bytes { return error('owner state threshold exceeded') }
	}
	return total
}

fn observed(pid int, pointer voidptr) ! {
	mut context := unsafe { &OwnerContext(pointer) }
	context.pid = pid
	for {
		if winejitstream.native_was_interrupted() {
			return error('whole owner interrupted by signal ' + winejitstream.native_interruption_signal().str())
		}
		elapsed := (time.sys_mono_now() - context.started) / 1000000
		if elapsed >= context.policy.deadline_ms { return error('whole owner deadline exceeded') }
		bytes := sample(context.state, context.policy)!
		if bytes > context.peak_bytes { context.peak_bytes = bytes }
		if elapsed >= context.next_free_ms {
			winejitstream.native_require_free(context.state, winejitstream.native_free_floor(false))!
			context.next_free_ms = elapsed + 1000
		}
		if sourcecommand.child_exited(pid)! { return }
		time.sleep(20 * time.millisecond)
	}
}

fn own(argv []string, state string, environment map[string]string, policy OwnerPolicy) !OwnerResult {
	winejitstream.native_watch_interrupts()!
	if os.exists(state) || os.is_link(state) { return error('owner output already exists') }
	ordinary_directory(os.dir(state))!
	winejitstream.native_require_free(os.dir(state), winejitstream.native_free_floor(true))!
	os.mkdir(state)!
	os.write_file(state + '/owner.argv.json', json2.encode(argv) + '\n')!
	os.write_file(state + '/owner.environment.json', json2.encode(environment) + '\n')!
	mut context := OwnerContext{state: state, policy: policy, started: time.sys_mono_now()}
	mut reason := ''
	mut status := 0
	result := sourcecommand.run_logged_owned(argv, environment, unsafe { nil }, state + '/owner.log',
		false, root, observed, unsafe { &context }, 0) or {
		reason = err.msg()
		sourcecommand.Output{}
	}
	if reason == '' { status = result.status }
	// Probe only: retirement and sole reap have finished. Never signal a
	// numeric identity after the command owner has released its reservation.
	deadline := time.sys_mono_now() + u64(2 * time.second)
	mut leader_absent := false
	mut group_absent := false
	mut attempts := 0
	mut leader_status := i32(0)
	mut leader_errno := i32(0)
	mut group_status := i32(0)
	mut group_errno := i32(0)
	for context.pid > 0 {
		attempts++
		leader_status = C.kill(i32(context.pid), 0)
		leader_errno = if leader_status < 0 { i32(C.errno) } else { i32(0) }
		group_status = C.kill(i32(-context.pid), 0)
		group_errno = if group_status < 0 { i32(C.errno) } else { i32(0) }
		leader_absent = leader_status < 0 && leader_errno == C.ESRCH
		group_absent = group_status < 0 && group_errno == C.ESRCH
		if (leader_absent && group_absent) || time.sys_mono_now() >= deadline { break }
		time.sleep(10 * time.millisecond)
	}
	output := OwnerResult{argv: argv, policy: policy, pid: context.pid, status: status, status_observed: reason == '',
		reason: reason, elapsed_ms: (time.sys_mono_now() - context.started) / 1000000,
		peak_admitted_bytes: context.peak_bytes, leader_absent: leader_absent, group_absent: group_absent,
		cleanup_probe_attempts: attempts, leader_probe_status: leader_status, leader_probe_errno: leader_errno,
		group_probe_status: group_status, group_probe_errno: group_errno}
	// This post-retirement receipt is charged to the reviewed metadata reserve;
	// the live child-state samples above do not include its later bytes.
	os.write_file(state + '/owner.result.json', json2.encode(output) + '\n')!
	winejitstream.native_require_free(state, winejitstream.native_free_floor(false))!
	return output
}

fn fixed_environment(scratch string, modules string) map[string]string {
	return {'PATH': '/opt/homebrew/bin:/usr/bin:/bin', 'LANG': 'C', 'LC_ALL': 'C',
		'V': compiler, 'VEXE': compiler, 'VINIX_V_COMPILER': compiler,
		'V_MACOS_V3_CALLER_VEXE': compiler, 'V_MACOS_V3_CALLER_VEXE_PRESENT': '1',
		'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0', 'V_MACOS_V3_CALLER_NO_FALLBACK': '1',
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1', 'V_MACOS_V3_NO_FALLBACK': '1',
		'V_C_ERROR_BUG_REPORT_DISABLED': '1', 'TMPDIR': scratch, 'VTMP': scratch,
		'VMODULES': modules}
}

fn host_inputs() !map[string]winejitstream.NativePin {
	mut pins := map[string]winejitstream.NativePin{}
	for path in [compiler, clang, os.executable(), overlay + '/bundle.json',
		overlay + '/overlay-before.json', overlay + '/changes.json', overlay + '/toolchain/v.mod',
		root + '/tests/packages/wine-fork-jit-stream-native.v',
		root + '/tests/packages/wine-fork-jit-stream-native-owner.v'] {
		winejitstream.native_input_add(path, mut pins)!
	}
	for path in [overlay + '/toolchain/vlib', overlay + '/toolchain/thirdparty',
		root + '/tools/packages/winejitstream', root + '/tools/sourcecommand',
		root + '/tests/hardware-platform/hwhost'] {
		winejitstream.native_input_tree(path, mut pins)!
	}
	return pins
}

struct OverlayPin { path string sha256 string }

fn overlay_walk(relative string, mut pins []OverlayPin) ! {
	if pins.len >= 30000 { return error('qualified compiler overlay exceeds entry bound') }
	path := overlay + '/toolchain/' + relative
	info := os.lstat(path)!
	if info.get_filetype() == .directory {
		pins << OverlayPin{relative, 'directory'}
		for name in os.ls(path)! { overlay_walk(relative + '/' + name, mut pins)! }
	} else if info.get_filetype() == .regular {
		pins << OverlayPin{relative, winejitstream.native_input_digest(path)!}
	} else { return error('qualified compiler overlay contains unsupported input') }
}

fn qualified_overlay() ! {
	mut actual := []OverlayPin{}
	for name in ['v', 'vlib', 'thirdparty', 'v.mod', 'snapshot.json'] { overlay_walk(name, mut actual)! }
	mut expected := json2.decode[[]OverlayPin](os.read_file(overlay + '/overlay-before.json')!)!
	actual.sort(a.path < b.path)
	expected.sort(a.path < b.path)
	if actual != expected { return error('complete qualified compiler root differs') }
}

fn require_pin(path string, digest string) ! {
	if winejitstream.native_input_digest(path)! != digest { return error('fixed input differs: ' + path) }
}

fn require_owner() !int {
	group := int(C.getpgrp())
	if group <= 1 || group != os.getpid() { return error('owner child is not its reserved group leader') }
	return group
}

fn host_child() ! {
	group := require_owner()!
	hard_limits(16 * 1024 * 1024)!
	source_check()!
	for name in ['capture', 'scratch', 'modules'] { os.mkdir(host_state + '/' + name)! }
	for name, value in fixed_environment(host_state + '/scratch', host_state + '/modules') {
		os.setenv(name, value, true)
	}
	for path, digest in {
		compiler: 'ff75a30180b1de305e3c62acc1ebd85341ff83ae5d852c819d11f27d5260c4c5'
		clang: '4e4fd968922cd634ebb6445325703a6276effde7b39337a6a9ff40b3b0c657b8'
		overlay + '/bundle.json': '32d8bc5f46c953aeb5e9ad1ad63e182f10752fe270983943a22c040016617976'
		overlay + '/overlay-before.json': '65b8b8322a34407c4b16762803c618e2fe8f414cc0bc5ccb10144bf20292786f'
		overlay + '/changes.json': '4941c055c018c321d7a4cc94c054b26ba6494bc6be7fa508d99a1bb10b7b2b21'
	} { require_pin(path, digest)! }
	qualified_overlay()!
	before := host_inputs()!
	os.write_file(host_state + '/inputs-before.json', json2.encode(before) + '\n')!
	winejitstream.native_require_empty_modules(host_state + '/modules')!
	argv := [compiler, '-nocache', '-prod', '-cc', clang, '-gc', 'none', '-manualfree',
		'-path', '@vlib|' + root + '|' + root + '/tests/hardware-platform|@vmodules',
		'-o', controller, root + '/tests/packages/wine-fork-jit-stream-native.v']
	os.write_file(host_state + '/controller.argv.json', json2.encode(argv) + '\n')!
	run := winejitstream.native_guard_inherited(argv, host_state + '/capture', 'build.log',
		winejitstream.NativeLimits{timeout_ms: 120000, file_bytes: 16 * 1024 * 1024,
			total_bytes: 16 * 1024 * 1024, log_bytes: 256 * 1024, serial_bytes: 256 * 1024,
			min_free_kib: winejitstream.native_free_floor(false)}, group)!
	os.write_file(host_state + '/controller.guard.json', json2.encode(run) + '\n')!
	if !run.stopped || run.wait_status != 0 || run.timed_out || run.size_limited || run.reason != '' {
		return error('fresh controller build failed; actual guard result retained')
	}
	winejitstream.native_require_empty_modules(host_state + '/modules')!
	qualified_overlay()!
	after := host_inputs()!
	if before != after { return error('selected controller build inputs changed') }
	os.write_file(host_state + '/inputs-after.json', json2.encode(after) + '\n')!
	os.write_file(host_state + '/controller.sha256', winejitstream.native_input_digest(controller)! + '\n')!
	println('PASS fresh production controller build; full selected maps equal; no controller or target execution')
}

fn native_child(digest string) ! {
	group := require_owner()!
	hard_limits(128 * 1024 * 1024)!
	source_check()!
	if digest.len != 64 || !digest.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`)) {
		return error('requires reviewed controller SHA256')
	}
	require_pin(controller, digest)!
	if os.read_file(host_state + '/controller.sha256')! != digest + '\n' {
		return error('controller build digest receipt differs')
	}
	require_pin(receipt, 'cdee03dabbcd5af40f5e1b7dc0eed94994042fac48c37f23bd630b8edcdd80dd')!
	require_pin(kernel, 'e805a73154d61503d6427f1ccc4d19b1eb9ec802ed38255e059e0b2bd1e83174')!
	for path, expected_digest in {
		'/opt/homebrew/bin/qemu-system-aarch64': '45d74da57beb9be259ca3d6996e5c70d4ab14326ea59c3db3e80308859d91a3e'
		'/opt/homebrew/Cellar/qemu/11.1.1/share/qemu/edk2-aarch64-code.fd': '47765fe344818cbc464b1c14ae658fb4b854f5c2ceffa982411731eb4865594d'
		'/opt/homebrew/Cellar/qemu/11.1.1/share/qemu/edk2-arm-vars.fd': 'b3b855c5a80310168051164986855692d1bdb06e67619856177965cd87c6774f'
		'/Users/alex/code/vinix/boot-image/limine-bin/BOOTAA64.EFI': '3a23c79b75dd78fbacb6430472ce4aa5e90ef89089a4970459a0282cf44ccb4f'
		'/opt/homebrew/bin/ld.lld': '745f1b0e8809caef992e6136402561787d951cafe3d0d1736bdc7c03be41e98b'
	} { require_pin(path, expected_digest)! }
	winejitstream.native_input_verify(json2.decode[map[string]winejitstream.NativePin](
		os.read_file(host_state + '/inputs-after.json')!)!)!
	for name in ['mformat', 'mmd', 'mcopy'] {
		require_pin(os.find_abs_path_of_executable(name)!, 'e8310ca53ac5f471b7cd8b0b4dacd2ef11a57e399e35d034d1b6899e49dd48a6')!
	}
	require_pin('/usr/bin/tar', '9ab7f0793033dc9dc4809d83d695118801bd687cbacda59a0cbbf151ba25dc2b')!
	require_pin('/bin/cp', '07cdcfe6a6474d9abac66f0b1959e2e9e4877bf4629e2e400249a3e7641b09f9')!
	os.setenv('VINIX_WINE_NATIVE_OWNER_PGID', group.str(), true)
	os.setenv('VINIX_QEMU_AARCH64', '/opt/homebrew/bin/qemu-system-aarch64', true)
	os.setenv('VINIX_OVMF_CODE_AARCH64', '/opt/homebrew/Cellar/qemu/11.1.1/share/qemu/edk2-aarch64-code.fd', true)
	os.setenv('VINIX_OVMF_VARS_AARCH64', '/opt/homebrew/Cellar/qemu/11.1.1/share/qemu/edk2-arm-vars.fd', true)
	os.setenv('VINIX_LIMINE_BOOTAA64', '/Users/alex/code/vinix/boot-image/limine-bin/BOOTAA64.EFI', true)
	argv := [controller, root, translator, kernel, receipt, compiler, arm_sysroot, arm_gcc,
		amd_sysroot, amd_gcc, native_state + '/capture']
	os.write_file(native_state + '/controller.argv.json', json2.encode(argv) + '\n')!
	mut arguments := []&char{}
	for argument in argv { arguments << &char(argument.str) }
	arguments << &char(unsafe { nil })
	C.execv(controller.str, arguments.data)
	return error('cannot exec reviewed native controller')
}

fn successful(result OwnerResult) ! {
	if !result.status_observed || result.status != 0 || result.reason != ''
		|| !result.leader_absent || !result.group_absent {
		return error('owned command failed; actual owner result retained')
	}
}

fn fixture_tool(state string, mode string) ! {
	leaf := C.fork()
	if leaf < 0 { return error('fixture leaf fork failed') }
	if leaf == 0 { for { C.pause() } }
	os.write_file(state + '/pids', C.getppid().str() + '\n' + os.getpid().str() + '\n' + leaf.str() + '\n')!
	os.write_file(state + '/group', C.getpgrp().str() + '\n')!
	match mode {
		'controller-crash' { C.kill(C.getppid(), C.SIGKILL) }
		'owner-interrupt' {
			owner := os.getenv('VINIX_WINE_NATIVE_CONTROL_OWNER_PID').int()
			if owner <= 1 || owner == os.getpid() || C.kill(i32(owner), C.SIGTERM) != 0 {
				return error('cannot interrupt the enclosing fixture owner')
			}
		}
		'success-descendant' { return }
		'state-cap' {
			for index in 0 .. 3 { os.write_file(state + '/payload-' + index.str(), 'x'.repeat(24000))! }
		}
		'log-cap' { print('x'.repeat(9000)); flush_stdout() }
		else {}
	}
	for { C.pause() }
}

fn fixture_controller(state string, mode string) ! {
	group := require_owner()!
	hard_limits(64 * 1024)!
	os.mkdir(state + '/capture')!
	limits := winejitstream.NativeLimits{timeout_ms: if mode == 'inner-timeout' { 150 } else { 5000 },
		file_bytes: 64 * 1024, total_bytes: 128 * 1024, log_bytes: 32 * 1024,
		serial_bytes: 32 * 1024, min_free_kib: winejitstream.native_free_floor(false)}
	if mode == 'group-refusal' {
		winejitstream.native_guard_inherited([os.executable(), '--fixture-tool', state, mode],
			state + '/capture', 'worker.log', limits, group + 1) or {
			os.write_file(state + '/refused', err.msg() + '\n')!
			return
		}
		return error('incorrect owner group admitted')
	}
	run := winejitstream.native_guard_inherited([os.executable(), '--fixture-tool', state, mode],
		state + '/capture', 'worker.log', limits, group)!
	os.write_file(state + '/guard.json', json2.encode(run) + '\n')!
	if !run.stopped || run.owner_group != group || run.cleanup_scope != 'direct-leader; outer-group-owned' {
		return error('inherited guard cleanup scope differs')
	}
	if mode == 'inner-timeout' {
		if !run.timed_out || run.wait_status == 0 { return error('inner timeout not observed') }
		exit(17)
	}
	if run.wait_status != 0 || run.timed_out || run.size_limited || run.reason != '' {
		return error('inherited fixture failed')
	}
}

fn controls() ! {
	if os.exists(controls_state) || os.is_link(controls_state) { return error('controls already exist') }
	source_check()!
	os.mkdir(controls_state)!
	mut results := map[string]OwnerResult{}
	for mode in ['success-descendant', 'controller-crash', 'owner-timeout', 'state-cap',
		'log-cap', 'inner-timeout', 'group-refusal', 'owner-interrupt'] {
		state := controls_state + '/' + mode
		mut environment := fixed_environment('/tmp', '/nonexistent-vinix-control-modules')
		environment['VINIX_WINE_NATIVE_CONTROL_OWNER_PID'] = os.getpid().str()
		result := own([os.executable(), '--fixture-controller', state, mode], state,
			environment,
			OwnerPolicy{deadline_ms: if mode == 'owner-timeout' { u64(1000) } else { u64(2000) },
				state_bytes: 64 * 1024, file_bytes: 32 * 1024, log_bytes: 8192,
				serial_bytes: 8192})!
		results[mode] = result
		os.write_file(controls_state + '/results.json', json2.encode(results) + '\n')!
		if !result.leader_absent || !result.group_absent { return error(mode + ': outer group survived') }
		match mode {
			'success-descendant' { successful(result)! }
			'group-refusal' {
				successful(result)!
				if !os.exists(state + '/refused') || os.exists(state + '/pids')
					|| os.exists(state + '/capture/worker.log') {
					return error('wrong group spawned a guarded child')
				}
			}
			'controller-crash' {
				if !result.status_observed || result.status != -9 || result.reason != '' {
					return error('abrupt controller status differs')
				}
			}
			'inner-timeout' {
				if !result.status_observed || result.status != 17 || result.reason != '' {
					return error('inner timeout status differs')
				}
			}
			'owner-timeout' {
				if result.status_observed || result.reason != 'whole owner deadline exceeded' {
					return error('owner deadline failure was not retained')
				}
			}
			'owner-interrupt' {
				if result.status_observed || result.reason != 'whole owner interrupted by signal 15' {
					return error('cooperative owner interruption was not retained')
				}
			}
			else {
				if result.status_observed || !result.reason.contains('threshold') {
					return error(mode + ': sampled threshold failure was not retained')
				}
			}
		}
		if mode != 'group-refusal' {
			if !os.is_file(state + '/group') || !os.is_file(state + '/pids') {
				return error(mode + ': fixture did not reach readiness within its finite bound')
			}
			if os.read_file(state + '/group')! != result.pid.str() + '\n' {
				return error('inner tool escaped reserved owner group')
			}
			for text in os.read_file(state + '/pids')!.split_into_lines() {
				pid := text.int()
				if pid <= 0 || C.kill(i32(pid), 0) >= 0 || C.errno != C.ESRCH {
					return error(mode + ': fixture process survived retirement')
				}
			}
		}
	}
	println('PASS inherited native owner: success descendants, crash, outer/inner timeouts, state/log caps, group refusal, cooperative owner interruption; no target or VM')
}

fn main() {
	$if prod {} $else { eprintln('owner requires -prod'); exit(1) }
	if os.args.len == 4 && os.args[1] == '--fixture-tool' {
		fixture_tool(os.args[2], os.args[3]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len == 4 && os.args[1] == '--fixture-controller' {
		fixture_controller(os.args[2], os.args[3]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len == 2 && os.args[1] == '--controls' {
		controls() or { eprintln(err); exit(1) }
		return
	}
	if os.args.len == 2 && os.args[1] == '--host-child' {
		host_child() or { eprintln(err); exit(1) }
		return
	}
	if os.args.len == 3 && os.args[1] == '--native-child' {
		native_child(os.args[2]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len == 2 && os.args[1] == '--host' {
		result := own([os.executable(), '--host-child'], host_state,
			fixed_environment(host_state + '/scratch', host_state + '/modules'),
			OwnerPolicy{deadline_ms: 180000, state_bytes: 16 * 1024 * 1024,
				file_bytes: 16 * 1024 * 1024, log_bytes: 256 * 1024,
				serial_bytes: 256 * 1024}) or { eprintln(err); exit(1) }
		successful(result) or { eprintln(err); exit(1) }
		println('PASS owned host production controller qualification')
		return
	}
	if os.args.len == 3 && os.args[1] == '--native' {
		result := own([os.executable(), '--native-child', os.args[2]], native_state,
			fixed_environment('/tmp', '/nonexistent-vinix-private-modules'),
			OwnerPolicy{deadline_ms: 300000, state_bytes: 256 * 1024 * 1024,
				file_bytes: 128 * 1024 * 1024, log_bytes: 256 * 1024,
				serial_bytes: 6 * 1024 * 1024}) or { eprintln(err); exit(1) }
		successful(result) or { eprintln(err); exit(1) }
		println('PASS whole owned native supplemental capture; not workload qualification')
		return
	}
	eprintln('usage: native-owner --host | --controls | --native REVIEWED_CONTROLLER_SHA256')
	exit(2)
}
