// SPDX-License-Identifier: GPL-2.0-or-later
module main

import fixturehost
import json2
import guesthost
import hosttest
import os
import policyhost
import time

#include <sys/wait.h>
#include <fcntl.h>
fn C.fcntl(i32, i32, ...int) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.fork() i32
fn C.pause() i32
fn C.kill(i32, i32) i32
fn C.getppid() i32

fn descriptors() int {
	mut count := 0
	for fd in 0 .. 4096 { if C.fcntl(fd, C.F_GETFD) >= 0 { count++ } }
	return count
}

fn write_all(fd i32, text string) {
	mut offset := 0
	for offset < text.len {
		count := unsafe { C.write(fd, text.str + offset, usize(text.len - offset)) }
		assert count > 0
		offset += int(count)
	}
}

fn child(mode string) {
	if mode == 'group' {
		pid := C.fork()
		assert pid >= 0
		if pid == 0 { for { C.pause() } }
		os.write_file(os.args[3], pid.str()) or { panic(err) }
		for { time.sleep(20 * time.millisecond) }
	}
	if mode == 'interrupt' {
		C.kill(C.getppid(), C.SIGINT)
		for { time.sleep(20 * time.millisecond) }
	}
	if mode == 'cwd' {
		println('cwd:' + os.getwd())
		println('CWD: PASS')
		flush_stdout()
		time.sleep(300 * time.millisecond)
		return
	}
	if mode == 'eof' {
		write_all(1, 'READY')
		C.close(1)
		C.close(2)
		time.sleep(10 * time.second)
		return
	}
	write_all(1, 'A\x00\xff')
	write_all(2, 'B\x80')
	write_all(1, 'a'.repeat(700000))
	write_all(2, 'b'.repeat(600000))
	exit(7)
}

fn check_capture() ! {
	baseline := descriptors()
	result := fixturehost.capture_merged_bounded([os.executable(), '--child', 'stream'],
		policyhost.environment(), policyhost.caller_arch(), '', 3.0, unsafe { nil })!
	assert result.status == 7 && result.stderr == ''
	assert result.stdout == 'A\x00\xffB\x80' + 'a'.repeat(700000) + 'b'.repeat(600000)
	for _ in 0 .. 20 {
		started := time.sys_mono_now()
		fixturehost.capture_merged_bounded([os.executable(), '--child', 'eof'],
			policyhost.environment(), policyhost.caller_arch(), '', 0.08, unsafe { nil }) or {
			assert err.msg().starts_with('Command timed out after ')
			elapsed := time.sys_mono_now() - started
			assert elapsed >= 60 * u64(time.millisecond) && elapsed < 3 * u64(time.second)
			assert descriptors() == baseline
			mut status := i32(0)
			assert C.waitpid(-1, &status, C.WNOHANG) == -1 && C.errno == C.ECHILD
			continue
		}
		return error('Fractional EOF deadline did not stop and reap the fixture')
	}
	assert descriptors() == baseline
	println('PASS merged binary stream, fractional EOF deadline and twenty FD/PID retirement cycles')
	group_work := hosttest.work_dir('', 'vinix-serial-group-')!
	defer { hosttest.remove_work_dir(group_work) or { eprintln(err.msg()) } }
	mut group_timeout := false
	fixturehost.capture_owned_bounded([os.executable(), '--child', 'group', group_work + '/child.pid'],
		policyhost.environment(), policyhost.caller_arch(), '', 0.4, unsafe { nil }, true) or {
		assert err.msg().starts_with('Command timed out after ')
		pid := (os.read_file(group_work + '/child.pid') or { panic(err) }).int()
		deadline := time.sys_mono_now() + 3 * u64(time.second)
		for C.kill(pid, 0) == 0 && time.sys_mono_now() < deadline { time.sleep(20 * time.millisecond) }
		assert C.kill(pid, 0) < 0 && C.errno == C.ESRCH
		assert descriptors() == baseline
		group_timeout = true
	}
	assert group_timeout
	guard := policyhost.own_commands()
	policyhost.owned_inherited_environment([os.executable(), '--child', 'interrupt'],
		policyhost.environment(), policyhost.caller_arch(), '') or {
		assert err.msg() == 'Host test interrupted' && err.code() == 130
		assert policyhost.command_interrupted()
		guard.close()
		assert descriptors() == baseline
		println('PASS nested SIGINT scope, private group retirement and descriptor owners')
		return
	}
	guard.close()
	return error('Interrupt did not retire its native command group')
}

