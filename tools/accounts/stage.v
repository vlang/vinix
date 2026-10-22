// SPDX-License-Identifier: GPL-2.0-or-later
// Stage the account service used by the ordinary graphical login path.
module main

import json2
import os
import stagecore

fn invoke(program string, arguments []string) ! {
	mut child := os.new_process(program)
	defer { child.close() }
	child.set_args(arguments)
	child.wait()
	if child.code != 0 { return error('${program} failed (${child.code})') }
}

fn stage() ! {
	mut architecture := ''
	mut staging := ''
	mut cc := []string{}
	mut include_session := false
	mut index := 1
	for index < os.args.len {
		if os.args[index] == '--include-session' { include_session = true; index++; continue }
		if index + 1 == os.args.len { return error('missing staging option value') }
		match os.args[index] {
			'--arch' { architecture = os.args[index + 1] }
			'--staging' { staging = os.abs_path(os.args[index + 1]) }
			'--cc-argv' { cc = json2.decode[[]string](os.args[index + 1])! }
			else { return error('unknown account staging option: ' + os.args[index]) }
		}
		index += 2
	}
	if architecture !in ['aarch64', 'x86_64'] || staging == '' || staging == '/' || !os.is_dir(staging) {
		return error('use --arch aarch64|x86_64 --staging EXISTING_ROOT [--cc-argv JSON] [--include-session]')
	}
	mut installer := stagecore.open(staging)!
	defer { installer.close() }
	if cc.len == 0 { cc = [architecture + '-linux-musl-gcc'] }
	compiler := os.find_abs_path_of_executable(cc[0])!
	configured_v := os.getenv('V')
	v := os.find_abs_path_of_executable(if configured_v == '' { 'v' } else { configured_v })!
	repository := os.dir(os.dir(os.dir(@FILE)))
	work := os.join_path(os.temp_dir(), 'vinix-accounts-${os.getpid()}')
	os.mkdir(work, mode: 0o700)!
	defer { os.rmdir_all(work) or {} }
	mut programs := ['authd', 'account', 'system', 'auth']
	if include_session { programs << 'session' }
	for program in programs {
		installer.check()!
		source := work + '/' + program + '.c'
		binary := work + '/' + program
		invoke(v, ['-new-compiler', '-enable-globals', '-path', '@vlib|@vmodules|' + repository + '|' + repository + '/tools/accounts',
			'-gc', 'none', '-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-os', 'linux',
			'-arch', if architecture == 'aarch64' { 'arm64' } else { 'amd64' }, '-o', source,
			repository + '/tools/accounts/' + program + '.v'])!
		invoke(compiler, [...cc[1..], '-static', '-O2', '-std=gnu11', '-D_GNU_SOURCE', source,
			'-o', binary, '-lm', '-lpthread'])!
		header := os.read_bytes(binary)!
		if header.len < 20 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
			|| int(header[18]) + (int(header[19]) << 8) != if architecture == 'aarch64' { 183 } else { 62 } {
			return error('compiler produced a wrong-architecture account executable')
		}
		installer.put(binary, 'usr/' + if program == 'auth' { 'bin' } else { 'sbin' } + '/vinix-' + program, 0o755)!
	}
	for action in os.ls(repository + '/tools/accounts/actions')! {
		installer.put(repository + '/tools/accounts/actions/' + action,
			'usr/share/vinix/actions/' + action, 0o644)!
	}
	println('Staged account authentication and graphical login support (${architecture})')
}

fn main() {
	stage() or { eprintln('account staging: ${err}'); exit(1) }
}
