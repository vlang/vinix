// SPDX-License-Identifier: GPL-2.0-or-later
module main

import cachecli
import generators
import hosttest
import os
import sourcecommand
import time

#include <signal.h>

fn C.kill(i32, i32) i32

struct SignalCase {
	work   string
	signal int
}

fn notify(pid int, pointer voidptr) ! {
	data := unsafe { &SignalCase(pointer) }
	deadline := time.sys_mono_now() + u64(30 * time.second)
	for !os.exists(data.work + '/ready') {
		if sourcecommand.child_exited(pid)! {
			return error('generator exited before compiler was ready')
		}
		if time.sys_mono_now() > deadline { return error('compiler fixture never became ready') }
		time.sleep(20 * time.millisecond)
	}
	if C.kill(pid, data.signal) != 0 { return os.error_posix() }
}

fn blocked() ! {
	if os.args[1..] == ['version'] {
		println('V 0.5.1 generator fixture')
		return
	}
	work := os.getenv('VINIX_GENERATOR_TEST_BLOCKED')
	mut child := os.new_process('/bin/sleep')
	child.set_args(['600'])
	child.run()
	os.write_file(work + '/pids', os.getpid().str() + '\n' + child.pid.str() + '\n')!
	os.write_file(work + '/ready', 'ready')!
	for { time.sleep(50 * time.millisecond) }
}

fn retired(work string) ! {
	ids := os.read_file(work + '/pids')!.split_into_lines().map(it.int())
	deadline := time.sys_mono_now() + u64(5 * time.second)
	for ids.any(C.kill(it, 0) == 0) && time.sys_mono_now() < deadline {
		time.sleep(20 * time.millisecond)
	}
	assert ids.all(C.kill(it, 0) != 0), 'compiler descendants survived'
}

fn run(argv []string, timeout f64) !sourcecommand.Output {
	result := sourcecommand.capture(argv, os.environ(), timeout, 64 * 1024 * 1024, unsafe { nil })!
	if result.status != 0 { return error(argv.str() + '\n' + result.str()) }
	return result
}

fn failure_cases(work string, reference string) ! {
	os.mkdir(work)!
	os.symlink(os.executable(), work + '/failing-v')!
	previous := os.getenv_opt('V')
	defer { if value := previous { os.setenv('V', value, true) } else { os.unsetenv('V') } }
	os.setenv('V', work + '/failing-v', true)
	mut before := os.ls(os.getenv('TMPDIR'))!
	before.sort()
	for tool in ['fixture', 'compat', 'bench', 'sampler', 'metadata'] {
		mut argv := [os.executable(), '--tool', tool, work + '/' + tool + '.c']
		if tool == 'fixture' { argv << ['--arch', 'aarch64'] }
		result := sourcecommand.capture(argv, os.environ(), 30, 1024 * 1024, unsafe { nil })!
		assert result.status == 1, result.str()
		assert result.stdout == 'compiler stdout\n', result.str()
		assert result.stderr == 'compiler stderr\nnative compiler command failed\n', result.str()
		assert !os.exists(work + '/' + tool + '.c')
	}
	if value := previous { os.setenv('V', value, true) } else { os.unsetenv('V') }
	cc := os.getenv_opt('CC')
	defer { if value := cc { os.setenv('CC', value, true) } else { os.unsetenv('CC') } }
	os.setenv('CC', work + '/failing-v', true)
	result := sourcecommand.capture([os.executable(), '--tool', 'check', '--original-reference', reference,
		'--state-dir', work + '/check'], os.environ(), 30, 1024 * 1024, unsafe { nil })!
	assert result.status == 1, result.str()
	assert result.stdout == 'compiler stdout\n', result.str()
	assert result.stderr == 'compiler stderr\nnative compiler command failed\n', result.str()
	mut after := os.ls(os.getenv('TMPDIR'))!
	after.sort()
	assert after == before
	println('GENERATOR compiler failure / separate streams / temporary retirement: PASS')
}

