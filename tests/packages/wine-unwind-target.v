// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hwhost
import crypto.sha256
import json2
import os
import plainiso
import tests.packages.winesource
import tests.packages.wineunwind

fn invoke(args []string, log string) ! {
	os.write_file(log + '.argv.json', json2.encode(args))!
	hwhost.run_tool(args, map[string]string{}, log, 300)!
}

fn run() ! {
	$if prod {} $else { return error('compile unwind target controller with -prod for embedded source binding') }
	if os.args.len != 8 { return error('usage: wine-unwind-target OUTPUT KERNEL SYSROOT GCC_RUNTIME CLANG ORIGINAL_NTDLL PATCHED_NTDLL (V=compiler)') }
	root := os.real_path(os.dir(@FILE) + '/../..')
	for path, source in {
		@FILE: $embed_file('wine-unwind-target.v').to_string()
		os.dir(@FILE) + '/wine-unwind-guest/main.v': $embed_file('wine-unwind-guest/main.v').to_string()
		os.dir(@FILE) + '/wine-unwind-guest/libgcc.h': $embed_file('wine-unwind-guest/libgcc.h').to_string()
		os.dir(@FILE) + '/wineunwind/check.v': $embed_file('wineunwind/check.v').to_string()
		root + '/tests/hardware-platform/plainiso/iso.v': plainiso.source()
	} {
		if winesource.file_digest(path)! != sha256.hexhash(source) { return error('compiled unwind controller source differs: ' + path) }
	}
	out := os.abs_path(os.args[1])
	if os.exists(out) || os.is_link(out) { return error('output must be fresh') }
	original := os.read_file(os.args[6])!
	patched := os.read_file(os.args[7])!
	defer { unsafe { original.free(); patched.free() } }
	wineunwind.check(original, patched)!
	v := os.getenv_opt('V') or { return error('set V to the compiler') }
	guest_source := os.dir(@FILE) + '/wine-unwind-guest'
	mut inputs := map[string]string{}
	for path in [@FILE, os.executable(), v, os.args[2], os.args[5], os.args[6], os.args[7],
		guest_source + '/main.v', guest_source + '/libgcc.h', os.args[4] + '/libgcc_eh.a',
		os.args[4] + '/libgcc.a', os.args[4] + '/include/unwind.h',
		os.dir(@FILE) + '/wineunwind/check.v'] {
		inputs[path] = winesource.file_digest(path)!
	}
	host := hwhost.find_host(root, 'x86_64', '')!
	for path in [host.qemu, host.firmware] { inputs[path] = winesource.file_digest(path)! }
	for _, path in plainiso.inputs(root)! { inputs[path] = winesource.file_digest(path)! }
	os.mkdir_all(out)!
	mut vargs := [v, '-backend', 'c', '-prod', '-os', 'linux', '-arch', 'amd64', '-gc', 'none',
		'-manualfree', '-d', 'no_backtrace', '-d', 'no_segfault_handler', '-o', out + '/guest.c', guest_source]
	mut discovery := vargs.clone()
	discovery.insert(1, ['-print-watched-files', '-dump-files', out + '/sources-before.txt'])
	invoke(discovery, out + '/discover.log')!
	winesource.capture(out + '/sources-before.txt', mut inputs)!
	os.write_file(out + '/inputs-before.json', json2.encode(inputs))!
	vargs.insert(1, ['-dump-files', out + '/sources-built.txt'])
	invoke(vargs, out + '/v.log')!
	winesource.admit(out + '/sources-before.txt', out + '/sources-built.txt', inputs)!
	invoke([os.args[5], '--target=x86_64-linux-musl', '--sysroot=' + os.args[3],
		'--gcc-install-dir=' + os.args[4], '-fuse-ld=lld', '-static', '-O2', '-w', '-D_GNU_SOURCE',
		'-fno-stack-protector', '-fasynchronous-unwind-tables', '-I', guest_source, '-I', os.args[4] + '/include', out + '/guest.c',
		os.args[4] + '/libgcc_eh.a', '-lm', '-lpthread', '-o', out + '/guest'], out + '/cc.log')!
	extras := out + '/extras'
	os.mkdir_all(extras + '/usr/share/wine-unwind')!
	os.write_file(extras + '/usr/share/wine-unwind/ntdll.so', patched)!
	os.write_file(out + '/generated.json', json2.encode({
		'guest.c': winesource.file_digest(out + '/guest.c')!
		'guest': winesource.file_digest(out + '/guest')!
		'extras/usr/share/wine-unwind/ntdll.so': winesource.file_digest(extras + '/usr/share/wine-unwind/ntdll.so')!
	}))!
	boot_host := hwhost.Host{ ...host, root: plainiso.prepare(root, out)! }
	result := hwhost.run_scenario(boot_host, hwhost.Scenario{
		name: 'Wine-target-unwind'
		arches: ['x86_64']
		required: ['HWTEST PASS Wine unwind: actual GCC trampoline caller and six registers; missing-FDE control refused']
		ending: .running
	}, hwhost.Run{ kernel: os.real_path(os.args[2]), guest: out + '/guest', extras: extras,
		state: out + '/boot', timeout: 120, keep: true })
	os.write_file(out + '/result.json', json2.encode(result))!
	for path, expected in inputs {
		if winesource.file_digest(path)! != expected { return error('unwind target input changed: ' + path) }
	}
	os.write_file(out + '/inputs-verified.json', json2.encode(inputs))!
	if !result.passed || result.interrupted { return error('target unwind failed: ' + result.reason) }
	serial := os.read_file(out + '/boot/serial.log')!
	if serial.split_into_lines().filter(it.trim_space() == 'HWTEST PASS Wine unwind: actual GCC trampoline caller and six registers; missing-FDE control refused').len != 1 {
		return error('missing or duplicated exact target unwind marker')
	}
	println('WINE TARGET UNWIND PASS ordinary x86_64 actual GCC frame/register recovery and missing-FDE control')
}

fn main() {
	if plainiso.requested() { plainiso.build() or { eprintln(err); exit(1) }; return }
	run() or { eprintln(err); exit(1) }
}
