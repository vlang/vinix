// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import cachecli
import generators
import hosttest
import os
import sourcecommand

struct HostObservation {
	probe string
	status int
	stdout string
	stderr string
}

pub fn runtime_host_cli(argv []string) !int {
	args := parse_arguments(argv, ['--baseline'], []string{}, []string{}, 0, 0, 'usage: test-runtime-v [--baseline FROZEN_ORIGINAL_C]')!
	if os.user_os() != 'macos' || os.uname().machine != 'arm64' { return error('This host adapter checks Darwin ARM64; run run-runtime-vm for native Linux ABI checks') }
	work := temporary_in(os.temp_dir(), 'vinix-android-host-')!
	defer { hosttest.remove_work_dir(work) or {} }
	os.write_file(work + '/stdio_ext.h', '#include <stdio.h>\nvoid __fseterr(FILE *);\n')!
	os.write_file(work + '/errno.h', '#include_next <errno.h>\n#undef EOVERFLOW\n#define EOVERFLOW 75\n')!
	flags := ['/usr/bin/clang', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-I', root() + '/build-support/android', '-I', root() + '/tests/android', '-I', work]
	generators.generate_module(root() + '/tests/android/runtimehost', work + '/host.c', 'arm64', ['nofloat'])!
	checked([...flags, '-c', work + '/host.c', '-o', work + '/host.o'])!
	generate_runtime(work + '/runtime.c', 'arm64')!
	mut sources := [work + '/runtime.c']
	if '--baseline' in args.options { sources << hosttest.module_resolve(args.value('--baseline', ''))! }
	mut results := [][]HostObservation{}
	for index, source in sources {
		object := work + '/runtime-' + index.str() + '.o'
		checked([...flags, '-D__linux__', '-D__errno_location=__error', '-Ddlsym=fixture_dlsym', '-Dpthread_mutex_lock=fixture_pthread_mutex_lock', '-Dpthread_mutex_trylock=fixture_pthread_mutex_trylock', '-Dpthread_mutex_unlock=fixture_pthread_mutex_unlock', '-c', source, '-o', object])!
		imports := checked(['nm', '-u', object])!.stdout
		for line in imports.split_into_lines() {
			fields := line.fields()
			if fields.len == 0 { continue }
			name := fields.last().trim_left('_')
			if name in ['malloc', 'calloc', 'realloc', 'memdup'] || name.starts_with('new_array') { return error('native Android runtime imported an allocation helper: ' + line) }
		}
		mut seen := []HostObservation{}
		for probe in ['atfork-test', 'fortify-test', 'aggregate'] {
			output := work + '/' + index.str() + '-' + probe
			mut fixture := []string{}
			mut helper := work + '/host.o'
			if probe != 'aggregate' {
				fixture << root() + '/tests/android/' + probe + '.c'
				helper = work + '/' + probe + '-host.o'
				checked([...flags, '-Dmain=android_aggregate_main', '-c', work + '/host.c', '-o', helper])!
			}
			checked([...flags, ...fixture, helper, object, '-Wl,-export_dynamic', '-o', output])!
			result := sourcecommand.capture([output], os.environ(), -1, 64 * 1024 * 1024, cachecli.cancelled)!
			if result.status != 0 { return error('Android runtime host fixture failed: ' + probe + '\n' + result.stdout + result.stderr) }
			seen << HostObservation{probe, result.status, result.stdout, result.stderr}
			if probe == 'aggregate' {
				mut environment := os.environ(); environment['ANDROID_HOST_STATS_FAIL'] = '1'
				failed := sourcecommand.capture([output], environment, -1, 64 * 1024 * 1024, cachecli.cancelled)!
				if failed.status != -6 || failed.stderr != 'Android allocator statistics ABI mismatch\n' { return error('allocator statistics failure differed: ' + failed.status.str() + '\n' + failed.stdout + failed.stderr) }
				seen << HostObservation{'provider-failure', failed.status, failed.stdout, failed.stderr}
			}
		}
		results << seen
	}
	if results.len == 2 && results[0] != results[1] { return error('V and frozen C runtime fixture observations differ') }
	println('Android runtime host ASan/UBSan: original atfork retirement and fortify fixtures, 80-byte aggregate ABI, provider failure PASS')
	return 0
}
