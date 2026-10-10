// SPDX-License-Identifier: GPL-2.0-or-later
module nativepolicy

import hosttest
import os

pub fn network_core(destination string) ! {
	work := private_work('vinix-netcore-')!
	defer { retire(work) }
	write(work + '/core.v', read(root() + '/kernel/netcore/core.v')!
		.replace('fn C.printf_panic(&char, ...) i32\n', '').replace('C.printf_panic(', 'C.printf('))!
	os.cp(root() + '/kernel/netcore/assert_amd64.v', work + '/assert.v')!
	write(work + '/v.mod', "Module {name: 'net_test'}\n")!
	generate_project(work, destination, '', false, []string{})!
}

fn c_sources(path string) ![]string {
	mut files := []string{}
	for name in os.ls(path)! {
		child := path + '/' + name
		if os.is_dir(child) { files << c_sources(child)! } else if name.ends_with('.c') { files << child }
	}
	files.sort()
	return files
}

fn network(suite string, fixture string) ! {
	work := private_work('vinix-' + suite + '-')!
	defer { retire(work) }
	os.mkdir(work + '/arch')!
	mut options := read(root() + '/kernel/c/lwipopts.h')!
	if suite in ['network-ipv6', 'network-tcp-lifetime'] {
		options = options.replace('#define LWIP_STATS 0', '#define LWIP_STATS 1')
	}
	write(work + '/lwipopts.h', options)!
	os.cp(root() + '/kernel/c/arch/cc.h', work + '/arch/cc.h')!
	lwip := root() + '/kernel/c/lwip'
	generated, obj := work + '/core.c', work + '/core.o'
	network_core(generated)!
	cc := hosttest.env_default('CC', 'clang')
	flags := ['-O2', '-g', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-Wno-macro-redefined',
		'-I' + work, '-I' + lwip + '/include']
	run(concat([cc], flags, ['-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter',
		'-ffreestanding', '-fno-builtin', '-fno-strict-aliasing', '-DVINIX_V_RUNTIME',
		'-I' + root() + '/kernel/c', '-c', generated, '-o', obj]))!
	imports := output(['nm', '-u', obj])!
	if allocator_imports(imports, ['malloc', 'calloc', 'realloc', 'memdup'], ['new_array', 'array_new']) {
		return error('implicit V allocator import: ' + imports)
	}
	println('Network: production V core has no implicit allocator imports')
	mut sources := c_sources(lwip + '/core')!
	sources << lwip + '/netif/ethernet.c'
	run(concat([cc], flags, [root() + '/tests/' + suite + '/' + fixture, obj], sources, ['-o', work + '/test']))!
	// Keep the original 60-second allowance; compilation has no deadline.
	timed_inherited([work + '/test'], 60)!
}
