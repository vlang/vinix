// SPDX-License-Identifier: GPL-2.0-or-later
module nativehost

import guesthost
import hosttest
import json2
import os

pub fn compatibility_inputs() !map[string]string {
	mut files := os.ls(root() + '/build-support/dota2/mmapcore')!
	files = files.filter(it.ends_with('.v')).map('build-support/dota2/mmapcore/' + it)
	files << ['build-support/dota2/mmap32-abi.h', 'build-support/dota2/mmap32.exports',
		'build-support/dota2/compat.v', 'build-support/compile-v-module',
		'tests/linuxkpi/generate_module.v', 'build-support/find-v.sh']
	mut result := map[string]string{}
	for file in files { result[file] = hosttest.sha(root() + '/' + file)! }
	result['v_compiler'] = capture(['sh', '-c', '. "$1/build-support/find-v.sh"; "$V" -version',
		'find-v', root()])!.trim_space()
	return result
}

pub fn build_mmap32(destination string, artifacts string) ! {
	os.mkdir_all(artifacts)!
	generated := artifacts + '/mmap32-v.c'
	run([root() + '/build-support/run-v-tool.sh', root() + '/build-support/dota2/compat.v', 'mmap32',
		generated, '--bare'])!
	run(['clang', '--target=x86_64-linux-gnu', '-fPIC', '-shared', '-nostdlib', '-ffreestanding',
		'-O2', '-fvisibility=hidden', '-fuse-ld=lld', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-DVINIX_DOTA_BARE_FFI',
		'-I', root() + '/build-support/dota2',
		'-Wl,--version-script=' + root() + '/build-support/dota2/mmap32.exports',
		'-Wl,-soname,libvinix-dota2-mmap32.so', generated, '-o', destination])!
}

