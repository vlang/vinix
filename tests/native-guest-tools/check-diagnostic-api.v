// SPDX-License-Identifier: GPL-2.0-or-later
module main

import guesthost
import hosttest
import os

fn owners() []string {
	mut names := (os.ls(os.temp_dir()) or { panic(err) }).filter(it.starts_with('vinix-stack-diagnostic-policy-'))
	names.sort()
	return names
}

fn main() {
	work := hosttest.work_dir('', 'vinix-diagnostic-api-check-') or { panic(err) }
	defer { hosttest.remove_work_dir(work) or { panic(err) } }
	before := owners()
	for arch in ['aarch64', 'x86_64'] {
		mut flags := if arch == 'aarch64' {
			sdk := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { guesthost.root() + '/build-aarch64-userland/sysroot' }
			[os.getenv_opt('CC') or { 'clang' }, '--target=aarch64-linux-musl', '--sysroot=' + sdk]
		} else {
			[os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' }]
		}
		flags << ['-O2', '-Wall', '-Wextra', '-Werror']
		adapter := if arch == 'aarch64' { 'arm64' } else { 'amd64' }
		output := work + '/' + arch + '.o'
		result := guesthost.compile_diagnostic(output, adapter, arch, flags) or { panic(err) }
		assert result == output && os.is_file(output)
		assert owners() == before
		if _ := guesthost.compile_diagnostic(work + '/' + arch + '-failure.o', adapter, arch, ['/usr/bin/false']) {
			panic('Compiler failure was accepted')
		}
		assert owners() == before
	}
	println('Diagnostic API: both architectures, success/failure private owner retirement: PASS')
}
