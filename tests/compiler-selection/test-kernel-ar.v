// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the real make rules against an isolated one-object ELF archive.
module main

import hosttest
import os

fn checked(arguments []string, environment map[string]string) !string {
	result := hosttest.capture(arguments, '', 60, environment)!
	if result.code != 0 { return error('${arguments.join(' ')}\n${result.stdout}${result.stderr}') }
	return result.stdout
}

fn selected(make []string, inspect string, settings []string, environment map[string]string) !string {
	mut argv := make.clone()
	argv << ['-f', 'GNUmakefile', '-f', inspect, 'inspect-ar']
	argv << settings
	return checked(argv, environment)!.trim_space()
}

fn require(condition bool, message string) ! {
	if !condition { return error(message) }
}

fn check() ! {
	root := hosttest.root()
	llvm_ar := hosttest.tool('llvm-ar')
	clang := hosttest.tool('clang')
	work := hosttest.work_dir('', 'vinix-kernel-ar-')!
	defer { hosttest.remove_work_dir(work) or { eprintln(err) } }
	kernel := work + '/kernel'
	for name in ['asm/aarch64', 'freestnd-c-hdrs', 'cc-runtime', 'c/flanterm', 'c/lwip/include/lwip'] {
		os.mkdir_all(kernel + '/' + name)!
	}
	for name in ['c/nanoprintf.h', 'c/lwip/include/lwip/init.h'] {
		os.write_file(kernel + '/' + name, '')!
	}
	// Bind the kernel rules to a committed source, excluding other sessions'
	// pending kernel edits. The compiler runtime is an untracked dependency;
	// copy its small makefile into this private fixture before building it.
	snapshot := checked(['git', '-C', root, 'rev-parse', 'HEAD'], os.environ())!.trim_space()
	os.write_file(kernel + '/GNUmakefile', checked(['git', '-C', root, 'show',
		'${snapshot}:kernel/GNUmakefile'], os.environ())!)!
	os.write_file(kernel + '/cc-runtime/cc-runtime.mk', os.read_file(root + '/kernel/cc-runtime/cc-runtime.mk')!)!
	os.write_file(kernel + '/cc-runtime/probe.c', 'long runtime_symbol(long value) { return value + 1; }\n')!
	inspect := work + '/inspect.mk'
	os.write_file(inspect, ".PHONY: inspect-ar\ninspect-ar:\n\t@echo '$(AR)'\n")!
	commands := work + '/commands'
	os.mkdir(commands)!
	os.symlink(llvm_ar, commands + '/llvm-ar')!
	os.symlink(os.executable(), commands + '/uname')!
	mut environment := os.environ()
	for name in ['AR', 'VINIX_LLVM_AR', 'MAKEFLAGS', 'MFLAGS'] { environment.delete(name) }
	environment['PATH'] = commands + os.path_delimiter + environment['PATH']
	environment['VINIX_ARCHIVER_TEST_UNAME'] = 'Darwin'
	make := ['make', '-s', '-C', kernel]
	require(selected(make, inspect, []string{}, environment)! == commands + '/llvm-ar', 'macOS did not discover the fixture LLVM archiver')!
	environment['VINIX_LLVM_AR'] = 'configured-ar'
	require(selected(make, inspect, []string{}, environment)! == 'configured-ar', 'configured macOS archiver was ignored')!
	require(selected(make, inspect, ['AR=explicit-ar'], environment)! == 'explicit-ar', 'explicit archiver did not take precedence')!
	environment.delete('VINIX_LLVM_AR')
	mut build := make.clone()
	build << ['ARCH=aarch64', 'CC=' + clang, 'cc-runtime-aarch64/cc-runtime.a']
	checked(build, environment)!
	archive := kernel + '/cc-runtime-aarch64/cc-runtime.a'
	require(checked([llvm_ar, 't', archive], environment)!.split_into_lines() == ['probe.c.o'], 'ELF runtime archive has unexpected members')!
	for goal in ['clean', 'distclean'] {
		mut argv := make.clone()
		argv << ['-n', goal, 'AR=']
		checked(argv, environment)!
	}
	mut missing_command := make.clone()
	missing_command << 'AR='
	missing := hosttest.capture(missing_command, '', 60, environment)!
	require(missing.code != 0 && missing.stderr.contains('LLVM llvm-ar is required'), 'missing LLVM archiver was not rejected')!
	environment['VINIX_ARCHIVER_TEST_UNAME'] = 'Linux'
	environment['VINIX_LLVM_AR'] = 'configured-ar'
	require(selected(make, inspect, []string{}, environment)! == 'ar', 'Linux did not select its ordinary archiver')!
	println('Kernel archiver tests passed.')
}

fn main() {
	if os.file_name(os.args[0]) == 'uname' {
		println(os.getenv('VINIX_ARCHIVER_TEST_UNAME'))
		return
	}
	check() or {
		eprintln(err)
		exit(1)
	}
}