fn mmap(args []string) !int {
	options := parse(args, [hosttest.Option{ name: '--work', value: true },
		hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--runtime-root', value: true },
		hosttest.Option{ name: '--native-root', value: true },
		hosttest.Option{ name: '--translator', value: true },
		hosttest.Option{ name: '--baseline', value: true },
		hosttest.Option{ name: '--baseline-probe', value: true },
		hosttest.Option{ name: '--timeout', value: true }, hosttest.Option{ name: '--prepare-only' }], [], 'Usage: run-mmap32 --work NEW_DIR --kernel-dir DIR [--baseline C --baseline-probe C] [--prepare-only]')!
	required(options, ['--work', '--kernel-dir'])!
	seconds := positive(options, '--timeout', 900)!
	work := resolve(options.value('--work', ''))!
	runtime := resolve(options.value('--runtime-root', root() + '/build/dota2-vulkan/staging/usr/libexec/vinix-dota2/root'))!
	native := resolve(options.value('--native-root', root() + '/build-aarch64-userland/staging'))!
	kernel_dir := resolve(options.value('--kernel-dir', ''))!
	separate(work, [runtime, native, kernel_dir])!
	fresh(work)!
	generated := work + '/probe-v.c'
	run([root() + '/build-support/run-v-tool.sh', root() + '/build-support/dota2/compat.v', 'mmap-probe',
		generated, '--bare'])!
	libc := runtime + '/lib/x86_64-linux-gnu/libc.so.6'
	compile_probe := ['clang', '--target=x86_64-linux-gnu', '-fPIE', '-pie', '-ffreestanding',
		'-fno-stack-protector', '-nostdlib', '-fuse-ld=lld', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-DVINIX_DOTA_BARE_FFI',
		'-I', here(), '-Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2', '-Wl,-e,_start']
	run([...compile_probe, generated, here() + '/mmap-probe-start.S', libc, '-o', work + '/probe-v'])!
	build_mmap32(work + '/mmap-v.so', work + '/generated')!
	mut files := {
		'bin/busybox':                                       native + '/bin/busybox'
		'lib/ld-musl-aarch64.so.1':                          native + '/lib/ld-musl-aarch64.so.1'
		'usr/bin/qemu-x86_64':                               resolve(options.value('--translator', root() + '/build/dota2-vulkan/staging/usr/bin/qemu-x86_64'))!
		'usr/bin/probe-v':                                   work + '/probe-v'
		'runtime/mmap-v.so':                                 work + '/mmap-v.so'
		'runtime/lib/x86_64-linux-gnu/libc.so.6':            libc
		'runtime/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2': runtime + '/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2'
	}
	mut variants := [['v-v', 'v', 'v']]
	if options.has('--baseline') {
		run(['clang', '--target=x86_64-linux-gnu', '-fPIC', '-shared', '-nostdlib', '-fuse-ld=lld',
			'-Wall', '-Wextra', '-Werror', resolve(options.value('--baseline', ''))!, '-o',
			work + '/mmap-c.so'])!
		files['runtime/mmap-c.so'] = work + '/mmap-c.so'
		variants.insert(0, ['c-v', 'c', 'v'])
	}
	if options.has('--baseline-probe') {
		run([...compile_probe, resolve(options.value('--baseline-probe', ''))!, libc, '-o',
			work + '/probe-c'])!
		files['usr/bin/probe-c'] = work + '/probe-c'
		variants.insert(0, [if options.has('--baseline') { 'c-c' } else { 'v-c' },
			if options.has('--baseline') { 'c' } else { 'v' }, 'c'])
	}
	rootfs := work + '/root'
	copy_files(rootfs, files)!
	directories(rootfs, ['sbin', 'dev', 'proc', 'sys', 'tmp', 'root', 'runtime/lib64'])!
	links(rootfs, ['sh', 'sleep', 'mount'])!
	mut script := '#!/bin/sh\nset -eu\nexport PATH=/bin:/usr/bin VINIX_ALLOW_WX=1 QEMU_CPU=Haswell\nexport VINIX_X86_64_ROOT=/runtime VINIX_I386_ROOT=/runtime VINIX_X86_MULTIARCH=1\nunset LD_PRELOAD LD_LIBRARY_PATH\nmount -t proc proc /proc 2>/dev/null || true\n'
	for variant in variants {
		script += 'echo MMAP-VARIANT-BEGIN:' + variant[0] + '\n/usr/bin/qemu-x86_64 -B 0x100000000 -L /runtime -E LD_LIBRARY_PATH=/runtime/lib/x86_64-linux-gnu -E LD_PRELOAD=/runtime/mmap-' + variant[1] + '.so /usr/bin/probe-' + variant[2] + '\necho MMAP-VARIANT-PASS:' + variant[0] + '\n'
	}
	script += 'echo MMAP-TRANSLATED-GUEST-END\nwhile :; do sleep 60; done\n'
	os.write_file(rootfs + '/sbin/init', script)!
	os.chmod(rootfs + '/sbin/init', 0o755)!
	install(kernel_dir + '/bin/vinix', work + '/kernel/bin/vinix')!
	tar := archive(rootfs, work, true)!
	mut report := {
		'kernel_sha256':    json2.Any(hosttest.sha(work + '/kernel/bin/vinix')!)
		'archive_sha256':   json2.Any(hosttest.sha(tar)!)
		'variants':         json2.decode[json2.Any](json2.encode(variants))!
		'v_inputs':         json2.decode[json2.Any](json2.encode(compatibility_inputs()!))!
		'fixture_v_sha256': json2.Any(hosttest.sha(here() + '/mmapprobe/core.v')!)
		'startup_sha256':   json2.Any(hosttest.sha(here() + '/mmap-probe-start.S')!)
		'runner_sha256':    json2.Any(hosttest.sha(here() + '/nativehost/mmap.v')!)
		'files':            json2.decode[json2.Any](json2.encode(hashes(rootfs, files)!))!
	}
	write_json(work + '/inputs.json', json2.Any(report))!
	if options.has('--prepare-only') {
		print_json(json2.Any(report))
		return 0
	}
	configured := launch(work, tar, 1024, 2, root(), false)!
	expected := [...variants.map('MMAP-VARIANT-PASS:' + it[0]), 'MMAP-TRANSLATED-GUEST-END']
	status := guesthost.boot(configured.command, configured.env, work, expected, [
		'VINIX-DOTA2-MMAP32-FAIL',
		'KERNEL PANIC',
	], seconds, true)!
	report['exit_code'] = json2.Any(status)
	report['expected_markers'] = json2.Any(hosttest.strings(expected))
	write_json(work + '/results.json', json2.Any(report))!
	return status
}
