// SPDX-License-Identifier: GPL-2.0-or-later
module kpihost

import cachecli
import gamehost
import hosttest
import json2
import os

pub fn native_host_cli(tools Tools, argv []string) !int {
	args := cachecli.arguments(argv, ['--arch'], [], [], 1, 1, 'Build the complete native musl LinuxKPI host workload.\nUsage: compile-native-host WORK --arch aarch64|x86_64') or { return error_with_code(err.msg(), 2) }
	arch := args.required('--arch') or { return error_with_code(err.msg(), 2) }
	if arch !in ['aarch64', 'x86_64'] {
		return error_with_code('unsupported native architecture', 2)
	}
	native_host(tools, hosttest.module_resolve(args.positional[0])!, arch)!
	return 0
}

fn abi_headers(tools Tools, work string) ! {
	for adapter in [['spinlock', 'spinlock_adapters'], ['atomic-exchange', 'atomic_exchange'],
		['overflow', 'integer_policy']] {
		schema := adapter[0]
		header := adapter[1]
		hosttest.generate_abi(tools.root + '/kernel/linuxkpi/abi/' + schema + '.json', tools.root + '/kernel/linuxkpi', work + '/include/vinix/' + header + '.h')!
	}
}

fn c_includes(tools Tools, work string, source string) []string {
	return ['-DVINIX_LINUXKPI', '-DVINIX_LINUXKPI_HOST_TEST', '-DVINIX_LINUXKPI_FORMAT_HOST_TEST',
		'-D__KERNEL__', '-include', tools.root + '/tests/linuxkpi/host_types.h', '-include',
		'linux/kconfig.h', '-include', source + '/include/linux/compiler_types.h', '-iquote',
		tools.root + '/kernel/c', '-I' + work + '/include',
		'-I' + tools.root + '/kernel/linuxkpi/include', '-I' + source + '/include',
		'-I' + source + '/include/uapi', '-I' + source + '/arch/x86/include',
		'-I' + source + '/arch/x86/include/uapi', '-I' + source + '/drivers/gpu/drm/i915']
}

fn native_module(tools Tools, module_path string, object string, arch string, flags []string) ! {
	source := object.all_before_last('.') + '.c'
	tools.generate_module(module_path, source, if arch == 'aarch64' { 'arm64' } else { 'amd64' }, ['nofloat'])!
	mut options := flags.filter(it !in ['-static', '-nostdlib', '-pie'] && !it.starts_with('-L') && !it.starts_with('-l') && !it.starts_with('-Wl,') && !it.starts_with('-fuse-ld='))
	options << ['-Wno-unused-function', '-Wno-unused-parameter', '-fPIC', '-I', module_path, '-c',
		source, '-o', object]
	tools.checked(options, os.environ())!
}

