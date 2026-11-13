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
	if os.args.len !in [8, 9] { return error('usage: CHECK OUTPUT ARCH KERNEL SYSROOT GCC_INSTALL CLANG V [standard|signal]') }
	mode := if os.args.len == 9 { os.args[8] } else { 'standard' }
	if mode !in ['standard', 'signal'] { return error('unsupported child control') }
	work := os.abs_path(os.args[1]); arch := os.args[2]
	if arch !in ['aarch64', 'x86_64'] || os.exists(work) || os.is_link(work) { return error('fresh output and supported architecture required') }
	root := os.real_path(os.dir(@FILE) + '/../..')
	probe := root + '/tests/packages/wine-client-handoff-probe.v'
	if winesource.file_digest(probe)! != sha256.hexhash($embed_file('wine-client-handoff-probe.v').to_string())
		|| winesource.file_digest(@FILE)! != sha256.hexhash($embed_file('wine-client-handoff-check.v').to_string()) { return error('compiled sources differ') }
	host := hwhost.find_host(root, arch, '')!
	mut inputs := map[string]string{}
	for path in [@FILE, probe, root + '/desktop/tools/tests/heap_tracker.h', os.executable(), os.args[3], os.args[6], os.args[7], host.qemu, host.firmware, host.firmware_vars] {
		if path != '' { inputs[path] = winesource.file_digest(path)! }
	}
	os.mkdir_all(work)!
	if arch == 'x86_64' {
		for _, path in plainiso.inputs(root)! { inputs[path] = winesource.file_digest(path)! }
	} else {
		loader := os.getenv_opt('VINIX_LIMINE_BOOTAA64') or { root + '/boot-image/limine-bin/BOOTAA64.EFI' }
		inputs[loader] = winesource.file_digest(loader)!
	}
	mut command := [os.args[7], '-backend', 'c', '-prod', '-os', 'linux', '-arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' },
		'-path', '@vlib|' + root + '|@vmodules', '-gc', 'none', '-manualfree', '-d', 'track_heap', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-o', work + '/probe.c', probe]
	if mode != 'standard' {
		define := 'wine_client_signal_window'
		command.insert(1, ['-d', define])
	}
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
	marker := if mode == 'signal' { 'WINE CLIENT HANDOFF SIGNAL PASS' }
		else { 'WINE CLIENT HANDOFF PASS consumed socket; explicit environment; protocol preserved; exec failure; 100 cycles' }
	mut required := [marker, 'HWTEST PASS wine-client-handoff fixture']
	if mode == 'standard' { required << 'WINE CLIENT CWD PASS captured directory; relative access; replacement; invalid descriptors; parent isolation; 100 cycles' }
	outcome := hwhost.run_scenario(boot_host, hwhost.Scenario{name: 'wine-client-handoff', arches: [arch], ending: .running,
		required: required,
		forbidden: ['HWTEST FAIL', 'Kernel panic']},
		hwhost.Run{kernel: os.args[3], guest: work + '/probe', state: work + '/boot', timeout: 90, keep: true})
	os.write_file(work + '/result.json', json2.encode(outcome))!
	for path, expected in inputs { if winesource.file_digest(path)! != expected { return error('input changed after boot') } }
	for path, expected in generated { if winesource.file_digest(path)! != expected { return error('generated artifact changed') } }
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	if outcome.interrupted || !outcome.passed { return error('Wine client handoff check failed: ' + outcome.reason) }
	println('WINE CLIENT HANDOFF CHECK PASS ' + arch)
}
fn main() {
	if plainiso.requested() { plainiso.build() or { eprintln(err); exit(1) }; return }
	run() or { eprintln(err); exit(1) }
}
