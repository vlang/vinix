// SPDX-License-Identifier: GPL-2.0-or-later
module guesthost

import fixturehost
import hosttest
import json2
import math
import os
import policyhost
import strconv

pub fn rsp_budget_command(arguments []string) int {
	guard := policyhost.own_commands()
	defer { guard.close() }
	result := rsp_budget_checked(arguments) or { return serial_report(err) }
	return result
}

fn rsp_budget_checked(arguments []string) !int {
	parsed := parse(arguments, [hosttest.Option{ name: '--build', value: true },
		hosttest.Option{ name: '--timeout', value: true }], []string{},
		'Usage: rsp-budget [--build HOST-BUILD] [--timeout SECONDS]') or { return SerialArgumentError{err.msg()} }
	timeout := strconv.atof64(parsed.value('--timeout', '3')) or { return SerialArgumentError{'invalid float for --timeout'} }
	if timeout <= 0 || math.is_nan(timeout) || math.is_inf(timeout, 0) { return SerialArgumentError{'timeout must be finite and positive'} }
	build := resolve(parsed.value('--build', root() + '/build/n64-host'))!
	source := build + '/source'
	stamp := build + '/obj/mupen64plus-rsp-cxd4_rsp.c.stamp'
	if !os.is_file(stamp) { return SerialArgumentError{'host RSP build missing; prepare build-support/n64 host output first'} }
	data := json2.decode[json2.Any](os.read_file(stamp)!)!.as_map()
	rows := (data['command'] or { return error('RSP build stamp has no command') }).as_array()
	mut command := []string{}
	for row in rows { if row !is string { return error('RSP build command must contain strings') }; command << row.str() }
	if command.any(it.starts_with('--target=')) { return SerialArgumentError{'--build must point to a native host build'} }
	if command.len == 0 { return error('Empty RSP compile command') }
	compile_at, output_at := command.index('-c'), command.index('-o')
	if compile_at < 0 || output_at < 0 || compile_at + 1 >= command.len || output_at + 1 >= command.len {
		return error('RSP compile command must include -c SOURCE and -o OBJECT')
	}
	work := hosttest.work_dir('', 'vinix-n64-rsp-budget-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err.msg()) } }
	command[compile_at + 1] = source + '/mupen64plus-rsp-cxd4/rsp.c'
	command[output_at + 1] = work + '/rsp.o'
	command.insert(1, '-DDebugMessage=vinix_n64_rsp_fixture_message')
	policyhost.owned_inherited_environment(command, policyhost.environment(), policyhost.caller_arch(), source)!
	mut flags := command[..command.index('-c')].filter(it !in ['-DDebugMessage=vinix_n64_rsp_fixture_message', '-Wno-everything'])
	flags << ['-Wall', '-Wextra', '-Werror', '-fno-strict-aliasing', '-I' + root() + '/build-support/n64']
	flags = flags.map(if it.starts_with('-I./') { '-I' + source + '/' + it[2..] } else { it })
	fixture := work + '/fixture.o'
	compile_module(root() + '/tests/n64/rspbudgetfixture', fixture,
		if policyhost.caller_arch() == 'arm64' { 'aarch64' } else { 'x86_64' }, flags)!
	program := work + '/rsp-budget'
	run([command[0], fixture, work + '/rsp.o', '-o', program])!
	policyhost.command_checkpoint()!
	result := fixturehost.capture_owned_bounded([program], policyhost.environment(), policyhost.caller_arch(),
		'', timeout, policyhost.command_interrupted, true) or {
		if err.msg().starts_with('Command timed out after ') {
			eprintln('N64 RSP FAIL: branch-delay loop did not respect its instruction budget')
			return 1
		}
		return err
	}
	print(result.stdout)
	if result.status != 0 { return 1 }
	if !result.stdout.contains('N64 RSP PASS: branch-delay loop is bounded and a subsequent task runs') {
		eprintln('N64 RSP FAIL: fixture did not report completion')
		return 1
	}
	return 0
}
