// SPDX-License-Identifier: GPL-2.0-or-later
module compathost

import os
import hosttest

fn C.mkdtemp(&char) &char

// Authentication policy is part of the host's rebuild dependency set.
fn x11_build(arguments []string) !int {
	mut positional := []string{}
	mut destination := ''
	for argument in arguments {
		if argument.starts_with('--output=') { destination = argument.all_after('=') }
		else { positional << argument }
	}
	if positional.len > 3 { return error_with_code('usage: build-wine-host.sh [aarch64|amd64|x86_64 [X11_STAGING [USERLAND_STAGING]]] [--output=PATH]', 2) }
	selected := if positional.len > 0 { positional[0] } else { 'aarch64' }
	if selected !in ['aarch64', 'amd64', 'x86_64'] { return error_with_code('unsupported X11 host architecture', 2) }
	arch := if selected == 'amd64' { 'x86_64' } else { selected }
	x11 := os.abs_path(if positional.len > 1 { positional[1] } else { root()+'/build-'+selected+'-x11/staging' })
	userland := os.abs_path(if positional.len > 2 { positional[2] } else { root()+'/build-'+selected+'-userland/staging' })
	sysroot := os.getenv_opt('VINIX_X11_SYSROOT') or { os.dir(x11)+'/sysroot' }
	binary := if destination != '' { os.abs_path(destination) } else { x11+'/usr/bin/vinix-wine-host' }
	mut inputs := [root()+'/build-support/xorg-server/wine-host-v-abi.h',
		root()+'/build-support/xorg-server/compile-v-host', root()+'/build-support/xorg-server/build-wine-host.sh',
		root()+'/build-support/native-compat-tools/main.v']
	for directory in ['build-support/xorg-server/winehost', 'tools/packages/x11auth', 'build-support/native-compat-tools/compathost'] {
		inputs << os.walk_ext(root()+'/'+directory, '.v')
	}
	if destination == '' && os.is_executable(binary) {
		modified := os.file_last_mod_unix(binary)
		if inputs.all(os.file_last_mod_unix(it) < modified) { return 0 }
	}
	gcc_parent := userland+'/usr/lib/gcc/'+arch+'-alpine-linux-musl'
	mut versions := os.ls(gcc_parent)!
	versions = versions.filter(os.is_dir(gcc_parent+'/'+it))
	versions.sort()
	if versions.len == 0 { return error('missing musl GCC runtime: '+gcc_parent) }
	llvm := os.getenv_opt('LLVM_BIN') or { '/opt/homebrew/opt/llvm/bin' }
	clang := if os.is_executable(llvm+'/clang') { llvm+'/clang' } else { 'clang' }
	os.mkdir_all(os.dir(binary))!
	// Keep the unpublished binary on the destination filesystem for atomic rename.
	mut template := (os.dir(binary)+'/.vinix-wine-host-XXXXXX').bytes()
	template << u8(0)
	created := C.mkdtemp(&char(template.data))
	if created == unsafe { nil } { return error('cannot create private X11 build directory') }
	work := unsafe { cstring_to_vstring(created) }
	defer { retire(work) }
	generated := work+'/core.c'
	x11_core('winehost', generated, if arch == 'aarch64' { 'arm64' } else { 'amd64' }, false)!
	run([clang, '--target='+arch+'-linux-musl', '--sysroot='+sysroot,
		'--gcc-install-dir='+gcc_parent+'/'+versions.last(), '-static-libgcc', '-O2',
		'-Wall', '-Wextra', '-Werror', '-D__vinix__', '-I'+sysroot+'/usr/include',
		generated, '-I'+root()+'/build-support/xorg-server', '-fuse-ld=lld',
		'-L'+sysroot+'/usr/lib', '-L'+sysroot+'/lib', '-Wl,-rpath-link,'+sysroot+'/usr/lib',
		'-Wl,-rpath-link,'+sysroot+'/lib', '-lXtst', '-lXdamage', '-lX11', '-lXext', '-lxcb',
		'-o', work+'/host'])!
	os.chmod(work+'/host', 0o755)!
	os.rename(work+'/host', binary)!
	if destination != '' { os.cp(generated, binary+'.c')! }
	println('X11 HOST BUILD PASS: '+arch+' '+binary)
	return 0
}
