// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import plainiso
import tests.packages.winesource

fn invoke(args []string, log string) ! {
	os.write_file(log + '.argv.json', json2.encode(args))!
	hwhost.run_tool(args, map[string]string{}, log, 300)!
}

fn run() ! {
	if os.args.len != 9 { return error('usage: CHECK OUTPUT ARCH KERNEL SYSROOT GCC_INSTALL CLANG V standard|fault|signal|signal-refused|interrupt|caller-interrupt') }
	wanted_outcome := os.args[8]
	if wanted_outcome !in ['standard', 'fault', 'signal', 'signal-refused', 'interrupt', 'caller-interrupt'] { return error('unknown outcome requirement') }
	work := os.abs_path(os.args[1]); arch := os.args[2]
	if arch !in ['aarch64', 'x86_64'] || os.exists(work) || os.is_link(work) { return error('fresh output and supported architecture required') }
	root := os.real_path(os.dir(@FILE) + '/../..')
	probe := root + '/tests/packages/lease-holder-probe.v'
	if winesource.file_digest(probe)! != sha256.hexhash($embed_file('lease-holder-probe.v').to_string())
		|| winesource.file_digest(@FILE)! != sha256.hexhash($embed_file('lease-holder-check.v').to_string()) { return error('compiled sources differ') }
	host := hwhost.find_host(root, arch, '')!
	mut inputs := map[string]string{}
	for path in [@FILE, probe, os.executable(), os.args[3], os.args[6], os.args[7], host.qemu, host.firmware, host.firmware_vars] {
		if path != '' { inputs[path] = winesource.file_digest(path)! }
	}
	os.mkdir_all(work)!
	os.write_file(work + '/expectation.txt', wanted_outcome + '\n')!
	if arch == 'x86_64' {
		for _, path in plainiso.inputs(root)! { inputs[path] = winesource.file_digest(path)! }
	} else {
		loader := os.getenv_opt('VINIX_LIMINE_BOOTAA64') or { root + '/boot-image/limine-bin/BOOTAA64.EFI' }
		inputs[loader] = winesource.file_digest(loader)!
	}
	mut command := [os.args[7], '-backend', 'c', '-prod', '-os', 'linux', '-arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' },
		'-path', '@vlib|' + root + '|@vmodules', '-gc', 'none', '-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-o', work + '/probe.c', probe]
	if wanted_outcome == 'fault' { command.insert(1, ['-d', 'lease_holder_fixture', '-d', 'lease_holder_wait_fault']) }
	if wanted_outcome == 'interrupt' { command.insert(1, ['-d', 'lease_holder_fixture', '-d', 'lease_holder_wait_interrupt']) }
	if wanted_outcome == 'caller-interrupt' { command.insert(1, ['-d', 'lease_holder_fixture', '-d', 'lease_holder_caller_interrupt']) }
	if wanted_outcome in ['signal', 'signal-refused'] { command.insert(1, ['-d', 'lease_holder_fixture', '-d', 'lease_holder_signal_window']) }
	if wanted_outcome == 'signal-refused' { command.insert(1, ['-d', 'lease_holder_keep_handlers']) }
	mut discovery := command.clone(); discovery.insert(1, ['-print-watched-files', '-dump-files', work + '/sources-before.txt'])
	invoke(discovery, work + '/discover.log')!
	winesource.capture(work + '/sources-before.txt', mut inputs)!
	os.write_file(work + '/inputs-before.json', json2.encode(inputs))!
	command.insert(1, ['-dump-files', work + '/sources-built.txt']); invoke(command, work + '/v.log')!
	winesource.admit(work + '/sources-before.txt', work + '/sources-built.txt', inputs)!
	invoke([os.args[6], '--target=' + arch + '-linux-musl', '--sysroot=' + os.args[4], '--gcc-install-dir=' + os.args[5],
		'-fuse-ld=lld', '-static', '-O2', '-w', '-D_GNU_SOURCE', '-fno-stack-protector', work + '/probe.c', '-lm', '-lpthread', '-o', work + '/probe'], work + '/cc.log')!
	mut generated := map[string]string{}
	for path in os.walk_ext(work, '', hidden: true) { if os.is_file(path) { generated[path] = winesource.file_digest(path)! } }
	os.write_file(work + '/generated-before-boot.json', json2.encode(generated))!
	for path, expected in inputs { if winesource.file_digest(path)! != expected { return error('input changed before boot') } }
	boot_host := if arch == 'x86_64' { hwhost.Host{ ...host, root: plainiso.prepare(root, work)! } } else { host }
	marker := if wanted_outcome == 'caller-interrupt' { 'LEASE HOLDER CALLER INTERRUPT PASS real wait EINTR; busy lease; original37; no children' }
		else if wanted_outcome == 'interrupt' { 'LEASE HOLDER INTERRUPT PASS retry EINTR; caller death; lease busy; original37; no children' }
		else if wanted_outcome == 'standard' { 'LEASE HOLDER PASS statuses 37/126/127/143; double-fork setsid; caller death; cancellation; descriptor isolation; setup refusals' }
		else if wanted_outcome == 'fault' { 'LEASE HOLDER FAULT PASS retained lease after wait error and caller death; SIGKILL limitation explicit' }
		else { 'LEASE HOLDER SIGNAL PASS caught handler reset before unmask; pending signal preserves default status' }
	outcome := hwhost.run_scenario(boot_host, hwhost.Scenario{name: 'lease-holder', arches: [arch], ending: .running,
		required: [marker, 'HWTEST PASS lease-holder fixture'], forbidden: ['HWTEST FAIL', 'Kernel panic']},
		hwhost.Run{kernel: os.args[3], guest: work + '/probe', state: work + '/boot', timeout: 90, keep: true})
	os.write_file(work + '/result.json', json2.encode(outcome))!
	for path, expected in inputs { if winesource.file_digest(path)! != expected { return error('input changed after boot') } }
	for path, expected in generated { if winesource.file_digest(path)! != expected { return error('generated artifact changed') } }
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	if outcome.interrupted { return error('lease holder check interrupted') }
	if wanted_outcome == 'signal-refused' {
		if outcome.passed || !outcome.reason.contains('HWTEST FAIL lease-holder: inherited handler ran before exec') { return error('signal control failed at wrong gate: ' + outcome.reason) }
	} else if !outcome.passed { return error('lease holder check failed: ' + outcome.reason) }
	serial := os.read_file(work + '/boot/serial.log')!
	actual_interrupts := serial.count('LEASE HOLDER caller wait EINTR')
	if (wanted_outcome == 'caller-interrupt' && actual_interrupts < 1)
		|| (wanted_outcome != 'caller-interrupt' && actual_interrupts != 0) { return error('real caller wait interruption count differs') }
	if serial.count('LEASE HOLDER injected EINTR') != if wanted_outcome == 'interrupt' { 1 } else { 0 } { return error('unexpected EINTR injection count') }
	if wanted_outcome == 'standard' && !serial.contains('LEASE HOLDER CHURN PASS 64 descendants; final adopted survivor retains lease; original37; no children') {
		return error('descendant churn qualification missing')
	}
	if wanted_outcome == 'standard' && !serial.contains('LEASE HOLDER CONCURRENT PASS independent leases and statuses; unrelated child waitable') {
		return error('concurrent holder qualification missing')
	}
	if wanted_outcome == 'standard' && !serial.contains('LEASE HOLDER CONCURRENT DEATH PASS caller SIGKILL; adopted holder37; independent caller126; unrelated child97') {
		return error('concurrent caller-death qualification missing')
	}
	if serial.count('Generation lease holder cannot collect children; retaining lease and retrying.') != if wanted_outcome == 'fault' { 1 } else { 0 } { return error('unexpected wait-failure diagnostic count') }
	println('LEASE HOLDER CHECK PASS ' + arch + ' ' + wanted_outcome)
}
fn main() {
	if plainiso.requested() { plainiso.build() or { eprintln(err); exit(1) }; return }
	run() or { eprintln(err); exit(1) }
}
