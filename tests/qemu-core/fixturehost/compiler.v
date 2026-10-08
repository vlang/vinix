// SPDX-License-Identifier: BSD-2-Clause
module fixturehost

import hosttest
import os

fn input_prefix(kind string) string {
	header := '#include "' + if kind == 'touch' {
		'touch-model-native-abi.h'
	} else {
		kind + '-oracle-native-abi.h'
	} + '"\n'
	return header + match kind {
		'signal' { '#define fork() vqs_host_fork()\n' }
		'restart' { '#define fork() vqr_host_fork()\n' }
		'nanosleep' {
			'#define fork() vqn_host_fork()\n#define sigaction(...) vqn_host_sigaction(__VA_ARGS__)\n'
		}
		'blocked' {
			'#define fork() vqb_host_fork()\n#define pipe(...) vqb_host_pipe(__VA_ARGS__)\n#define pthread_create(...) vqb_host_pthread_create(__VA_ARGS__)\n#define execv(...) vqb_host_execv(__VA_ARGS__)\n#define waitpid(...) vqb_host_waitpid(__VA_ARGS__)\n'
		}
		'poll' {
			'#define pipe(...) vqp_host_pipe(__VA_ARGS__)\n#define poll(...) vqp_host_poll(__VA_ARGS__)\n#define write(...) vqp_host_write(__VA_ARGS__)\n#define read(...) vqp_host_read(__VA_ARGS__)\n#define close(...) vqp_host_close(__VA_ARGS__)\n'
		}
		'epoll' {
			'#define pipe(...) vqe_host_pipe(__VA_ARGS__)\n#define epoll_create1(...) vqe_host_create(__VA_ARGS__)\n#define epoll_ctl(...) vqe_host_ctl(__VA_ARGS__)\n#define epoll_wait(...) vqe_host_wait(__VA_ARGS__)\n#define write(...) vqe_host_write(__VA_ARGS__)\n#define read(...) vqe_host_read(__VA_ARGS__)\n#define close(...) vqe_host_close(__VA_ARGS__)\n'
		}
		'int' {
			'#define syscall(...) vqt_host_syscall(__VA_ARGS__)\n#define close(...) vqt_host_close(__VA_ARGS__)\n'
		}
		'touch' {
			'#define sysinfo(...) vqt_host_sysinfo(__VA_ARGS__)\n#define mmap(...) vqt_host_mmap(__VA_ARGS__)\n#define munmap(...) vqt_host_munmap(__VA_ARGS__)\n#define mprotect(...) vqt_host_mprotect(__VA_ARGS__)\n#define pthread_barrier_init(...) vqt_host_barrier_init(__VA_ARGS__)\n#define pthread_barrier_wait(...) vqt_host_barrier_wait(__VA_ARGS__)\n#define pthread_barrier_destroy(...) vqt_host_barrier_destroy(__VA_ARGS__)\n'
		}
		else { '' }
	}
}

fn allocator_imports(text string) bool {
	mut token := ''
	for ch in (text + ' ').bytes() {
		if hosttest.word_char(ch) {
			token += ch.ascii_str()
			continue
		}
		if token in ['malloc', '_malloc', 'calloc', '_calloc', 'realloc', '_realloc'] {
			return true
		}
		token = ''
	}
	return ['memdup', 'v_malloc', 'new_array'].any(text.contains(it))
}

fn check_imports(name string, output string) ! {
	if allocator_imports(command(['nm', '-u', output + '/' + name + '.o'], output + '/' + name + '.nm')!) {
		return error('Unexpected allocator in ' + name)
	}
}

fn target_flags(arch string, force bool) []string {
	$if darwin {
		return ['-arch', if arch == 'arm64' { 'arm64' } else { 'x86_64' }]
	}
	return if force {
		['-arch', if arch == 'arm64' { 'arm64' } else { 'x86_64' }]
	} else {
		[]string{}
	}
}

const ignored_warnings = ['-Wno-unused-parameter', '-Wno-unused-variable', '-Wno-unused-function']
const native_ignored_warnings = ['-Wno-unused-function', '-Wno-unused-variable', '-Wno-unused-parameter']