fn cli_cases(work string, reference string) ! {
	for argv in [['fixture'], ['fixture', work + '/x'], ['fixture', work + '/x', '--arch', 'bad'],
		['compat', work + '/x', '--arch', 'bad'], ['compat', work + '/x', '--arch='],
		['sampler', work + '/x', '--arch', 'arm64'], ['metadata', work + '/x', '--bad'],
		['bench', work + '/x', '--arch', 'bad'], ['check'],
		['check', '--original-reference', reference], ['metadata', work + '/x', '--arch=']] {
		result := sourcecommand.capture([os.executable(), '--tool', ...argv], os.environ(), 30, 1024 * 1024, unsafe { nil })!
		assert result.status == 2, argv.str() + result.str()
	}
	protected := work + '/protected'
	os.mkdir(protected)!
	os.write_file(protected + '/keep', 'unchanged')!
	for state in [protected, ''] {
		result := sourcecommand.capture([os.executable(), '--tool', 'check', '--original-reference',
			reference, '--state-dir', state], os.environ(), 30, 1024 * 1024, unsafe { nil })!
		assert result.status == 1, result.str()
		assert os.read_file(protected + '/keep')! == 'unchanged'
	}
	println('GENERATOR CLI / invalid options / protected state: PASS')
}

fn signal_cases(work string) ! {
	mut before := os.ls(os.getenv('TMPDIR'))!
	before.sort()
	bin := work + '/bin'
	os.mkdir(bin)!
	os.symlink(os.executable(), bin + '/blocked-v')!
	previous := os.getenv_opt('V')
	defer {
		if value := previous { os.setenv('V', value, true) } else { os.unsetenv('V') }
		os.unsetenv('VINIX_GENERATOR_TEST_BLOCKED')
	}
	os.setenv('V', bin + '/blocked-v', true)
	for tool in ['fixture', 'compat', 'bench', 'sampler', 'metadata'] {
		for signal in [2, 15] {
			directory := work + '/' + tool + '-' + signal.str()
			os.mkdir(directory)!
			os.setenv('VINIX_GENERATOR_TEST_BLOCKED', directory, true)
			data := SignalCase{directory, signal}
			mut argv := [os.executable(), '--tool', tool, directory + '/output.c']
			if tool == 'fixture' { argv << ['--arch', 'aarch64'] }
			result := sourcecommand.capture_owned(argv, os.environ(), 45, 4 * 1024 * 1024, unsafe { nil }, unsafe { nil }, notify, unsafe { &data }, 0)!
			assert result.status == 128 + signal, result.str()
			retired(directory)!
			assert !os.exists(directory + '/output.c')
			println('GENERATOR signal / descendant retirement: PASS ' + tool + ' ' + signal.str())
		}
	}
	mut after := os.ls(os.getenv('TMPDIR'))!
	after.sort()
	assert after == before, 'interrupted generators retained temporary projects'
}

fn sampler(work string, arch string, sanitizer bool) ! {
	root := generators.root()
	generated := work + '/sampler.c'
	fixture := work + '/fixture.c'
	generators.generate_sampler(generated, arch, true)!
	generators.generate_module(root + '/tests/alloc-bench/samplerfixture', fixture, arch, []string{})!
	hosttest.emit_module_header(root + '/kernel/heapbench', generated, work + '/sampler.h')!
	mut flags := [os.getenv_opt('CC') or { 'clang' }, '-arch',
		if arch == 'amd64' { 'x86_64' } else { arch }, '-std=c11', '-O2', '-g', '-Wall', '-Wextra',
		'-Werror', '-fno-builtin']
	if sanitizer { flags << ['-fsanitize=address,undefined', '-fno-omit-frame-pointer'] }
	run([...flags, '-DVINIX_KALLOC_HOST_TEST', '-I', root + '/kernel/c', '-c', generated, '-o',
		work + '/sampler.o'], 120)!
	imports := run(['nm', '-u', work + '/sampler.o'], 30)!.stdout
	assert !hosttest.allocation_symbols(imports), imports
	run([...flags, '-Wno-unused-function', '-Wno-unused-parameter', '-I',
		root + '/tests/alloc-bench/samplerfixture', '-c', fixture, '-o', work + '/fixture.o'], 120)!
	run([...flags, '-c', root + '/tests/alloc-bench/samplerfixture/varargs-' + arch + '.S', '-o',
		work + '/varargs.o'], 120)!
	run([...flags, work + '/sampler.o', work + '/fixture.o', work + '/varargs.o', '-o',
		work + '/sampler-test'], 120)!
	result := run([work + '/sampler-test'], 180)!
	assert result.stdout == 'Shared kernel allocator sampler: success, three-phase OOM/zeroing rollback, TSC failure and kext ABI passed\n', result.str()
	assert result.stderr == '', result.str()
	os.write_file(work + '/sampler.stdout', result.stdout)!
	println('SAMPLER / OOM / zeroing / clock / callback ABI / allocator imports: PASS ' + arch)
}