fn check_producer(producer string, work string) ! {
	root := hosttest.root()
	v := policyhost.capture(['sh', '-c', '. "$1/build-support/find-v.sh"; printf "%s" "$V"', 'find-v', root])!
	for mode in ['shell', 'full', 'desktop'] {
		for mask in 0 .. 8 {
			name := mode + '-' + mask.str()
			baseline := work + '/' + name
			os.mkdir(baseline)!
			hosttest.module_copy_tree(root + '/build-support/init-aarch64/initcore', baseline + '/initcore')!
			mut options := []string{}
			mut command := [v, '-shared', '-no-builtin', '-no-closures', '-os', 'vinix',
				'-target-libc-headers', '-nofloat', '-gc', 'none', '-manualfree']
			if mode != 'shell' { command << ['-d', 'init_' + mode] }
			if mask & 1 != 0 {
				options << '--host'
				command << ['-d', 'init_host']
				for file in os.ls(baseline + '/initcore')! {
					if !file.ends_with('.v') { continue }
					path := baseline + '/initcore/' + file
					mut text := hosttest.module_read_text(path)!
					for symbol in ['memcpy', 'memset', 'memmove', '_start'] {
						text = text.replace("@[export: '" + symbol + "']", "@[export: 'vinix_init_host_" + symbol + "']")
					}
					hosttest.module_write_text(path, text)!
				}
			}
			if mask & 2 != 0 { options << '--wifi-bundle'; command << ['-d', 'init_wifi_bundle'] }
			if mask & 4 != 0 { options << '--busybox-echo-test'; command << ['-d', 'init_busybox_echo_test'] }
			os.write_file(baseline + '/v.mod', "Module { name: 'init_bridge' }\n")!
			os.write_file(baseline + '/entry.v', 'module main\nimport initcore as _\n')!
			command << ['-o', baseline + '/original.c', baseline]
			policyhost.inherited(command)!
			text := hosttest.module_read_text(baseline + '/original.c')!
			original := '#pragma GCC diagnostic ignored "-Wunused-function"\n#pragma GCC diagnostic ignored "-Wunused-label"\n#pragma GCC diagnostic ignored "-Wunused-parameter"\n' +
				text.replace('#include <inttypes.h>\n', '') +
				'\n_Static_assert(sizeof(initcore__SignalAction) == 32 && offsetof(initcore__SignalAction, flags) == 8 && offsetof(initcore__SignalAction, restorer) == 16 && offsetof(initcore__SignalAction, mask) == 24, "raw ARM signal ABI");\n_Static_assert(sizeof(initcore__Delay) == 16 && offsetof(initcore__Delay, nanoseconds) == 8, "raw ARM time ABI");\n'
			actual := baseline + '/actual.c'
			policyhost.inherited([producer, mode, actual, ...options])!
			assert hosttest.module_read_text(actual)! == original, name
		}
	}
	println('PASS byte-identical init sources for all twenty-four original option combinations')
}

