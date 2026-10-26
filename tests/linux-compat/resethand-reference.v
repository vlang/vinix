// SPDX-License-Identifier: GPL-2.0-or-later
// Boot the unchanged native resethand probe ELF against a supplied Linux kernel.
module main

import crypto.sha256
import guesthost
import hosttest
import json2
import os

struct ReferenceReceipt {
	architecture  string
	context       string = 'Linux QEMU reference; same native musl probe ELF; semantic checks only'
	launcher_mode string
	artifacts     map[string]string
	command       []string
	passed        bool
	finished      bool
	forced        bool
	status        int
}

fn digest(path string) string { return sha256.sum(os.read_bytes(path) or { panic(err) }).hex() }

fn entry(mut archive []u8, name string, mode u32, inode u32, data []u8, major u32, minor u32) {
	mut header := '070701'
	for value in [inode, mode, u32(0), 0, 1, 0, u32(data.len), 0, 0, major, minor, u32(name.len + 1),
		0]! {
		header += '${value:08x}'
	}
	archive << header.bytes()
	archive << name.bytes()
	archive << u8(0)
	for archive.len % 4 != 0 { archive << u8(0) }
	archive << data
	for archive.len % 4 != 0 { archive << u8(0) }
}

fn case_lines() []string {
 mut result := []string{}
 for ordinary in 0 .. 2 { for signal in [10, 12, 28] { for mode in 0 .. 4 {
  result << 'LINUX RESETHAND CASE: uid=' + if ordinary == 0 { '0 gid=0' } else { '1000 gid=2000' }
   + ' signal=' + signal.str() + ' mode=' + mode.str() + ' checks=' + if mode == 3 { '19' } else { '17' } + ' failures=0'
 } } }
 return result
}
fn verify(text string, arch string) ! {
 if arch !in ['aarch64', 'x86_64'] || !text.contains('Linux version ') { return error('Reference architecture or Linux boot missing') }
 for bad in ['LINUX RESETHAND FAIL', 'LINUX RESETHAND: FAIL', 'LINUX RESETHAND MISMATCH', 'REFERENCE FAIL', 'Kernel panic', 'BUG:'] {
  if text.contains(bad) { return error('Reference failure: ' + bad) }
 }
 mut expected := case_lines()
 expected << ['LINUX RESETHAND: PASS', 'LINUX RESETHAND SUMMARY: checks=420 failures=0']
 mut counts := map[string]int{}
 for raw in text.split_into_lines() {
  line := raw.trim_space()
  if line.starts_with('LINUX RESETHAND CASE:') || line.starts_with('LINUX RESETHAND SUMMARY:') {
   if line !in expected { return error('Unexpected reference case or summary: ' + line) }
  }
  counts[line]++
 }
 for line in expected { if counts[line] != 1 { return error('Missing or repeated result: ' + line) } }
}
fn controls() ! {
 good := 'Linux version control\n' + case_lines().join('\n') + '\nLINUX RESETHAND: PASS\nLINUX RESETHAND SUMMARY: checks=420 failures=0\n'
 for arch in ['aarch64', 'x86_64'] { verify(good, arch)! }
 mut bad := []string{}
 for line in good.split_into_lines().filter(it != '') { bad << good.replace(line + '\n', '') }
 bad << good.replace('checks=420', 'checks=419')
 bad << good.replace('checks=17', 'checks=16')
 bad << good.replace('mode=3', 'mode=2')
 bad << good.replace('uid=1000 gid=2000', 'uid=0 gid=0')
 bad << good + 'LINUX RESETHAND: PASS\n'
 bad << good + 'LINUX RESETHAND MISMATCH injected\n'
 bad << good + 'Kernel panic injected\n'
 mut refused := 0
 for candidate in bad { verify(candidate, 'aarch64') or { refused++; continue }; return error('Negative control accepted') }
 verify(good, 'invalid') or { refused++ }
 assert refused == bad.len + 1
 println('One-shot signal action reference parser controls: PASS (2 positive, ' + refused.str() + ' negative)')
}

