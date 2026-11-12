// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hwhost
import os

fn run() ! {
	if os.args.len != 7 {
		return error('usage: ioctl-check ARCH OUTPUT KERNEL SYSROOT GCC_RUNTIME CLANG (V=<compiler>)')
	}
	arch := os.args[1]
	if arch !in ['aarch64', 'x86_64'] { return error('invalid architecture') }
	root := os.real_path(os.dir(@FILE) + '/../..')
	work := os.abs_path(os.args[2])
	if os.exists(work) { return error('output must be fresh') }
	os.mkdir_all(work)!
	v := os.getenv_opt('V') or { return error('set V to the V compiler') }
	cfile := work + '/guest.c'
	hwhost.run_tool([v, '-prod', '-backend', 'c', '-os', 'linux', '-arch',
		if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-gc', 'none', '-manualfree', '-d',
		'no_backtrace', '-d', 'no_segfault_handler', '-o', cfile, os.dir(@FILE) + '/ioctl-guest'], map[string]string{}, work + '/v.log', 300)!
	hwhost.run_tool([os.args[6], '--target=' + arch + '-linux-musl', '--sysroot=' + os.args[4],
		'--gcc-install-dir=' + os.args[5], '-fuse-ld=lld', '-static', '-O2', '-w', '-D_GNU_SOURCE',
		'-fno-stack-protector', cfile, '-lm', '-lpthread', '-o', work + '/guest'],
		map[string]string{}, work + '/cc.log', 300)!
	host := hwhost.find_host(root, arch, '')!
	outcome := hwhost.run_scenario(host, hwhost.Scenario{
		name:     'pledge-file-ioctl'
		arches:   [arch]
		required: ['HWTEST PASS pledge-file-ioctl: 20 ordinary-user query and refusal controls']
		ending:   .running
	}, hwhost.Run{
		kernel:  os.real_path(os.args[3])
		guest:   work + '/guest'
		state:   work + '/boot'
		timeout: 120
		keep:    true
	})
	if !outcome.passed { return error(outcome.reason) }
	println('PLEDGE FILE IOCTL PASS ' + arch)
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}
