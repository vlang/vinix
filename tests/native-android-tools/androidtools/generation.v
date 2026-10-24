// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import cachecli
import generators
import hosttest
import os
import sourcecommand

pub fn root() string { return hosttest.root() }

pub fn checked(command []string) !sourcecommand.Output {
	cachecli.checkpoint()!
	result := sourcecommand.capture(command, os.environ(), -1, 64 * 1024 * 1024, cachecli.cancelled)!
	if result.status != 0 { return error('command failed: ' + command.str() + '\n' + result.stdout + result.stderr) }
	return result
}

pub fn restore_fork_table(input string) !string {
	table := 'runtimecore__fork_thunks'
	prefix := '\tmemmove(' + table + ', (runtimecore__ForkThunks[128]){'
	suffix := '}, sizeof(' + table + '));\n'
	start := input.index(prefix) or { return error('V callback table initializer shape changed') }
	end := start + prefix.len + (input[start + prefix.len..].index(suffix) or { return error('V callback table initializer shape changed') })
	values := input[start + prefix.len..end]
	if values.contains('\n') { return error('V callback table initializer shape changed') }
	declaration := 'runtimecore__ForkThunks ' + table + '[128];'
	if input.count(declaration) != 1 { return error('V callback table declaration shape changed') }
	mut result := input.replace(declaration, 'static const runtimecore__ForkThunks ' + table + '[128] = {' + values + '};')
	initializer := input[start..end + suffix.len]
	position := result.index(initializer) or { return error('V callback table initializer shape changed') }
	result = result[..position] + result[position + initializer.len..]
	result += '\n#if !defined(__APPLE__)\n_Static_assert(sizeof(runtimecore__ForkHandler) == 80 && _Alignof(runtimecore__ForkHandler) == 8, "Original native fork slot layout");\n'
	for index, field in ['prepare', 'parent', 'child', 'dso', 'used'] {
		offset := 40 + 8 * index
		result += '_Static_assert(__builtin_offsetof(runtimecore__ForkHandler, ' + field + ') == ' + offset.str() + ', "Original fork ' + field + ' offset");\n'
	}
	return result + '_Static_assert(sizeof(runtimecore__ForkThunks) == 24, "Original three-callback table entry");\n#endif\n'
}

pub fn generate_runtime(output string, arch string) ! {
	if arch !in ['arm64', 'amd64'] { return InputError{'unsupported Android runtime architecture'} }
	generators.generate_module(root() + '/build-support/android/runtimecore', output, arch, ['nofloat'])!
	if arch == 'arm64' { os.write_file(output, restore_fork_table(os.read_file(output)!)!)! }
}

pub fn build_runtime(output string, compiler string, generated string, arch string) ! {
	os.mkdir_all(generated)!
	source := generated + '/android-runtime.c'
	generate_runtime(source, arch)!
	checked([compiler, '-O2', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function', '-Wno-unused-label', '-Wno-unused-parameter', '-fvisibility=hidden', '-shared', '-fPIC', '-I', root() + '/build-support/android', source, '-ldl', '-o', output])!
}

fn closure(directory string, mut paths []string) ! {
	mut names := os.ls(root() + '/' + directory)!
	names.sort()
	for name in names {
		path := directory + '/' + name
		if os.is_link(root() + '/' + path) { continue }
		if os.is_dir(root() + '/' + path) { closure(path, mut paths)! }
		else if (name.ends_with('.v') || name.ends_with('.h')) && !name.ends_with('_test.v') { paths << path }
	}
}

pub fn runtime_inputs() ![]u8 {
	mut paths := ['tests/native-android-tools/main.v', 'build-support/android/runtime-v-abi.h', 'build-support/android/musl-statistics.h', 'build-support/compile-v-module', 'tests/linuxkpi/generate_module.v', 'build-support/find-v.sh']
	for directory in ['build-support/android/runtimecore', 'build-support/android/atlframework', 'tests/native-android-tools/androidtools', 'tests/native-generators/generators', 'tests/linuxkpi/hosttest', 'tools/sourcecommand', 'build-support/cachecli', 'build-support/cachekey', 'tests/native-guest-tools/guesthost', 'tests/qemu-core/fixturehost', 'tests/host-policy/policyhost', 'tests/native-policy-tools/nativepolicy', 'compat/ios/plist', 'tools/qmpclient', 'build-support/tarcore', 'build-support/tarstream'] { closure(directory, mut paths)! }
	version := checked(['sh', '-c', '. "$1/build-support/find-v.sh"; "$V" -version', 'find-v', root()])!.stdout.trim_space()
	for directory in ['build-support/android/nativews','build-support/android/wsloader','build-support/android/nativeapk','build-support/android/nativeidentity','build-support/android/nativecache'] { closure(directory,mut paths)! }
	paths << ['build-support/android/nativews/bindings.txt','build-support/android/native-run.v','build-support/android/native-entry.v']
	mut result := []u8{}
	for path in paths { result << path.bytes(); result << u8(0); result << os.read_bytes(root() + '/' + path)!; result << u8(0) }
	result << version.bytes()
	return result
}

pub fn generation_cli(command string, argv []string) !int {
	if command == 'runtime-inputs' {
		mut stdout := os.stdout()
		bytes := runtime_inputs()!
		mut offset := 0
		for offset < bytes.len {
			written := stdout.write(bytes[offset..])!
			if written == 0 { return error('runtime input stream stopped') }
			offset += written
		}
		stdout.flush()
		return 0
	}
	args := parse_arguments(argv, ['--arch', '--cc', '--generated-dir'], []string{}, []string{}, 1, 1, 'usage: native Android ' + command + ' OUTPUT [--arch arm64|amd64] [--cc COMPILER --generated-dir DIR]')!
	arch := args.value('--arch', 'arm64')
	if arch !in ['arm64', 'amd64'] { return InputError{'unsupported Android runtime architecture'} }
	output := hosttest.module_resolve(args.positional[0])!
	if command == 'compile-framework' {
		build_framework_library(output, args.value('--cc', 'aarch64-linux-musl-gcc'), hosttest.module_resolve(args.value('--generated-dir', os.dir(output) + '/generated'))!, arch)!
	} else if command == 'compile-atl-configuration' {
		if '--cc' in args.options || '--generated-dir' in args.options { return error('configuration generation does not accept library build options') }
		generators.generate_module(root() + '/build-support/android/atlconfiguration', output, arch, ['nofloat'])!
	} else if '--cc' in args.options {
		build_runtime(output, args.value('--cc', ''), hosttest.module_resolve(args.value('--generated-dir', os.dir(output) + '/generated'))!, arch)!
	} else { generate_runtime(output, arch)! }
	return 0
}
