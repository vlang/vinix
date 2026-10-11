// SPDX-License-Identifier: GPL-2.0-or-later
module nativehost

import guesthost
import hosttest
import json2
import os
import transcriptcore

fn wake(args []string) !int {
	options := parse(args, [hosttest.Option{ name: '--kernel-dir', value: true },
		hosttest.Option{ name: '--old-translator', value: true },
		hosttest.Option{ name: '--new-translator', value: true },
		hosttest.Option{ name: '--base-root', value: true },
		hosttest.Option{ name: '--runtime-root', value: true },
		hosttest.Option{ name: '--boot-repo', value: true },
		hosttest.Option{ name: '--signal-probe', value: true },
		hosttest.Option{ name: '--cc', value: true }, hosttest.Option{ name: '--work', value: true },
		hosttest.Option{ name: '--run' }, hosttest.Option{ name: '--timeout', value: true }], [], 'Usage: wake-op-run --work NEW_DIR --kernel-dir DIR --old-translator ELF --new-translator ELF [--run]')!
	required(options, ['--kernel-dir', '--old-translator', '--new-translator', '--work'])!
	if os.getenv('VINIX_PRUNE_BUILD') != '0' { return argument('set VINIX_PRUNE_BUILD=0') }
	seconds := positive(options, '--timeout', 180)!
	work := resolve(options.value('--work', ''))!
	base := resolve(options.value('--base-root', root() + '/build/dota2-vulkan/test/root'))!
	runtime := resolve(options.value('--runtime-root', base + '/usr/libexec/vinix-dota2/root'))!
	kernel_dir := resolve(options.value('--kernel-dir', ''))!
	separate(work, [base, runtime, kernel_dir])!
	mut files := {
		'bin/busybox':                                       base + '/bin/busybox'
		'lib/ld-musl-aarch64.so.1':                          base + '/lib/ld-musl-aarch64.so.1'
		'usr/bin/qemu-old':                                  resolve(options.value('--old-translator', ''))!
		'usr/bin/qemu-new':                                  resolve(options.value('--new-translator', ''))!
		'runtime/lib/x86_64-linux-gnu/libc.so.6':            runtime + '/lib/x86_64-linux-gnu/libc.so.6'
		'runtime/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2': runtime + '/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2'
	}
	mut preloads := []string{}
	for name in ['libvinix-steam-robust.so', 'libvinix-dota2-mmap32.so'] {
		path := runtime + '/usr/lib/x86_64-linux-gnu/' + name
		if os.is_file(path) {
			guest := 'runtime/usr/lib/x86_64-linux-gnu/' + name
			files[guest] = path
			preloads << '/' + guest
		}
	}
	if options.has('--signal-probe') {
		guest := 'runtime/usr/lib/x86_64-linux-gnu/wake-op-signal-probe.so'
		files[guest] = resolve(options.value('--signal-probe', ''))!
		preloads << '/' + guest
	}
	for path in [...files.values(), kernel_dir + '/bin/vinix', here() + '/wake-op.c',
		here() + '/wake-op.ld'] {
		if !os.is_file(path) { return argument('missing fixture input: ' + path) }
	}
	fresh(work)!
	binary := work + '/wake-op-x86_64'
	argv := [options.value('--cc', 'clang'), '--target=x86_64-linux-gnu', '-O2', '-fno-pie', '-no-pie',
		'-fno-stack-protector', '-nostdlib', '-fuse-ld=lld', '-Wl,-z,now', '-Wl,-z,max-page-size=0x4000',
		'-Wl,-T,' + here() + '/wake-op.ld', '-Wl,--dynamic-linker=/lib64/ld-linux-x86-64.so.2',
		'-Wl,-e,_start', here() + '/wake-op.c', runtime + '/lib/x86_64-linux-gnu/libc.so.6', '-o',
		binary]
	run(argv)!
	files['usr/bin/wake-op-x86_64'] = binary
	rootfs := work + '/root'
	copy_files(rootfs, files)!
	directories(rootfs, ['etc', 'proc', 'sys', 'dev', 'tmp', 'sbin', 'runtime/lib64'])!
	links(rootfs, ['sh', 'sleep', 'uname'])!
	script := '#!/bin/sh\nset -eu\nexport PATH=/bin:/usr/bin VINIX_ALLOW_WX=1 QEMU_CPU=Haswell\nexport VINIX_X86_64_ROOT=/runtime VINIX_I386_ROOT=/runtime VINIX_X86_MULTIARCH=1\nunset LD_PRELOAD LD_LIBRARY_PATH\n' + if options.has('--signal-probe') {
		'export VINIX_DOTA2_SIGNAL_PROBE=1\n'
	} else {
		''
	} + 'uname -a\nfor variant in old new; do\n    echo WAKE-OP-VARIANT-BEGIN:$variant\n    status=0\n    /usr/bin/qemu-$variant -B 0x100000000 -L /runtime \\\n        -E LD_LIBRARY_PATH=/runtime/lib/x86_64-linux-gnu:/runtime/usr/lib/x86_64-linux-gnu \\\n        -E LD_PRELOAD=' + preloads.join(':') + ' /usr/bin/wake-op-x86_64 || status=$?\n    echo WAKE-OP-VARIANT-EXIT:$variant:$status\ndone\necho WAKE-OP-GUEST-END\nwhile :; do sleep 60; done\n'
	os.write_file(rootfs + '/sbin/init', script)!
	os.chmod(rootfs + '/sbin/init', 0o755)!
	install(kernel_dir + '/bin/vinix', work + '/kernel/bin/vinix')!
	tar := archive(rootfs, work, true)!
	mut report := {
		'kernel_sha256':         json2.Any(hosttest.sha(work + '/kernel/bin/vinix')!)
		'fixture_source_sha256': json2.Any(hosttest.sha(here() + '/wake-op.c')!)
		'fixture_linker_sha256': json2.Any(hosttest.sha(here() + '/wake-op.ld')!)
		'fixture_runner_sha256': json2.Any(hosttest.sha(here() + '/nativehost/wake.v')!)
		'fixture_binary_sha256': json2.Any(hosttest.sha(binary)!)
		'build_command':         json2.Any(hosttest.strings(argv))
		'archive_sha256':        json2.Any(hosttest.sha(tar)!)
		'files':                 json2.decode[json2.Any](json2.encode(hashes(rootfs, files)!))!
		'run_requested':         json2.Any(options.has('--run'))
	}
	write_json(work + '/inputs.json', json2.Any(report))!
	if !options.has('--run') {
		print_json(json2.Any(report))
		return 0
	}
	configured := launch(work, tar, 2048, 4, resolve(options.value('--boot-repo', root()))!, false)!
	result := guesthost.boot_session(configured.command, configured.env, work, guesthost.SessionPolicy{ pass: 'WAKE-OP-GUEST-END', failures: ['KERNEL PANIC'], log: work + '/vinix.log', cleanup_wait: 5, term_wait: 5, kill_wait: 5 }, seconds, true)!
	verdict := transcriptcore.wake_verdict(result.text, true)
	for key, value in json2.decode[json2.Any](json2.encode(verdict))!.as_map() {
		report[key] = value
	}
	write_json(work + '/results.json', json2.Any(report))!
	print_json(json2.Any(report))
	return if verdict.passed { 0 } else { 1 }
}