fn check_interrupts(producer string, churn string, rsp string, work string) ! {
	scratch := work + '/owner scratch\\bytes'
	os.mkdir(scratch)!
	mut env := policyhost.environment()
	env['TMPDIR'] = scratch
	env['V'] = os.executable()
	env['VINIX_SERIAL_QA_SURROGATE'] = '1'
	env['VINIX_SERIAL_QA_PID'] = work + '/surrogate.pid'
	mut commands := [[producer, 'desktop', work + '/interrupt.c']]
	if churn != '' {
		env['CC_AMD64'] = os.executable()
		commands << [churn, '--arch', 'amd64', '--mode', 'pipes', '--kernel',
			os.getenv('VINIX_SERIAL_QA_KERNEL_X86')]
	}
	if rsp != '' {
		build := work + '/rsp-build'
		os.mkdir(build)!
		os.mkdir(build + '/obj')!
		os.mkdir(build + '/source')!
		os.write_file(build + '/obj/mupen64plus-rsp-cxd4_rsp.c.stamp', json2.encode(json2.Any({
			'command': json2.Any([os.executable(), '-c', 'rsp.c', '-o', 'rsp.o'].map(json2.Any(it)))
		})))!
		commands << [rsp, '--build', build]
	}
	for command in commands {
		result := fixturehost.capture_both_preferred(command, env, policyhost.caller_arch())!
		assert result.status == 130, result.stdout + result.stderr
		assert os.ls(scratch)!.len == 0
		pid := os.read_file(work + '/surrogate.pid')!.int()
		assert C.kill(pid, 0) < 0 && C.errno == C.ESRCH
	}
	println('PASS actual controller SIGINT statuses, default scratch retirement and compiler child owners')
}

fn checked() ! {
	check_capture()!
	work_cwd := hosttest.work_dir('', 'vinix-serial-cwd-')!
	defer { hosttest.remove_work_dir(work_cwd) or { eprintln(err.msg()) } }
	directory := work_cwd + '/with space\\bytes'
	os.mkdir(directory)!
	expected_cwd := hosttest.module_resolve(directory)!
	before := os.getwd()
	assert guesthost.boot_abi_from([os.executable(), '--child', 'cwd'], policyhost.environment(),
		work_cwd, 'aarch64', ['cwd:' + expected_cwd, 'CWD: PASS'], 'CWD: PASS', []string{},
		3, false, directory)! == 0
	assert guesthost.boot_from([os.executable(), '--child', 'cwd'], policyhost.environment(),
		work_cwd, ['cwd:' + expected_cwd, 'CWD: PASS'], []string{}, 3, false, directory)! == 0
	assert guesthost.boot_abi_from([os.executable(), '--child', 'cwd'], policyhost.environment(),
		work_cwd, 'aarch64', ['CWD: PASS'], 'CWD: PASS', []string{}, 3, false,
		work_cwd + '/absent')! == 1
	assert os.getwd() == before
	println('PASS child working directory, literal Unix path, failed chdir and unchanged parent cwd')
	assert guesthost.churn_features('directories')! == ['CHURN MEASURE program=mkdir_tmpfs cohort=3 runs=200',
		'CHURN MEASURE program=mkdir_ext2 cohort=3 runs=200']
	assert guesthost.churn_features('exec')!.len == 4
	assert guesthost.churn_features('waits')!.len == 4
	assert guesthost.churn_features('select')!.len == 2
	assert guesthost.memlock_features().len == 8 && guesthost.realtime_features().len == 11
	if os.args.len >= 2 {
		work := hosttest.work_dir('', 'vinix-serial-generator-check-')!
		defer { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } }
		check_producer(os.args[1], work)!
		check_interrupts(os.args[1], if os.args.len >= 3 { os.args[2] } else { '' },
			if os.args.len >= 4 { os.args[3] } else { '' }, work)!
	}
}

fn main() {
	if os.getenv('VINIX_SERIAL_QA_SURROGATE') == '1' {
		if os.args.len == 2 && os.args[1] == 'version' { println('V 0.5.2 native ownership fixture'); return }
		os.write_file(os.getenv('VINIX_SERIAL_QA_PID'), os.getpid().str()) or { panic(err) }
		C.kill(C.getppid(), C.SIGINT)
		for { time.sleep(20 * time.millisecond) }
	}
	if os.args.len >= 3 && os.args[1] == '--child' { child(os.args[2]); return }
	checked() or { eprintln(err.msg()); exit(1) }
}
