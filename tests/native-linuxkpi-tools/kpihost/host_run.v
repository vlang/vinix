// SPDX-License-Identifier: GPL-2.0-or-later
module kpihost

import gamehost
import cachecli
import hosttest
import os
import sourcecommand

#include <sys/resource.h>
struct C.rlimit {
	rlim_cur u64
	rlim_max u64
}

fn C.getrlimit(i32, &C.rlimit) i32
fn C.setrlimit(i32, &C.rlimit) i32

pub fn host_run_cli(tools Tools, argv []string) !int {
	_, work, temporary := private_work(argv, 'Run independent LinuxKPI native host models and original-header controls.\nUsage: run [--work DIR]')!
	defer { if temporary { gamehost.remove(work) or {} } }
	host_workload(tools, work)!
	return 0
}

fn audited_object(tools Tools, command []string, object string) ! {
	tools.checked(command, os.environ())!
	symbols := tools.command(['nm', '-u', object], os.environ())!
	if symbols.status != 0 { return error(symbols.stderr) }
	no_allocations(symbols.stdout)!
}

pub fn host_workload(tools Tools, work string) ! {
	root := tools.root
	source := gamehost.env('LINUXKPI_SOURCE_DIR', root + '/third_party/linux-i915/linux-6.6.157')
	hosttest.verify_upstream(source, hosttest.upstream_pin()!)!
	exercise_pci(tools, work + '/pci-config', '')!
	arch := host_arch()!
	assembly := if arch == 'arm64' { 'aarch64' } else { 'x86_64' }
	compiler := hosttest.shell_split(gamehost.env('CC', 'clang'))!
	cc := [...compiler, ...clang_host_flags(arch)]
	flags := ['-std=gnu11', '-fgnu89-inline', '-O1', '-g', '-ffreestanding', '-fno-builtin', '-fwrapv',
		'-fno-strict-aliasing', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter',
		'-Wno-unused-function', '-fsanitize=address,undefined', '-fno-omit-frame-pointer']
	tools.checked([root + '/tests/linuxkpi/compile-v-core', work + '/compat.c', '--arch', arch], os.environ())!
	audited_object(tools, [...cc, '-std=gnu11', '-O2', '-g', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-function', '-Wno-unused-parameter', '-fsanitize=address,undefined',
		'-fno-omit-frame-pointer', '-ffreestanding', '-fno-builtin', '-fwrapv', '-fno-strict-aliasing',
		'-DVINIX_V_RUNTIME', '-DVINIX_LINUXKPI_HOST_TEST', '-I' + root + '/kernel/c', '-c',
		work + '/compat.c', '-o', work + '/compat.o'], work + '/compat.o')!
	println('LinuxKPI: V core has no implicit allocator imports')
	for name in ['varargs', 'workqueue_abi', 'storage'] {
		extra := if name == 'varargs' {
			['-Dsnprintf=vinix_linuxkpi_format_test_snprintf',
				'-Dscnprintf=vinix_linuxkpi_format_test_scnprintf',
				'-Dsprintf=vinix_linuxkpi_format_test_sprintf']
		} else {
			[]string{}
		}
		tools.checked([...cc, '-DVINIX_LINUXKPI', '-I' + root + '/kernel/asm/' + assembly, ...extra,
			'-c', root + '/kernel/asm/' + assembly + '/linuxkpi_' + name + '.S', '-o',
			work + '/' + name + '.o'], os.environ())!
	}
	abi_headers(tools, work)!
	tools.checked([root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/overflow_policy.v'], os.environ())!
	exercise_exchange(tools, work + '/exchange')!
	tools.checked([root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/spin_sequencing.v'], os.environ())!
	tools.generate_module(root + '/kernel/linuxkpi/exchangecore', work + '/exchangecore.c', arch, ['nofloat'])!
	tools.checked([...cc, ...flags, '-c', work + '/exchangecore.c', '-o', work + '/exchangecore.o'], os.environ())!
	tools.header_primitives(work + '/headercore.c', arch, true, false)!
	include := c_includes(tools, work, source)
	audited_object(tools, [...cc, '-std=gnu11', '-O1', '-g', '-ffreestanding', '-fno-builtin',
		'-fwrapv', '-fno-strict-aliasing', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter',
		'-Wno-unused-function', '-D_FORTIFY_SOURCE=0', '-D__sputc=vkh_header_sputc',
		'-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-pthread',
		...include.filter(it != '-DVINIX_LINUXKPI_FORMAT_HOST_TEST'), '-c', work + '/headercore.c',
		'-o', work + '/headercore.o'], work + '/headercore.o')!
	println('LinuxKPI: native V header primitives have no implicit allocator imports')
	tools.header_primitives(work + '/headerimpl.c', arch, true, true)!
	tools.checked([...cc, ...flags, '-ffunction-sections', '-fdata-sections', '-D_FORTIFY_SOURCE=0',
		'-D__sputc=vhp_header_sputc', '-pthread',
		...include.filter(it != '-DVINIX_LINUXKPI_FORMAT_HOST_TEST'), '-c', work + '/headerimpl.c',
		'-o', work + '/headerimpl.o'], os.environ())!
	for name in ['runtimefixture', 'cachefixture', 'pciconfigfixture', 'i915policyfixture',
		'taskfixture', 'timefixture', 'timerfixture', 'syncfixture', 'wwfixture', 'iofixture',
		'seqfixture', 'srcufixture', 'workerfixture', 'workfixture', 'usleepfixture', 'waitbitfixture',
		'printkfixture'] {
		tools.generate_module(root + '/kernel/linuxkpi/' + name, work + '/' + name + '.c', arch, [
			'nofloat',
			'linuxkpi_host_test',
		])!
		audited_object(tools, [...cc, ...flags, '-Wno-deprecated-declarations', '-D_FORTIFY_SOURCE=0',
			'-D__sputc=vkf_' + name + '_sputc', '-pthread', ...include, '-c', work + '/' + name + '.c',
			'-o', work + '/' + name + '.o'], work + '/' + name + '.o')!
	}
	println('LinuxKPI: independent V fixtures have no implicit allocator imports')
	tools.checked([...cc, '-DVINIX_LINUXKPI', '-I' + root + '/kernel/asm/' + assembly, '-c',
		root + '/kernel/asm/' + assembly + '/linuxkpi_printk_fixture_abi.S', '-o',
		work + '/printk_fixture_abi.o'], os.environ())!
	tools.checked([...cc, '-DVINIX_LINUXKPI', '-DVINIX_LINUXKPI_HOST_TEST', '-c',
		root + '/kernel/asm/x86_64/linuxkpi_fixture_abi.S', '-o', work + '/fixture_storage.o'], os.environ())!
	golden_parity(tools)!
	tools.generate_module(root + '/tests/linuxkpi/policyhost', work + '/policyhost.c', arch, ['nofloat'])!
	tools.checked([...cc, '-std=gnu11', '-O1', '-g', '-ffreestanding', '-fno-builtin', '-Wall',
		'-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-parameter',
		'-fsanitize=address,undefined', '-fno-omit-frame-pointer', '-c', work + '/policyhost.c',
		'-o', work + '/policyhost.o'], os.environ())!
	mut environment := os.environ()
	environment['CC'] = hosttest.shell_join(cc)
	tools.host_suite(work, arch, true, environment)!
	objects := ['policyhost', 'i915policyfixture', 'runtimefixture', 'syncfixture', 'fixture_storage',
		'compat', 'headercore', 'exchangecore', 'varargs', 'storage', 'workqueue_abi'].map(work + '/' + it + '.o')
	upstream := ['lib/list_sort.c', 'lib/sort.c', 'lib/rbtree.c', 'lib/find_bit.c', 'lib/hweight.c',
		'lib/ctype.c', 'lib/siphash.c', 'drivers/gpu/drm/i915/i915_config.c',
		'drivers/gpu/drm/i915/display/intel_qp_tables.c'].map(source + '/' + it)
	executable := work + '/test'
	tools.checked([...cc, '-std=gnu11', '-O1', '-g', '-fwrapv', '-fno-strict-aliasing', '-Wall',
		'-Wextra', '-Werror', '-Wno-unused-parameter', '-fsanitize=address,undefined',
		'-fno-omit-frame-pointer', '-pthread',
		...include.filter(it != '-iquote' && it != root + '/kernel/c'),
		'-Dmain=vinix_linuxkpi_host_original_main',
		if os.user_os() == 'macos' { '-Wl,-dead_strip' } else { '-Wl,--gc-sections' }, ...objects,
		'@' + work + '/host-fixtures.rsp', ...upstream, '-include', 'linux/export.h', '-o', executable], environment)!
	tools.checked([executable], environment)!
	sleep_boundaries(tools, executable, environment)!
	tools.checked([root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/standalone.v',
		'--arch', arch, '--header-impl', work + '/headerimpl.o', '--include', work + '/include'], environment)!
	println('LinuxKPI: upstream helpers and standalone Linux/DRM header tests passed')
	for file in ['smp_calls.v', 'upstreamsource/core_test.v'] {
		tools.checked([root + '/build-support/run-v-tool.sh', root + '/tests/linuxkpi/' + file], environment)!
	}
}

fn sleep_boundaries(tools Tools, executable string, environment map[string]string) ! {
	mut original := C.rlimit{}
	if C.getrlimit(C.RLIMIT_CORE, &original) != 0 { return os.error_posix() }
	limit := C.rlimit{ rlim_cur: 0, rlim_max: original.rlim_max }
	if C.setrlimit(C.RLIMIT_CORE, &limit) != 0 { return os.error_posix() }
	defer { C.setrlimit(C.RLIMIT_CORE, &original) }
	for name in ['reversed', 'huge', 'clock-horizon', 'absolute-overflow', 'state', 'atomic',
		'valid-horizon'] {
		result := sourcecommand.capture_full([executable, name], environment, 30, 1024 * 1024, cachecli.cancelled)!
		expected := if name == 'valid-horizon' { 0 } else { -int(C.SIGABRT) }
		if result.status != expected || (expected != 0 && !result.stderr.contains('usleep boundary BUG with no published records or pages')) {
			return error('LinuxKPI sleep boundary failed: ' + name + ' status=' + result.status.str() + '\n' + result.stderr)
		}
	}
	println('LinuxKPI: invalid sleep ranges, contexts and signed clock boundaries passed')
}