fn run() ! {
	options := guesthost.parse(os.args[1..], [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--kernel', value: true },
		hosttest.Option{ name: '--init', value: true },
		hosttest.Option{ name: '--launcher', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
	], [], 'Usage: resethand-reference.v --arch aarch64|x86_64 --kernel LINUX --init NATIVE-PROBE-ELF [--launcher REFERENCE-INIT-ELF] --state-dir FRESH-DIR')!
	for key in ['--arch', '--kernel', '--init', '--state-dir'] {
		if !options.has(key) { return error('missing ' + key) }
	}
	arch := options.value('--arch', '')
	state := options.value('--state-dir', '')
	if os.exists(state) { return error('state directory must be fresh') }
	os.mkdir_all(state)!
	work := os.real_path(state)
	init := options.value('--init', '')
	probe := os.read_bytes(init)!
	machine := if probe.len >= 20 { int(probe[18]) + (int(probe[19]) << 8) } else { 0 }
	if probe.len < 20 || probe[..6] != [u8(127), `E`, `L`, `F`, 2, 1] || machine != if arch == 'aarch64' {
		183
	} else {
		62
	} {
		return error('probe must be a matching little-endian ELF64')
	}
	os.write_file_array(work + '/probe', probe)!
	os.write_file_array(work + '/linux', os.read_bytes(options.value('--kernel', ''))!)!
	wrapper := os.dir(@FILE) + '/resethandreferenceinit/core.v'
	os.mkdir_all(work + '/source/resethandreferenceinit')!
	os.write_file(work + '/source/resethandreferenceinit/core.v', os.read_file(wrapper)!)!
	launcher := if options.has('--launcher') {
		bytes := os.read_bytes(options.value('--launcher', ''))!
		if bytes.len < 20 || bytes[..6] != [u8(127), `E`, `L`, `F`, 2, 1]
			|| int(bytes[18]) + (int(bytes[19]) << 8) != machine {
			return error('launcher must be a matching little-endian ELF64')
		}
		os.write_file_array(work + '/init', bytes)!
		work + '/init'
	} else {
		guesthost.compile_init(work + '/source/resethandreferenceinit/core.v', work, arch, false)!
	}
	mut archive := []u8{}
	for index, directory in ['.', 'dev', 'tmp', 'sbin', 'proc'] {
		entry(mut archive, directory, 0o040755, u32(index + 1), []u8{}, 0, 0)
	}
	entry(mut archive, 'dev/console', 0o020600, 10, []u8{}, 5, 1)
	entry(mut archive, 'dev/null', 0o020666, 11, []u8{}, 1, 3)
	entry(mut archive, 'sbin/probe', 0o100755, 12, os.read_bytes(work + '/probe')!, 0, 0)
	entry(mut archive, 'init', 0o100755, 13, os.read_bytes(launcher)!, 0, 0)
	entry(mut archive, 'TRAILER!!!', 0, 14, []u8{}, 0, 0)
	os.write_file_array(work + '/initramfs.cpio', archive)!
	mut command := if arch == 'aarch64' {
		['qemu-system-aarch64', '-machine', 'virt', '-accel', 'hvf', '-cpu', 'host']
	} else {
		['qemu-system-x86_64', '-machine', 'q35', '-accel', 'tcg', '-cpu', 'max']
	}
	command[0] = os.find_abs_path_of_executable(command[0])!
	command << ['-m', '512', '-smp', '2', '-kernel', work + '/linux', '-initrd',
		work + '/initramfs.cpio', '-append', if arch == 'aarch64' {
			'console=ttyAMA0 rdinit=/init panic=-1'
		} else {
			'console=ttyS0 rdinit=/init panic=-1'
		}, '-display', 'none', '-serial', 'mon:stdio', '-no-reboot']
	mut inputs := map[string]string{}
	for path in [work + '/linux', work + '/probe', launcher, work + '/initramfs.cpio',
		work + '/source/resethandreferenceinit/core.v', @FILE, os.executable(), command[0]] {
		inputs[path] = digest(path)
	}
	os.write_file(work + '/inputs.json', json2.encode(inputs, prettify: true) + '\n')!
	os.write_file(work + '/command.json', json2.encode(command, prettify: true) + '\n')!
	result := guesthost.boot_session(command, os.environ(), work, guesthost.SessionPolicy{
		pass:     'LINUX RESETHAND: PASS'
		failures: [
			'LINUX RESETHAND FAIL',
			'LINUX RESETHAND: FAIL',
			'LINUX RESETHAND MISMATCH',
			'LINUX RESETHAND REFERENCE FAIL',
			'Kernel panic',
		]
		settle:   1
		log:      work + '/live.log'
	}, 600, true)!
	mut artifacts := {
		'kernel':            digest(work + '/linux')
		'probe':             digest(work + '/probe')
		'wrapper_source':    digest(work + '/source/resethandreferenceinit/core.v')
		'wrapper_elf':       digest(launcher)
		'initramfs':         digest(work + '/initramfs.cpio')
		'serial':            digest(work + '/serial.log')
		'controller_source': digest(@FILE)
	}
	if !options.has('--launcher') {
		artifacts['wrapper_c'] = digest(work + '/fixture.c')
		artifacts['serial_adapter_c'] = digest(work + '/serial.c')
	}
	artifacts['qemu'] = digest(command[0])
	mut reason := ''
	verify(result.text, arch) or { reason = err.msg() }
	for path, expected in inputs {
		if digest(path) != expected { reason = 'Reference input changed: ' + path }
	}
	valid := reason == '' && result.finished && result.passed && result.status == 0
	os.write_file(work + '/receipt.json', json2.encode(ReferenceReceipt{ architecture: arch, launcher_mode: if options.has('--launcher') {
		'supplied ELF; wrapper source recorded separately'
	} else {
		'compiled recorded wrapper source'
	}, artifacts: artifacts, command: command, passed: valid, finished: result.finished, forced: result.forced, status: result.status },
		prettify: true
	) + '\n')!
	os.write_file(work + '/status', if valid { '0\n' } else { '1\n' })!
	if !valid { return error(if reason != '' { reason } else { 'Linux reference session failed' }) }
	println('Linux resethand reference: PASS')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		controls() or {
			eprintln(err.msg())
			exit(1)
		}
		return
	}
	run() or {
		eprintln(err.msg())
		exit(1)
	}
}
