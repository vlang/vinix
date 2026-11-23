// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import guesthost
import hosttest
import json2
import os
import strconv

struct PressureReceipt {
	architecture string
	platform     string
	command      []string
	artifacts    map[string]string
	samples      [3]int
	passed       bool
}

fn digest(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn pressure_command(base []string) []string {
	mut command := base.clone()
	command[command.index('-m') + 1] = '1280'
	command[command.index('-smp') + 1] = '4'
	command << ['-object', 'memory-backend-ram,id=vinix-numa0,size=1024M', '-object',
		'memory-backend-ram,id=vinix-numa1,size=128M', '-object',
		'memory-backend-ram,id=vinix-numa2,size=128M', '-numa', 'node,nodeid=0,cpus=0-1,memdev=vinix-numa0',
		'-numa', 'node,nodeid=1,cpus=2,memdev=vinix-numa1', '-numa', 'node,nodeid=2,cpus=3,memdev=vinix-numa2',
		'-numa', 'dist,src=0,dst=1,val=20', '-numa', 'dist,src=0,dst=2,val=30', '-numa', 'dist,src=1,dst=2,val=20']
	return command
}

fn placement(text string) ![3]int {
	const_marker := 'LINUX PREFMANY PRESSURE: '
	lines := text.split_into_lines().filter(it.starts_with(const_marker))
	if lines.len != 1 { return error('expected one pressure summary') }
	fields := lines[0][const_marker.len..].fields()
	if fields.len != 3 { return error('expected three NUMA sample counts') }
	mut counts := [3]int{}
	for node, field in fields {
		name := 'node${node}='
		if !field.starts_with(name) { return error('unexpected pressure summary field ' + field) }
		counts[node] = strconv.atoi(field[name.len..])!
	}
	if counts.any(it <= 0) || counts[0] + counts[1] + counts[2] != 320 {
		return error('expected pages on both preferred nodes and the fallback node')
	}
	return counts
}

fn run() ! {
	options := guesthost.parse(os.args[1..], [
		hosttest.Option{ name: '--arch', value: true, choices: ['aarch64', 'x86_64'] },
		hosttest.Option{ name: '--platform', value: true, choices: ['vinix', 'linux'] },
		hosttest.Option{ name: '--input-dir', value: true },
		hosttest.Option{ name: '--state-dir', value: true },
	], [], 'Usage: prefmany-numa.v --arch ARCH --platform vinix|linux --input-dir PREVIOUS-RUN --state-dir FRESH-DIR')!
	for key in ['--arch', '--platform', '--input-dir', '--state-dir'] {
		if !options.has(key) { return error('missing ' + key) }
	}
	arch := options.value('--arch', '')
	platform := options.value('--platform', '')
	input := os.real_path(options.value('--input-dir', ''))
	state := os.real_path(options.value('--state-dir', ''))
	os.mkdir(state)!
	reference := platform == 'linux'
	init := input + if reference { '/probe' } else { '/prefmany/init' }
	kernel := input + if reference { '/linux' } else { '/kernel/bin/vinix' }
	archive := input + if reference { '/initramfs.cpio' } else { '/prefmany/initramfs.tar' }
	mut hashes := {
		'probe':     digest(init)!
		'kernel':    digest(kernel)!
		'initramfs': digest(archive)!
	}
	mut environment := os.environ()
	mut base := []string{}
	if reference {
		base = if arch == 'aarch64' {
			['qemu-system-aarch64', '-machine', 'virt', '-accel', 'hvf', '-cpu', 'host']
		} else {
			['qemu-system-x86_64', '-machine', 'q35', '-accel', 'tcg', '-cpu', 'max']
		}
		base[0] = os.find_abs_path_of_executable(base[0])!
		base << ['-m', '1280', '-smp', '4', '-kernel', kernel, '-initrd', archive, '-append',
			if arch == 'aarch64' { 'console=ttyAMA0 rdinit=/init panic=-1 numa_balancing=disable' }
			else { 'console=ttyS0 rdinit=/init panic=-1 numa_balancing=disable' },
			'-display', 'none', '-serial', 'mon:stdio', '-no-reboot', '-nic', 'none']
	} else {
		launch := guesthost.launch(init, archive, state, input + '/kernel', arch, true)!
		base = launch.command
		environment = launch.env
		hashes['iso'] = digest(state + '/test.iso')!
	}
	command := pressure_command(base)
	pass := if reference { 'LINUX PREFMANY REFERENCE: PASS' } else { 'LINUX PREFMANY: PASS' }
	result := guesthost.boot_session(command, environment, state, guesthost.SessionPolicy{
		pass: pass
		failures: ['LINUX PREFMANY FAIL', 'LINUX REFERENCE FAIL', 'KERNEL PANIC', 'Kernel panic']
		settle: 1
		monitor_at_marker: true
		log: state + '/live.log'
	}, 300, true)!
	if !result.finished || !result.passed || result.status != 0 {
		return error('NUMA guest failed or timed out')
	}
	counts := placement(result.text)!
	hashes['serial'] = digest(state + '/serial.log')!
	os.write_file(state + '/receipt.json', json2.encode(PressureReceipt{
		architecture: arch
		platform: platform
		command: command
		artifacts: hashes
		samples: counts
		passed: true
	}) + '\n')!
	println('Preferred-many NUMA placement and fallback passed on ${platform} ${arch}')
}

fn main() {
	run() or { eprintln(err.msg()); exit(1) }
}
