// SPDX-License-Identifier: GPL-2.0-or-later
module main

import net.unix
import os
import time

fn shell_command(mut console unix.StreamConn, log_path string, command string) !string {
	before := os.read_file(log_path)!
	console.write_string(command + '\n')!
	deadline := time.now().add(20 * time.second)
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

fn audio_with_keyboard(mut child os.Process, mut console unix.StreamConn, log_path string) !string {
	before := os.read_file(log_path)!
	console.write_string('tone\n')!
	time.sleep(80 * time.millisecond)
	for key in ['e', 'c', 'h', 'o', 'spc', 'o', 'k', 'ret'] {
		child.stdin_write('sendkey ${key} 20\n')
		time.sleep(60 * time.millisecond)
	}
	deadline := time.now().add(4 * time.second)
	for time.now() < deadline {
		log := os.read_file(log_path)!
		if log.len < before.len { return error('Console log truncated') }
		result := log[before.len..].replace('\r', '')
		if result.contains('audio: played 48000 stereo frames') && result.contains('\nok\nvinix$ ') { return result }
		time.sleep(10 * time.millisecond)
	}
	return error('USB keyboard stopped responding during audio playback')
}

fn exercise_shell(mut child os.Process, output string, log_path string) ! {
	mut console := unix.connect_stream(output + '/serial.sock')!
	defer { console.close() or {} }
	mut transcript := ''
	checks := {
		'help':          'help  ls [path]  cat path  pwd  ps  uname  mem  net  ping [IPv4]  tone  echo text  exit\n'
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
	transcript += audio_with_keyboard(mut child, mut console, log_path)!
	sound := shell_command(mut console, log_path, 'tone')!
	transcript += sound
	if !sound.contains('audio: played 48000 stereo frames') { return error('USB audio failed: ${sound}') }
	network := shell_command(mut console, log_path, 'net')!
	transcript += network
	if !network.contains('DHCP: 10.0.2.15 gateway 10.0.2.2') { return error('GEM DHCP failed: ${network}') }
	for _ in 0 .. 16 {
		ping := shell_command(mut console, log_path, 'ping 10.0.2.2')!
		transcript += ping
		if !ping.contains('ping: 4/4 replies from 10.0.2.2') { return error('GEM ping failed: ${ping}') }
	}
	child.stdin_write('set_link net0 off\n')
	time.sleep(100 * time.millisecond)
	down := shell_command(mut console, log_path, 'net')!
	transcript += down
	if !down.contains('net: link down') { return error('GEM failed to report link loss: ${down}') }
	child.stdin_write('set_link net0 on\n')
	time.sleep(100 * time.millisecond)
	recovered := shell_command(mut console, log_path, 'ping')!
	transcript += recovered
	if !recovered.contains('ping: 4/4 replies from 10.0.2.2') { return error('GEM failed link recovery: ${recovered}') }
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
	println('PASS interactive userspace shell: commands, errors, editing, DHCP, 64 ICMP replies across DMA ring wraps, stable free pages')
}
