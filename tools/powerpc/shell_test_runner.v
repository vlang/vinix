// SPDX-License-Identifier: GPL-2.0-or-later
module main

import net.unix
import os
import time

fn shell_command(mut console unix.StreamConn, log_path string, command string) !string {
	before := os.read_file(log_path)!
	console.write_string(command + '\n')!
	deadline := time.now().add(3 * time.second)
	for time.now() < deadline {
		log := os.read_file(log_path)!
		if log.len < before.len { return error('Console log was truncated') }
		result := log[before.len..].replace('\r', '')
		if result.contains('PANIC') || result.contains('VINIX-PPC: FAIL') {
			return error('Guest failure: ${result}')
		}
		if result.ends_with('vinix$ ') { return result }
		time.sleep(10 * time.millisecond)
	}
	return error('Shell command timed out: ${command}')
}

fn exercise_shell(output string, log_path string) ! {
	mut console := unix.connect_stream(output + '/serial.sock')!
	defer { console.close() or {} }
	mut transcript := ''
	checks := {
		'help':          'help  ls [path]  cat path  pwd  ps  uname  mem  echo text  exit\n'
		'ls':            'bin/\netc/\nREADME\n'
		'ls /bin':       '\ninit\n'
		'ls /etc/':      '\nmotd\n'
		'cat /etc/motd': 'Vinix PowerPC development system\n'
		'pwd':           '\n/\n'
		'ps':            'PID  COMMAND\n1    init (shell)\n'
		'uname':         '\nVinix 0.1-ppc-dev powerpc\n'
		'echo hello':    '\nhello\n'
		'cat /missing':  '\ncat: cannot open file\n'
		'ls /etc/motd':  '\nls: not a directory\n'
		'unknown':       '\nUnknown command. Type help.\n'
		'echo ax\bZ':    '\naZ\n'
	}
	for command, expected in checks {
		result := shell_command(mut console, log_path, command)!
		transcript += result
		os.write_file(output + '/shell-commands.log', transcript)!
		if !result.contains(expected) { return error('Unexpected result for ${command}: ${result}') }
	}
	before := shell_command(mut console, log_path, 'mem')!
	transcript += before
	for _ in 0 .. 32 {
		result := shell_command(mut console, log_path, 'cat /etc/motd')!
		transcript += result
		if !result.contains('Vinix PowerPC development system\n') {
			return error('Repeated open/read/close failed')
		}
	}
	after := shell_command(mut console, log_path, 'mem')!
	transcript += after
	os.write_file(output + '/shell-commands.log', transcript)!
	if !before.contains(' Free KiB: ') || before.all_before(' Uptime seconds: ') != after.all_before(' Uptime seconds: ') {
		return error('Physical memory changed across repeated file operations')
	}
	console.write_string('exit\n')!
	deadline := time.now().add(3 * time.second)
	mut exited := false
	for time.now() < deadline {
		log := os.read_file(log_path)!
		if log.contains('Vinix: init exited, status 0x00000000') {
			exited = true
			break
		}
		time.sleep(10 * time.millisecond)
	}
	if !exited { return error('Shell did not exit successfully') }
	println('PASS interactive userspace shell: commands, errors, editing, repeated open/read/close, stable free pages')
}
