// SPDX-License-Identifier: GPL-2.0-only
module main

import fixturehost
import hosttest
import os
import policyhost
import time

#include <signal.h>
#include <unistd.h>
fn C.kill(i32, i32) i32

fn environment() map[string]string {
	mut env := policyhost.environment()
	env['V_MACOS_V3_NO_FALLBACK'] = '1'
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	env['ASAN_OPTIONS'] = 'detect_leaks=0:halt_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	return env
}

fn invoke(argv []string, log string, env map[string]string, timeout int) !fixturehost.CapturedCommand {
	result := fixturehost.capture_bounded(argv, env, policyhost.caller_arch(), '', timeout, unsafe { nil })!
	os.write_file(log, result.stdout + result.stderr)!
	return result
}

fn private_directories(work string, family string) ![]string {
	base := if family == 'hotplug' { work + '/tmp' } else { '/tmp' }
	mut names := os.ls(base)!.filter(it.starts_with('vinix-' + family + '-'))
	names.sort()
	return names
}

fn owners(work string, profile string) ! {
	mut env := environment()
	env['TMPDIR'] = work + '/tmp'
	env['V'] = work + '/missing-compiler'
	for family in ['smc', 'hotplug'] {
		controller := work + '/' + family + '-' + profile
		before := private_directories(work, family)!
		for index in 0 .. 3 {
			assert invoke([controller], work + '/owner-' + family + '-' + profile + '-' + index.str() + '.log', env, 30)!.status == 1
			assert private_directories(work, family)! == before
		}
		for args in [['--bad'], ['--arch', 'aarch64'], ['--host-arch', 'invalid']] {
			assert invoke([controller, ...args], work + '/cli.log', env, 30)!.status == 2
		}
		assert invoke([controller, '--help'], work + '/help.log', env, 30)!.status == 0
		assert invoke([controller, '--state-dir', ''], work + '/empty.log', env, 30)!.status == 1
		state := work + '/retained-' + family + '-' + profile + '-' + time.sys_mono_now().str() + '\\literal\nbytes'
		assert invoke([controller, '--state-dir', state], work + '/retained.log', env, 30)!.status == 1
		assert os.is_dir(state)
		assert private_directories(work, family)! == before
		// Native compiler surrogate: interrupt the public controller, then check
		// its exact direct child and default owner have both retired.
		mut sleeping := environment()
		sleeping['TMPDIR'] = env['TMPDIR']
		sleeping['CC'] = os.executable()
		sleeping['VINIX_MAILBOX_CC_SLEEP'] = '1'
		pidfile := work + '/' + family + '-' + profile + '-' + time.sys_mono_now().str() + '.pid'
		sleeping['VINIX_MAILBOX_PID'] = pidfile
		mut process := os.new_process(controller)
		process.set_environment(sleeping)
		process.set_redirect_stdio()
		process.run()
		defer { process.close() }
		start := time.sys_mono_now()
		for !os.exists(pidfile) {
			if !process.is_alive() || time.sys_mono_now() - start > 120 * u64(time.second) {
				panic('Native compiler surrogate did not start')
			}
			time.sleep(20 * time.millisecond)
		}
		C.kill(process.pid, C.SIGINT)
		for process.is_alive() {
			if time.sys_mono_now() - start > 130 * u64(time.second) {
				C.kill(process.pid, C.SIGKILL)
				process.wait()
				panic('Controller interrupt did not finish')
			}
			time.sleep(20 * time.millisecond)
		}
		assert process.code == 130
		assert C.kill(os.read_file(pidfile)!.int(), 0) == -1
		assert private_directories(work, family)! == before
		println(family + ' ' + profile + ' failure owners, CLI/literal paths and actual SIGINT/direct-child cleanup PASS')
	}
}

fn workflows(work string, profile string) ! {
	arch := if profile == 'x86' { 'amd64' } else { 'arm64' }
	for family in ['smc', 'hotplug'] {
		state := work + '/' + family + '-' + profile + '-host'
		mut argv := [work + '/' + family + '-' + profile, '--host-arch', arch, '--state-dir', state]
		if family == 'hotplug' { argv << ['--original-reference', work + '/hotplug-original.c'] }
		result := invoke(argv, state + '.log', environment(), 300)!
		if family == 'smc' {
			assert result.status == 1 && result.stderr.contains("undeclared function 'memdup'"), result.stderr
			assert os.is_file(state + '/core.o') && os.is_file(state + '/fixture.c')
			println('SMC ' + profile + ' original strict memdup fixture failure retained')
		} else {
			assert result.status == 0 && result.stdout.contains('apple display hotplug state tests passed'), result.stdout + result.stderr
			assert os.is_file(state + '/v/inputs.json') && os.is_file(state + '/c/inputs.json')
			println('Display-hotplug ' + profile + ' independent original/V full result parity PASS')
		}
	}
}

fn cold(work string) ! {
	mut env := environment()
	env['TMPDIR'] = work + '/tmp'
	for family in ['apple_smc', 'apple_display_hotplug'] {
		result := fixturehost.capture_bounded([hosttest.root() + '/tests/' + family + '/run.sh', '--help'],
			env, '', '/tmp', 180, unsafe { nil })!
		assert result.status == 0 && result.stdout.contains('Native V'), result.stdout + result.stderr
		assert os.ls(env['TMPDIR'])!.len == 0
		println(family + ' cold native launcher and owner cleanup PASS')
	}
}

fn main() {
	if os.getenv('VINIX_MAILBOX_CC_SLEEP') == '1' {
		os.write_file(os.getenv('VINIX_MAILBOX_PID'), os.getpid().str()) or { panic(err) }
		for { time.sleep(10 * time.millisecond) }
	}
	assert os.args.len in [3, 4]
	work := os.args[2]
	if !os.is_dir(work + '/tmp') {
		os.mkdir(work + '/tmp') or { if !os.is_dir(work + '/tmp') { panic(err) } }
	}
	match os.args[1] {
		'owners' { owners(work, os.args[3]) or { panic(err) } }
		'host' { workflows(work, os.args[3]) or { panic(err) } }
		'cold' { cold(work) or { panic(err) } }
		else { panic('Expected owners, host or cold') }
	}
}
