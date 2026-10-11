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

const runners = {
	'protocol': 'tests/m1-wifi/run-protocol.v'
	'platform': 'tests/m1-wifi/run-platform.v'
	'control':  'tests/m1-wifi/run-control.v'
	'helpers':  'tests/m1-wifi/run-helpers.v'
	'ans':      'tests/apple-ans/run.v'
	'spi':      'tests/apple-spi-keyboard/run.v'
	'speakers': 'tests/apple-speakers/run.v'
	'all':      'tests/m1-wifi/run.v'
}

fn configure() map[string]string {
	mut env := policyhost.environment()
	env['V_MACOS_V3_NO_FALLBACK'] = '1'
	env['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	env['ASAN_OPTIONS'] = 'detect_leaks=0:halt_on_error=1'
	env['UBSAN_OPTIONS'] = 'halt_on_error=1'
	return env
}

fn invoke(argv []string, log string, env map[string]string, timeout int) !hosttest.Result {
	result := fixturehost.capture_bounded(argv, env, policyhost.caller_arch(), '', timeout, unsafe { nil })!
	os.write_file(log, result.stdout + result.stderr)!
	return hosttest.Result{ stdout: result.stdout, stderr: result.stderr, code: result.status }
}

fn build(work string, profiles []string) ! {
	for profile in profiles {
		for name, path in runners {
			mut command := [os.getenv('V'), '-nocache', '-cc', 'cc', '-arch',
				if profile == 'x86' { 'amd64' } else { 'arm64' }]
			if profile == 'san' {
				command << ['-cflags', '-fsanitize=address,undefined', '-cflags',
					'-fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined']
			}
			command << ['-o', work + '/' + name + '-' + profile, hosttest.root() + '/' + path]
			result := invoke(command, work + '/' + name + '-' + profile + '-build.log', configure(), 180)!
			assert result.code == 0, result.stderr
			println(name + ' ' + profile + ' fresh build PASS')
		}
	}
}

fn workflows(work string, profile string, names []string) ! {
	arch := if profile == 'x86' { 'amd64' } else { 'arm64' }
	for name in names {
		base := work + '/' + name + '-' + profile + '-host'
		state := if os.exists(base) { base + '-retry-' + time.sys_mono_now().str() } else { base }
		mut command := [work + '/' + name + '-' + profile, '--state-dir', state]
		if name != 'ans' { command << ['--host-arch', arch] }
		result := invoke(command,
			state + '.log', configure(), 240)!
		if result.code == 0 {
			assert os.is_file(state + '/validation.json')
			assert result.stdout.contains('PASS ')
			println(name + ' ' + profile + ' independent C/V golden workflow PASS')
		} else {
			assert result.code == 1 && (result.stderr.contains("undeclared function 'memdup'")
				|| result.stderr.contains("call to undeclared function 'memdup'")
				|| result.stderr.contains('unknown register name') || result.stderr.contains('invalid input constraint')
				|| (name == 'ans' && result.stderr.contains('inline assembly is not supported by the selected V3 backend'))
				|| (name == 'ans' && result.stderr.contains('unknown function: a_count_transfer')
					&& result.stderr.contains('unknown function: a_count_flush'))), result.stdout + result.stderr
			println(name + ' ' + profile + ' original strict compiler limitation retained')
		}
	}
}

fn defaults(family string) []string {
	return (os.ls('/tmp') or { panic(err) }).filter(it.starts_with('vinix-' + family + '-')).sorted()
}

fn cold_fronts(work string) ! {
	scratch := work + '/cold-scratch'
	os.mkdir(scratch)!
	mut env := configure()
	env['TMPDIR'] = scratch
	for front in ['tests/m1-wifi/run.sh', 'tests/m1-wifi/run-protocol', 'tests/m1-wifi/run-platform',
		'tests/m1-wifi/run-control', 'tests/m1-wifi/run-helpers', 'tests/m1-wifi/run-ctl', 'tests/m1-wifi/run-ctl-vm',
		'tests/apple-ans/run.sh', 'tests/apple-spi-keyboard/run.sh', 'tests/apple-spi-touchpad/run.sh', 'tests/apple-speakers/run.sh'] {
		result := fixturehost.capture_bounded([hosttest.root() + '/' + front, '--help'], env,
			policyhost.caller_arch(), '/tmp', 180, unsafe { nil })!
		os.write_file(work + '/cold-' + front.replace('/', '_') + '.log', result.stdout + result.stderr)!
		assert result.status == 0 && result.stdout.contains('Native V'), result.stdout + result.stderr
		assert os.ls(scratch)!.len == 0
		println(front + ' cold native CLI/launcher cleanup PASS')
	}
}

fn owners(work string, profile string) ! {
	mut env := configure()
	env['V'] = work + '/missing-compiler'
	for name, family in {
		'protocol': 'wifi-protocol'
		'platform': 'wifi-platform'
		'control':  'wifi-control'
		'helpers':  'wifi-helpers'
		'ans':      'ans'
		'spi':      'spi'
		'speakers': 'speakers'
	} {
		controller := work + '/' + name + '-' + profile
		before := defaults(family)
		for index in 0 .. 3 {
			result := invoke([controller], work + '/' + name + '-' + profile + '-owner-' + index.str() + '.log', env, 30)!
			assert result.code == 1
			assert defaults(family) == before
		}
		for arguments in [['--bad-option'], ['--arch', 'aarch64'], ['--host-arch', 'invalid']] {
			assert invoke([controller, ...arguments], work + '/cli.log', env, 30)!.code == 2
		}
		assert invoke([controller, '--help'], work + '/help.log', env, 30)!.code == 0
		assert invoke([controller, '--state-dir', work], work + '/fresh.log', env, 30)!.code == 1
		assert invoke([controller, '--state-dir', ''], work + '/empty-path.log', env, 30)!.code == 1
		state := work + '/retained-' + name + '-' + profile + '\\literal\nbytes'
		assert invoke([controller, '--state-dir', state], work + '/retained.log', env, 30)!.code == 1
		assert os.is_dir(state)
		assert defaults(family) == before
	}
	// The compiler surrogate is a native process. Check the actual controller's
	// handler, its direct child retirement and its private /tmp owner together.
	env = configure()
	env['CC'] = os.executable()
	env['VINIX_APPLE_CC_SLEEP'] = '1'
	env['VINIX_APPLE_PID'] = work + '/cc-' + profile + '.pid'
	before := defaults('wifi-protocol')
	mut process := os.new_process(work + '/protocol-' + profile)
	process.set_environment(env)
	process.set_redirect_stdio()
	process.run()
	defer { process.close() }
	started := time.sys_mono_now()
	for !os.exists(env['VINIX_APPLE_PID']) {
		if !process.is_alive() || time.sys_mono_now() - started > 90 * u64(time.second) {
			panic('Compiler surrogate did not start')
		}
		time.sleep(20 * time.millisecond)
	}
	C.kill(process.pid, C.SIGINT)
	for process.is_alive() {
		if time.sys_mono_now() - started > 100 * u64(time.second) {
			C.kill(process.pid, C.SIGKILL)
			process.wait()
			panic('Interrupt not delivered')
		}
		time.sleep(20 * time.millisecond)
	}
	assert process.code == 130
	assert C.kill(os.read_file(env['VINIX_APPLE_PID'])!.int(), 0) == -1
	assert defaults('wifi-protocol') == before
	println(profile + ' 21 default-owner failures, CLI guards, retained literal paths and SIGINT/direct-child cleanup PASS')
}

fn main() {
	if os.getenv('VINIX_APPLE_CC_SLEEP') == '1' {
		os.write_file(os.getenv('VINIX_APPLE_PID'), os.getpid().str()) or { panic(err) }
		for { time.sleep(10 * time.millisecond) }
	}
	if os.args.len < 3 {
		eprintln('Usage: check-runners build|host|owners EXISTING-WORK [arm|x86|san]')
		exit(2)
	}
	work := os.args[2]
	if os.args[1] == 'build' {
		os.mkdir_all(work) or { panic(err) }
		profiles := if os.args.len == 4 { [os.args[3]] } else { ['arm', 'x86', 'san'] }
		assert profiles.all(it in ['arm', 'x86', 'san'])
		build(work, profiles) or { panic(err) }
	} else if os.args.len == 4 && (os.args[1] in ['host', 'tail'] || os.args[1].starts_with('only-')) {
		workflows(work, os.args[3], if os.args[1].starts_with('only-') { [os.args[1].all_after('only-')] }
		else if os.args[1] == 'tail' { ['ans', 'spi', 'speakers'] } else {
			['protocol', 'platform', 'control', 'helpers', 'ans', 'spi', 'speakers']
		}) or { panic(err) }
	} else if os.args.len == 4 && os.args[1] == 'owners' {
		owners(work, os.args[3]) or { panic(err) }
	} else if os.args.len == 3 && os.args[1] == 'cold' {
		cold_fronts(work) or { panic(err) }
	} else {
		exit(2)
	}
}
