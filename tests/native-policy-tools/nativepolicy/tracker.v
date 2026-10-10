// SPDX-License-Identifier: GPL-2.0-or-later
module nativepolicy

import os

fn tracker() ! {
	work := private_work('vinix-track-')!
	defer { retire(work) }
	source := work + '/tracker'
	os.mkdir(source)!
	write(source + '/track.v', read(root() + '/kernel/alloctrack/track_d_alloc_track.v')!
		.replace('module alloctrack', 'module tracker'))!
	write(source + '/host.v', 'module tracker\nfn kernel_address_min() u64 { return 4096 }\n')!
	write(work + '/v.mod', "Module { name: 'track_test' }\n")!
	write(work + '/entry.v', 'module main\nimport tracker as _\n')!
	generated := work + '/track.c'
	generate_project(work, generated, '', false, []string{})!
	flags := concat(['clang'], clang_arch(arch()), ['-std=gnu11', '-O2', '-g', '-ffreestanding', '-fno-builtin',
		'-fsanitize=address,undefined', '-fno-omit-frame-pointer'])
	obj := work + '/track.o'
	run(concat(flags, ['-I' + root() + '/kernel/c', '-c', generated, '-o', obj]))!
	no_allocators(output(['nm', '-u', obj])!)!
	fixture := work + '/fixture.c'
	// The original fixture generator has no nofloat define.
	run([root() + '/build-support/compile-v-module', root() + '/tests/alloc-track/fixture',
		fixture, '--arch', arch()])!
	executable := work + '/test'
	run(concat(flags, ['-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter',
		'-I', root() + '/tests/alloc-track/fixture', obj, fixture, '-o', executable]))!
	run([executable])!
	println('Allocation tracker: 8,192 live records, replacement/deletion/restart, call chains and bounded dump; no allocator imports')
}
