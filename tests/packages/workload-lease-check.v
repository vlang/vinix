// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import json2
import crypto.sha256
import hwhost
import plainiso
import tests.packages.winesource

fn invoke(args []string, log string) ! {
	os.write_file(log + '.argv.json', json2.encode(args))!
	hwhost.run_tool(args, map[string]string{}, log, 300)!
}
fn snapshot(text string) !map[string]u64 {
	mut values := map[string]u64{}
	for line in text.split_into_lines() {
		fields := line.fields()
		if fields.len == 4 && fields[0].starts_with('size-') { values[fields[0]] = fields[2].u64() }
		if fields.len == 4 && fields[0] == 'large' { values['large-pages'] = fields[3].u64() }
		if line.starts_with('# written after free ') { values['written-after-free'] = line.all_after('# written after free ').u64() }
	}
	if values.len < 3 { return error('missing slab classes') }
	return values
}
fn run() ! {
	if os.args.len != 9 || os.args[8] !in ['positive', 'baseline', 'tracked'] { return error('usage: CHECK FRESH_OUTPUT ARCH KERNEL SYSROOT GCC CLANG V positive|baseline|tracked') }
	work := os.abs_path(os.args[1]); arch := os.args[2]
	if arch !in ['aarch64', 'x86_64'] || os.exists(work) || os.is_link(work) { return error('fresh work and supported architecture required') }
	root := os.real_path(os.dir(@FILE) + '/../..')
	probe := root + '/tests/packages/workload-lease-probe.v'
	if winesource.file_digest(probe)! != sha256.hexhash($embed_file('workload-lease-probe.v').to_string()) { return error('compiled probe source differs') }
	if winesource.file_digest(@FILE)! != sha256.hexhash($embed_file('workload-lease-check.v').to_string()) { return error('compiled controller source differs') }
	host := hwhost.find_host(root, arch, '')!
	mut inputs := map[string]string{}
	for path in [@FILE, probe, os.executable(), os.args[3], os.args[6], os.args[7], host.qemu, host.firmware] {
		inputs[path] = winesource.file_digest(path)!
	}
	if arch == 'x86_64' { for _, path in plainiso.inputs(root)! { inputs[path] = winesource.file_digest(path)! } }
	else { inputs[hwhost.shared_path(root, 'boot-image/limine-bin/BOOTAA64.EFI')] = winesource.file_digest(hwhost.shared_path(root, 'boot-image/limine-bin/BOOTAA64.EFI'))! }
	os.mkdir_all(work)!
	os.write_file(work + '/admitted-probe.v', os.read_file(probe)!)!
	os.write_file(work + '/admitted-controller.v', os.read_file(@FILE)!)!
	mut args := [os.args[7], '-backend', 'c', '-prod', '-os', 'linux', '-arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' },
		'-gc', 'none', '-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-path', '@vlib|' + root + '|@vmodules',
		'-dump-files', work + '/sources.txt', '-o', work + '/probe.c', probe]
	if os.args[8] == 'tracked' { args.insert(1, ['-d', 'workload_sites']) }
	invoke(args, work + '/v.log')!
	winesource.capture(work + '/sources.txt', mut inputs)!
	invoke([os.args[6], '--target=' + arch + '-linux-musl', '--sysroot=' + os.args[4], '--gcc-install-dir=' + os.args[5],
		'-fuse-ld=lld', '-static', '-O2', '-w', '-D_GNU_SOURCE', '-fno-stack-protector', work + '/probe.c', '-lm', '-lpthread', '-o', work + '/probe'], work + '/cc.log')!
	inputs[work + '/probe'] = winesource.file_digest(work + '/probe')!
	os.write_file(work + '/inputs.json', json2.encode(inputs))!
	boot_host := if arch == 'x86_64' { hwhost.Host{...host, root: plainiso.prepare(root, work)!} } else { host }
	outcome := hwhost.run_scenario(boot_host, hwhost.Scenario{name: 'workload-lease', arches: [arch], ending: .running,
		required: ['WORKLOAD LEASE HOLDER DEATH PASS', 'WORKLOAD LEASE DEPTH PASS', 'HWTEST PASS workload-lease'],
		forbidden: ['HWTEST FAIL', 'Kernel panic', 'KERNEL PANIC', 'FATAL EXCEPTION']},
		hwhost.Run{kernel: os.args[3], guest: work + '/probe', state: work + '/boot', timeout: 210, keep: true})
	os.write_file(work + '/guest-outcome.json', json2.encode(outcome))!
	mut reason := ''
	if os.args[8] == 'baseline' {
		if outcome.passed || !outcome.reason.contains('workload lease query unsupported') { reason = 'baseline refused at wrong gate' }
	} else if !outcome.passed { reason = outcome.reason } else {
		serial := os.read_file(work + '/boot/serial.log')!.replace('\r', '')
		before := snapshot(serial.all_after('WORKLOAD SLAB BEFORE\n').all_before('WORKLOAD SLAB AFTER'))!
		after := snapshot(serial.all_after('WORKLOAD SLAB AFTER\n').all_before('HWTEST PASS'))!
		mut delta := map[string]i64{}
		if before.len != after.len { reason = 'slab class inventory changed' }
		for name, count in before {
			if name !in after { reason = 'slab class missing'; continue }
			delta[name] = i64(after[name]) - i64(count)
			if delta[name] > 0 { reason = 'retained kernel allocations in ' + name }
		}
		os.write_file(work + '/slab-delta.json', json2.encode(delta))!
	}
	for path, hash in inputs { if winesource.file_digest(path)! != hash { return error('workload input changed: ' + path) } }
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	os.write_file(work + '/result.json', json2.encode({'passed': json2.Any(reason == ''), 'reason': reason, 'expectation': os.args[8]}))!
	if reason != '' { return error('workload qualification failed: ' + reason) }
	println('WORKLOAD LEASE CHECK PASS arch=' + arch + ' expectation=' + os.args[8])
}
fn main() {
	if plainiso.requested() { plainiso.build() or { eprintln(err); exit(1) }; return }
	run() or { eprintln(err); exit(1) }
}