pub fn native_host(tools Tools, work string, arch string) ! {
	gamehost.mkdir(work)!
	source := gamehost.env('LINUXKPI_SOURCE_DIR', tools.root + '/third_party/linux-i915/linux-6.6.157')
	tests := tools.root + '/tests/linuxkpi'
	mut cc := []string{}
	mut link := []string{}
	v_arch := if arch == 'aarch64' { 'arm64' } else { 'amd64' }
	if arch == 'aarch64' {
		sysroot := tools.root + '/build-aarch64-userland/sysroot'
		directory := tools.root + '/build-aarch64-userland/staging/usr/lib/gcc/aarch64-alpine-linux-musl'
		mut versions := os.ls(directory)!.filter(os.is_dir(directory + '/' + it))
		versions.sort()
		if versions.len == 0 { return error('Alpine GCC runtime missing') }
		gcc := directory + '/' + versions.last()
		cc = [gamehost.env('CC_AARCH64', '/opt/homebrew/opt/llvm/bin/clang'),
			'--target=aarch64-linux-musl', '--sysroot=' + sysroot, '--gcc-install-dir=' + gcc,
			'-mno-outline-atomics']
		link = ['-L' + sysroot + '/lib', '-fuse-ld=lld']
	} else {
		cc = [gamehost.env('CC_AMD64', '/opt/homebrew/Cellar/musl-cross/0.9.11/libexec/bin/x86_64-linux-musl-gcc')]
	}
	nm := gamehost.env('NM', '/opt/homebrew/opt/llvm/bin/llvm-nm')
	mut flags := ['-std=gnu11', '-fgnu89-inline', '-O2', '-g', '-fno-stack-protector', '-ffreestanding',
		'-fno-builtin', '-fwrapv', '-fno-strict-aliasing', '-Wall', '-Wextra', '-Werror',
		'-Wno-unused-parameter', '-Wno-unused-function', '-Wno-deprecated-declarations', '-pthread',
		'-D_GNU_SOURCE']
	if arch == 'x86_64' {
		flags << ['-Wno-attributes', '-Wno-array-parameter', '-Wno-type-limits',
			'-Wno-misleading-indentation']
	}
	include := c_includes(tools, work, source)
	abi_headers(tools, work)!
	tools.checked([tools.root + '/tests/linuxkpi/compile-v-core', work + '/compat.c', '--arch',
		v_arch], os.environ())!
	core_warnings := if arch == 'x86_64' {
		['-Wno-type-limits', '-Wno-sign-compare']
	} else {
		[]string{}
	}
	tools.checked([...cc, ...flags, ...core_warnings, '-DVINIX_V_RUNTIME', '-DVINIX_LINUXKPI_HOST_TEST',
		'-I' + tools.root + '/kernel/c', '-c', work + '/compat.c', '-o', work + '/compat.o'], os.environ())!
	tools.header_primitives(work + '/headercore.c', v_arch, true, false)!
	tools.checked([...cc, ...flags, ...core_warnings, ...include, '-c', work + '/headercore.c',
		'-o', work + '/headercore.o'], os.environ())!
	tools.generate_module(tools.root + '/kernel/linuxkpi/exchangecore', work + '/exchangecore.c', v_arch, ['nofloat'])!
	tools.checked([...cc, ...flags, '-c', work + '/exchangecore.c', '-o', work + '/exchangecore.o'], os.environ())!
	for name in ['runtimefixture', 'syncfixture', 'i915policyfixture'] {
		tools.generate_module(tools.root + '/kernel/linuxkpi/' + name, work + '/' + name + '.c', v_arch, [
			'nofloat',
			'linuxkpi_host_test',
		])!
		tools.checked([...cc, ...flags, ...include, '-c', work + '/' + name + '.c', '-o',
			work + '/' + name + '.o'], os.environ())!
	}
	tools.generate_module(tests + '/policyhost', work + '/policyhost.c', v_arch, ['nofloat'])!
	tools.checked([...cc, ...flags, '-Dmain=vmh_host_entry', '-c', work + '/policyhost.c', '-o',
		work + '/policyhost.o'], os.environ())!
	for name in ['linuxkpi_varargs', 'linuxkpi_workqueue_abi', 'linuxkpi_storage'] {
		extra := if name == 'linuxkpi_varargs' {
			['-Dsnprintf=vinix_linuxkpi_format_test_snprintf',
				'-Dscnprintf=vinix_linuxkpi_format_test_scnprintf',
				'-Dsprintf=vinix_linuxkpi_format_test_sprintf']
		} else {
			[]string{}
		}
		assembly := tools.root + '/kernel/asm/' + arch + '/' + name + '.S'
		tools.checked([...cc, '-DVINIX_LINUXKPI', '-DVINIX_LINUXKPI_HOST_TEST',
			'-I' + tools.root + '/kernel/asm/' + arch, ...extra, '-c', assembly, '-o',
			work + '/' + name + '.o'], os.environ())!
	}
	tools.checked([...cc, '-DVINIX_LINUXKPI', '-DVINIX_LINUXKPI_HOST_TEST', '-c',
		tools.root + '/kernel/asm/x86_64/linuxkpi_fixture_abi.S', '-o', work + '/fixture_storage.o'], os.environ())!
	mut environment := os.environ()
	environment['CC'] = hosttest.shell_join([...cc, ...if arch == 'x86_64' {
		['-Wno-attributes', '-Wno-array-parameter', '-Wno-type-limits', '-Wno-misleading-indentation',
			'-Wno-missing-braces']
	} else {
		[]string{}
	}])
	environment['NM'] = nm
	tools.host_suite(work, v_arch, false, environment)!
	native_module(tools, tests + '/hostguest', work + '/hostguest.o', arch, [...cc, ...flags])!
	native_module(tools, tools.root + '/tests/kernel-gaps/serialcore', work + '/serial.o', arch, [
		...cc,
		...flags,
	])!
	objects := ['policyhost', 'i915policyfixture', 'runtimefixture', 'syncfixture', 'fixture_storage',
		'compat', 'headercore', 'exchangecore', 'linuxkpi_varargs', 'linuxkpi_storage',
		'linuxkpi_workqueue_abi', 'hostguest', 'serial'].map(work + '/' + it + '.o')
	upstream := ['lib/list_sort.c', 'lib/sort.c', 'lib/rbtree.c', 'lib/find_bit.c', 'lib/hweight.c',
		'lib/ctype.c', 'lib/siphash.c', 'drivers/gpu/drm/i915/i915_config.c',
		'drivers/gpu/drm/i915/display/intel_qp_tables.c'].map(source + '/' + it)
	command := [...cc, ...flags,
		...if arch == 'x86_64' { ['-Wno-maybe-uninitialized'] } else { []string{} }, ...include,
		'-static', ...objects, '@' + work + '/host-fixtures.rsp', ...upstream, '-include',
		'linux/export.h', ...link, '-o', work + '/linuxkpi-host']
	tools.checked(command, os.environ())!
	mut hashes := map[string]json2.Any{}
	for name in os.ls(work)!.filter(it.ends_with('.o')) {
		hashes[name] = json2.Any(gamehost.digest(work + '/' + name)!)
	}
	receipt := json2.Any({
		'arch':       json2.Any(arch)
		'compiler':   json2.Any(cc.map(json2.Any(it)))
		'flags':      json2.Any(flags.map(json2.Any(it)))
		'link':       json2.Any(command.map(json2.Any(it)))
		'objects':    json2.Any(hashes)
		'elf_sha256': json2.Any(gamehost.digest(work + '/linuxkpi-host')!)
	})
	os.write_file(work + '/native-inputs.json', json2.encode(receipt, prettify: true) + '\n')!
	println('LinuxKPI: strict native musl complete host workload built for ' + arch)
}
