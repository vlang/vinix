// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import workflowbuild

fn main() {
	root := os.real_path('.')
	work := os.getenv('VINIX_VOX_STATE')
	if work == '' { panic('VINIX_VOX_STATE must name an external state directory') }
	if '--services-only' in os.args {
		build_services(root, work, os.getenv('VINIX_DESKTOP_V'))!
		return
	}
	os.mkdir_all(work + '/desktop-source')!
	workflowbuild.run('git', ['archive', 'HEAD', 'desktop', 'tools/accounts', 'tools/packages',
		'-o', work + '/desktop-source.tar'])!
	workflowbuild.run('tar', ['-xf', work + '/desktop-source.tar', '-C', work + '/desktop-source'])!
	os.cp(root + '/desktop/app.v', work + '/desktop-source/desktop/app.v')!
	workflowbuild.stage(work + '/desktop-source', root + '/../ui2', work + '/desktop', true)!
	app := work + '/desktop'
	v := os.getenv('VINIX_DESKTOP_V')
	workflowbuild.run(v, ['-new-compiler', '-memory-limit', '10G', '-os', 'linux', '-arch', 'arm64',
		'-gc', 'none', '-manualfree', '-enable-globals', '-prod', '-d', 'glibc', '-d',
		'no_segfault_handler', '-d', 'ui2_headless', '-path',
		'@vlib|' + app + '/modules|@vmodules|' + work + '/desktop-source|' + root + '|' + root + '/third_party|' + root + '/tools/accounts',
		'-o', work + '/desktop.c', app])!
	sdk := root + '/build-aarch64-userland/staging'
	mut versions := os.ls(sdk + '/usr/lib/gcc/aarch64-alpine-linux-musl')!
	versions.sort()
	gcc := sdk + '/usr/lib/gcc/aarch64-alpine-linux-musl/' + versions.last()
	llvm := '/opt/homebrew/opt/llvm/bin'
	workflowbuild.run(llvm + '/clang', ['--target=aarch64-linux-musl', '-static', '-nostdinc',
		'-nostdlib', '-isystem', root + '/build-support/aarch64-cc-shim', '-isystem', gcc + '/include',
		'-isystem', sdk + '/usr/include', '-I', app, '-D_GNU_SOURCE', '-O1', '-fno-stack-protector',
		'-w', sdk + '/usr/lib/crt1.o', sdk + '/usr/lib/crti.o', gcc + '/crtbeginT.o',
		work + '/desktop.c', app + '/execinfo.c', app + '/presenter.c', '-L' + sdk + '/usr/lib',
		'-L' + gcc, '-lgcc_eh', '-lc', '-lgcc', '-lm', '-lpthread', gcc + '/crtend.o',
		sdk + '/usr/lib/crtn.o', '-fuse-ld=lld', '-B' + llvm, '-o', work + '/vinix-desktop'])!
	build_services(root, work, v)!
}

fn build_services(root string, work string, v string) ! {
	sdk := root + '/build-aarch64-userland/staging'
	mut versions := os.ls(sdk + '/usr/lib/gcc/aarch64-alpine-linux-musl')!
	versions.sort()
	gcc := sdk + '/usr/lib/gcc/aarch64-alpine-linux-musl/' + versions.last()
	llvm := '/opt/homebrew/opt/llvm/bin'
	os.mkdir_all(work + '/services')!
	for index, service in ['session', 'timesync', 'runner'] {
		name := ['vinix-session', 'vinix-timesync', 'vinix-service-runner'][index]
		generated := work + '/services/' + name + '.c'
		workflowbuild.run(v, ['-new-compiler', '-memory-limit', '10G', '-os', 'linux', '-arch',
			'arm64', '-gc', 'none', '-manualfree', '-enable-globals', '-prod', '-d', 'no_backtrace',
			'-d', 'no_segfault_handler', '-path',
			'@vlib|@vmodules|' + root + '|' + root + '/tools/accounts', '-o', generated,
			root + '/desktop/services/' + service])!
		workflowbuild.run(llvm + '/clang', ['--target=aarch64-linux-musl', '--sysroot=' + sdk,
			'--gcc-install-dir=' + gcc, '-static', '-fuse-ld=lld', '-D_GNU_SOURCE', '-O1', '-w',
			generated, '-lm', '-lpthread', '-o', work + '/services/' + name])!
	}
}
