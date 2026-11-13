// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import hwhost
import json2
import os
import plainiso
import tests.packages.winesource

fn invoke(argv []string, log string) ! {
	os.write_file(log + '.argv.json', json2.encode(argv))!
	hwhost.run_tool(argv, map[string]string{}, log, 300)!
}
fn run() ! {
	if os.args.len != 8 { return error('usage: CHECK FRESH_OUTPUT KERNEL SYSROOT GCC_INSTALL CLANG V held|unheld') }
	work := os.abs_path(os.args[1]); mode := os.args[7]
	if mode !in ['held', 'unheld'] || os.exists(work) || os.is_link(work) { return error('fresh output and held|unheld required') }
	root := os.real_path(os.dir(@FILE) + '/../..')
	probe := root + '/tools/packages/pkgcore/generation_launch_test.v'
	if winesource.file_digest(@FILE)! != sha256.hexhash($embed_file('generation-launch-check.v').to_string())
		|| winesource.file_digest(probe)! != sha256.hexhash($embed_file('../../tools/packages/pkgcore/generation_launch_test.v').to_string()) { return error('compiled generation check sources differ') }
	host := hwhost.find_host(root, 'x86_64', '')!
	mut inputs := map[string]string{}
	for path in [@FILE, probe, os.executable(), os.args[2], os.args[5], os.args[6], host.qemu, host.firmware] { inputs[path] = winesource.file_digest(path)! }
	for _, path in plainiso.inputs(root)! { inputs[path] = winesource.file_digest(path)! }
	os.mkdir_all(work)!
	mut command := [os.args[6], '-backend', 'c', '-prod', '-os', 'linux', '-arch', 'amd64', '-gc', 'none', '-manualfree',
		'-d', 'no_backtrace', '-d', 'no_segfault_handler', '-d', 'generation_launch_fixture', '-path', '@vlib|' + root + '|@vmodules', '-o', work + '/probe.c', probe]
	if mode == 'held' { command.insert(1, ['-d', 'wine_owned_manager']) }
	mut discovery := command.clone(); discovery.insert(1, ['-print-watched-files', '-dump-files', work + '/sources-before.txt'])
	invoke(discovery, work + '/discover.log')!
	winesource.capture(work + '/sources-before.txt', mut inputs)!
	os.write_file(work + '/inputs-before.json', json2.encode(inputs))!
	command.insert(1, ['-dump-files', work + '/sources-built.txt']); invoke(command, work + '/v.log')!
	winesource.admit(work + '/sources-before.txt', work + '/sources-built.txt', inputs)!
	invoke([os.args[5], '--target=x86_64-linux-musl', '--sysroot=' + os.args[3], '--gcc-install-dir=' + os.args[4], '-fuse-ld=lld', '-static',
		'-O2', '-w', '-D_GNU_SOURCE', '-fno-stack-protector', work + '/probe.c', '-lm', '-lpthread', '-o', work + '/probe'], work + '/cc.log')!
	mut generated := map[string]string{}
	for path in os.walk_ext(work, '', hidden: true) { if os.is_file(path) { generated[path] = winesource.file_digest(path)! } }
	os.write_file(work + '/generated-before-boot.json', json2.encode(generated))!
	boot_host := hwhost.Host{...host, root: plainiso.prepare(root, work)!}
	outcome := hwhost.run_scenario(boot_host, hwhost.Scenario{name: 'generation-launch', arches: ['x86_64'], ending: .running,
		required: ['HWTEST PASS generation launch: holder adoption; lease lifetime; status37; missing lease; non-Windows dispatch; low descriptor isolation'], forbidden: ['HWTEST FAIL', 'Kernel panic']},
		hwhost.Run{kernel: os.args[2], guest: work + '/probe', state: work + '/boot', timeout: 60, keep: true})
	os.write_file(work + '/result.json', json2.encode(outcome))!
	for path, hash in inputs { if winesource.file_digest(path)! != hash { return error('generation check input changed') } }
	for path, hash in generated { if winesource.file_digest(path)! != hash { return error('generation generated artifact changed') } }
	os.write_file(work + '/inputs-verified.json', json2.encode(inputs))!
	if outcome.interrupted { return error('generation check interrupted') }
	if mode == 'unheld' {
		if outcome.passed || !outcome.reason.contains('HWTEST FAIL generation launch: generation worker readiness timed out') { return error('unheld control failed at wrong gate: ' + outcome.reason) }
	} else if !outcome.passed { return error('generation dispatch check failed: ' + outcome.reason) }
	println('GENERATION LAUNCH CHECK PASS ' + mode)
}
fn main() {
	if plainiso.requested() { plainiso.build() or { eprintln(err); exit(1) }; return }
	run() or { eprintln(err); exit(1) }
}