fn generated_cases(work string, reference string, arch string, sanitizer bool) ! {
	root := generators.root()
	generators.check_metadata(reference, work + '/metadata')!
	generators.generate_compat(work + '/compat.c', arch)!
	text := os.read_file(work + '/compat.c')!
	for name in ['strchr', 'strpbrk', 'strsep'] {
		assert text.contains('vinix_linuxkpi_host_' + name + '(')
	}
	for name in ['vsnprintf', 'vscnprintf', 'vsprintf', 'snprintf', 'scnprintf', 'sprintf'] {
		if os.read_file(root + '/kernel/linuxkpi/compatcore/native_runtime.v')!.contains("@[export: '" + name + "']") {
			assert text.contains('vinix_linuxkpi_format_test_' + name + '(')
		}
	}
	manifest := generators.generate_bench(work + '/bench.c', arch)!
	assert manifest['arch']!.str() == arch
	assert manifest['source_sha256']!.str() == hosttest.sha(work + '/bench.c')!
	assert manifest['native_header_sha256']!.str() == hosttest.sha(work + '/bench-native-abi.h')!
	flags := [os.getenv_opt('CC') or { 'clang' }, '-arch',
		if arch == 'amd64' { 'x86_64' } else { arch }, '-std=c11', '-O2', '-Wall', '-Wextra', '-Werror',
		'-fno-builtin']
	run([...flags, '-I', work, work + '/bench.c', '-o', work + '/bench'], 120)!
	result := run([work + '/bench', '--quick', '--label', 'native-generator'], 180)!
	assert result.stdout.contains('ALLOC-DONE'), result.str()
	os.write_file(work + '/bench.stdout', result.stdout)!
	generators.generate_module(root + '/tests/kernel-gaps/serialcore', work + '/serial.c', arch, ['nofloat'])!
	assert os.read_file(work + '/serial.c')!.contains('serialcore__init(')
	generators.compile_fixture(root + '/tests/kernel-gaps/serialcore', work + '/serial.o',
		if arch == 'amd64' { 'x86_64' } else { 'aarch64' }, [...flags, '-static', '-nostdlib',
			'-pie', '-L/not-used', '-lnot-used', '-Wl,not-used', '-fuse-ld=not-used'])!
	if arch == 'amd64' { generators.generate_sampler(work + '/sampler-native.c', arch, false)! }
	sampler(work, arch, sanitizer)!
}

fn main() {
	if os.base(os.args[0]) == 'failing-v' {
		if os.args[1..] == ['version'] {
			println('V 0.5.1 generator fixture')
			return
		}
		println('compiler stdout')
		eprintln('compiler stderr')
		exit(7)
	}
	if os.base(os.args[0]) == 'blocked-v' {
		blocked() or { panic(err) }
		return
	}
	args := os.args[1..]
	if args.len == 3 && args[0] == '--failures' {
		failure_cases(args[1], args[2]) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if args.len >= 2 && args[0] == '--tool' {
		exit(if args[1] == 'check' {
			generators.check_cli(args[2..])
		} else {
			generators.cli(args[2..], args[1])
		})
	}
	if args.len != 4 || args[2] !in ['arm64', 'amd64'] || args[3] !in ['plain', 'san'] {
		eprintln('usage: test-generators NEW_STATE ORIGINAL_METADATA arm64|amd64 plain|san')
		exit(2)
	}
	os.mkdir(args[0]) or {
		eprintln(err)
		exit(1)
	}
	guard := cachecli.own_commands()
	defer { guard.close() }
	generated_cases(args[0], args[1], args[2], args[3] == 'san') or {
		eprintln(err)
		exit(1)
	}
	cli_cases(args[0], args[1]) or {
		eprintln(err)
		exit(1)
	}
	signal_cases(args[0]) or {
		eprintln(err)
		exit(1)
	}
	println('NATIVE GENERATORS: PASS')
}
