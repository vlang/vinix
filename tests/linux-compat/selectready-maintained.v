// SPDX-License-Identifier: GPL-2.0-or-later
// Replay the retained maintained probe ELFs against an explicitly supplied kernel.
module main

import crypto.sha256
import guesthost
import json2
import os

struct CaseResult {
	name string
	init_sha256 string
	iso_sha256 string
	exit_code int
}
struct Receipt {
	architecture string
	kernel_sha256 string
	results []CaseResult
}
fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn run() ! {
	if os.args.len != 6 { return error('Usage: selectready-maintained ARCH KERNEL-DIR BASELINE-BUNDLE SUPPORT FRESH-STATE') }
	arch, kernel, baseline, support, state := os.args[1], os.real_path(os.args[2]), os.real_path(os.args[3]), os.real_path(os.args[4]), os.args[5]
	if arch !in ['aarch64', 'x86_64'] || os.exists(state) { return error('Fresh state and native architecture required') }
	suffix := if arch == 'aarch64' { 'arm' } else { 'x86' }
	os.mkdir_all(state + '/kernel/bin')!
	os.mkdir_all(state + '/sources')!
	os.cp(kernel + '/bin/vinix', state + '/kernel/bin/vinix')!
	kernel_hash := digest(state + '/kernel/bin/vinix')!
	os.setenv('COPYFILE_DISABLE', '1', true); os.setenv('VINIX_QEMU_SMP', '4', true)
	for key in ['VINIX_CMDLINE', 'VINIX_QEMU_BIN', 'VINIX_QEMU_X86_64', 'VINIX_OVMF_CODE', 'VINIX_OVMF_VARS', 'VINIX_QEMU_CPU', 'VINIX_QEMU_NETWORK'] { os.unsetenv(key) }
	mut results := []CaseResult{}
	for name in ['selectempty', 'maskwait', 'resethand', 'sigmaskcopy', 'altstackrestore', 'sigwaitorder', 'seccomp', 'runtime'] {
		work := state + '/' + name
		os.mkdir_all(work)!
		probe := baseline + '/maintained-' + suffix + '/' + name + '/init'
		probe_hash := digest(probe)!
		os.cp(probe, work + '/init')!
		os.cp_all(baseline + '/maintained-' + suffix + '/sources/' + name + 'fixture', state + '/sources/' + name + 'fixture', false)!
		archive := guesthost.image(work + '/init', work)!
		launch := guesthost.launch_from(work + '/init', archive, work, state + '/kernel', arch, true, support + '/launch-root')!
		os.write_file(work + '/command.json', json2.encode(launch.command, prettify: true) + '\n')!
		result := guesthost.boot_session(launch.command, launch.env, work, guesthost.SessionPolicy{
			pass: 'LINUX ' + name.to_upper() + ': PASS'
			failures: ['LINUX ' + name.to_upper() + ': FAIL', 'LINUX ' + name.to_upper() + ' FAIL', 'KERNEL PANIC', 'FATAL EXCEPTION']
			settle: 1
			log: work + '/live.log'
		}, 240, true)!
		if digest(probe)! != probe_hash || digest(state + '/kernel/bin/vinix')! != kernel_hash { return error('Maintained input changed') }
		results << CaseResult{name: name, init_sha256: probe_hash, iso_sha256: digest(work + '/test.iso')!, exit_code: if result.finished && result.passed && result.status == 0 { 0 } else { 1 }}
		os.write_file(state + '/receipt.json', json2.encode(Receipt{architecture: arch, kernel_sha256: kernel_hash, results: results}, prettify: true) + '\n')!
	}
	if results.any(it.exit_code != 0) { return error('Maintained regression failed') }
	println('Maintained probes: PASS (8/8) ' + arch)
}
fn main() { run() or { eprintln(err.msg()); exit(1) } }