pub fn host(kind string, output string, cc string, arch string) ! {
	prepare(kind, output, arch, false)!
	target := target_flags(arch, kind == 'touch')
	mut flags := [cc, ...target, '-O2', '-g', '-Wall', '-Wextra', '-Werror']
	unconditional_warnings := kind in ['signal', 'restart', 'nanosleep', 'touch']
	if unconditional_warnings { flags << ignored_warnings }
	flags << ['-fno-strict-aliasing', '-fsanitize=address,undefined']
	if kind == 'touch' {
		flags << ['-idirafter', hosttest.root() + '/build-aarch64-userland/sysroot/include']
	}
	provider := provider_name(kind, false)
	flags << ['-I', output + '/' + kind + 'fixture', '-I', output + '/' + provider]
	if kind == 'epoll' {
		flags << ['-idirafter',
			hosttest.env_default('VINIX_AARCH64_SYSROOT', hosttest.root() + '/build-aarch64-userland/sysroot') + '/include']
	}
	mut objects := []string{}
	for name in [reference_name(kind), kind + 'fixture', provider] {
		mut source := output + '/' + name + '.c'
		if name != provider {
			source = output + '/host-' + name + '.c'
			probe := if kind == 'blocked' && name == reference_name(kind) {
				'#define open(path, flags) vqb_host_probe_open(path, flags)\n#define getauxval(tag) vqb_host_getauxval(tag)\n'
			} else {
				''
			}
			write(source, input_prefix(kind) + probe + read(output + '/' + name + '.c')!)!
		}
		object := output + '/' + name + '.o'
		warnings := if !unconditional_warnings && name != reference_name(kind) {
			ignored_warnings
		} else {
			[]string{}
		}
		command([...flags, ...warnings, '-c', source, '-o', object], output + '/' + name + '-compile.log')!
		objects << object
		check_imports(name, output)!
	}
	if kind == 'int' {
		object := output + '/syscall-abi.o'
		command([cc, ...target, '-c', output + '/intoracle/syscall_abi.S', '-o', object], output + '/syscall-abi-compile.log')!
		objects << object
	}
	program := output + '/' + kind + '-differential'
	command([cc, ...target, '-fsanitize=address,undefined', ...objects, '-o', program], '')!
	result := command([program], output + '/host.log')!
	marker := 'QEMU CORE ' + kind.to_upper() + if kind == 'touch' {
		' HOST DIFFERENTIAL PASS'
	} else {
		' DIFFERENTIAL PASS'
	}
	if !result.contains(marker) { return error(missing_marker(kind)) }
	mut receipt := host_schema(kind).as_map()
	receipt['host_arch'] = arch
	receipt['executable_sha256'] = hosttest.sha(program)!
	write_schema(output + '/validation.json', receipt)!
	print(result)
}

pub fn native_build(kind string, output string, arch string) ! {
	native_build_core(kind, output, arch, reference_name(kind), false)!
}

// Preserve the shared helper's explicit reference argument and fork mapping.
pub fn native_helper(kind string, output string, arch string, reference string) ! {
	native_build_core(kind, output, arch, reference, true)!
}

fn native_build_core(kind string, output string, arch string, reference string, helper bool) ! {
	outside_checkout(output, 'Compile recovered oracle C outside the maintained checkout')!
	sysroot := hosttest.env_default('VINIX_AARCH64_SYSROOT', hosttest.root() + '/build-aarch64-userland/sysroot')
	cc := if arch == 'arm64' {
		[hosttest.env_default('CC', 'clang'), '--target=aarch64-linux-musl', '--sysroot=' + sysroot]
	} else {
		[hosttest.env_default('CC_AMD64', 'x86_64-linux-musl-gcc')]
	}
	flags := ['-D_GNU_SOURCE', '-O2', '-g', '-Wall', '-Wextra', '-Werror', '-fno-strict-aliasing',
		'-I', output + '/' + kind + 'fixture', '-I', output + '/' + kind + 'oracle']
	mut commands := [][]string{}
	mut objects := []string{}
	direct := helper || kind in ['signal', 'restart', 'touch']
	for name in [reference, kind + 'fixture', kind + 'oracle'] {
		mut source := output + '/' + name + '.c'
		if kind != 'touch' && name != kind + 'oracle' {
			source = output + '/native-' + name + '.c'
			prefix := if helper {
				'#include "' + kind + '-oracle-native-abi.h"\n#define fork() ' + if kind == 'signal' {
					'vqs_host_fork()'
				} else {
					'vqr_host_fork()'
				} + '\n'
			} else {
				input_prefix(kind)
			}
			write(source, prefix + read(output + '/' + name + '.c')!)!
		}
		object := output + '/' + name + '.o'
		warnings := if name != reference { native_ignored_warnings } else { []string{} }
		argv := [...cc, ...flags, ...warnings, '-c', source, '-o', object]
		if direct {
			inherited_command(argv)!
		} else {
			command(argv, output + '/' + name + '-compile.log')!
		}
		commands << argv
		if direct {
			symbols := capture(['nm', '-u', object], '', os.environ(), false)!
			write(output + '/' + name + '.nm', symbols)!
			if allocator_imports(symbols) { return error('Unexpected allocator in ' + name) }
		} else {
			check_imports(name, output)!
		}
		objects << object
	}
	if kind == 'int' && !helper {
		object := output + '/syscall-abi.o'
		command([...cc, '-c', output + '/intoracle/syscall_abi.S', '-o', object], output + '/syscall-abi-compile.log')!
		objects << object
	}
	program := output + '/' + kind + '-init'
	mut argv := [...cc, ...flags, '-static', '-pthread', ...objects]
	if arch == 'arm64' { argv << ['-L' + sysroot + '/lib', '-fuse-ld=lld'] }
	argv << ['-o', program]
	if direct { inherited_command(argv)! } else { command(argv, output + '/link.log')! }
	commands << argv
	mut receipt := native_schema(if helper { 'signal' } else { kind }).as_map()
	receipt['arch'] = arch
	receipt['commands'] = commands.map(json_strings(it))
	receipt['executable_sha256'] = hosttest.sha(program)!
	write_schema(output + '/native-validation.json', receipt)!
	println(program)
}
