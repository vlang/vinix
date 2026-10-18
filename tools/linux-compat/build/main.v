// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

struct BuildReceipt {
	architecture      string
	libc              string
	commands          [][]string
	inputs            map[string]string
	executable_sha256 string
}

fn run(command []string) ! {
	mut child := os.new_process(command[0])
	child.set_args(command[1..])
	child.run()
	child.wait()
	defer { child.close() }
	if child.code != 0 { return error('build failed: ' + command.str()) }
}

fn main() {
	options := if os.args.len >= 3 { os.args[3..] } else { []string{} }
	runtime := '--runtime-probe' in options
	glibc := '--libc=glibc' in options
	if os.args.len < 3 || options.len > 2
		|| options.any(it !in ['--runtime-probe', '--libc=glibc'])
		|| options.filter(it == '--runtime-probe').len > 1
		|| options.filter(it == '--libc=glibc').len > 1 || (glibc && !runtime) || os.args[1] !in [
		'aarch64',
		'x86_64',
		'i386',
	] || (os.args[1] == 'i386' && !runtime) {
		eprintln('Usage: build/main.v aarch64|x86_64|i386 FRESH-OUTPUT-DIR [--runtime-probe] [--libc=glibc]; glibc requires a runtime probe and VINIX_GLIBC_SYSROOT')
		exit(2)
	}
	arch := os.args[1]
	output := os.args[2]
	if os.exists(output) {
		eprintln('output directory must be fresh')
		exit(2)
	}
	root := os.real_path(os.dir(@FILE) + '/../../..')
	mut compiler := os.getenv_opt('VINIX_V_COMPILER') or { os.find_abs_path_of_executable('v') or {
		eprintln('V compiler is missing')
		exit(2)
	} }
	if os.is_dir(compiler) { compiler += '/v' }
	if !os.is_executable(compiler) {
		eprintln('V compiler is not executable')
		exit(2)
	}
	os.mkdir_all(output) or {
		eprintln(err.msg())
		exit(1)
	}
	work := os.real_path(output)
	mut generate := if runtime {
		[root + '/build-support/compile-v-module', root + '/tests/linux-compat/runtimefixture',
			work + '/workloads.c', '--arch',
			if arch == 'aarch64' {
				'arm64'
			} else if arch == 'i386' {
				'i386'
			} else {
				'amd64'
			}, '-d', 'nofloat']
	} else {
		[compiler, '-nocache', '-os', 'linux', '-arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' },
			'-gc', 'none', '-enable-globals', '-path', '@vlib|@vmodules|' + root, '-prod', '-o', work + '/workloads.c', root + '/tools/linux-compat/workloads']
	}
	if glibc { generate << ['-d', 'glibc'] }
	mut compile := []string{}
	i386_sdk := if arch == 'i386' { os.getenv('VINIX_I386_SYSROOT') } else { '' }
	mut link_inputs := map[string]string{}
	if glibc {
		sdk := os.getenv_opt('VINIX_GLIBC_SYSROOT') or {
			eprintln('VINIX_GLIBC_SYSROOT must name the matching pinned Debian SDK')
			exit(2)
		}
		triplet := match arch {
			'aarch64' { 'aarch64-linux-gnu' }
			'x86_64' { 'x86_64-linux-gnu' }
			else { 'i386-linux-gnu' }
		}
		target := if arch == 'i386' { 'i686-linux-gnu' } else { triplet }
		lib := sdk + '/lib/' + triplet
		dev := sdk + '/usr/lib/' + triplet
		loader := match arch {
			'aarch64' { 'ld-linux-aarch64.so.1' }
			'x86_64' { 'ld-linux-x86-64.so.2' }
			else { 'ld-linux.so.2' }
		}
		link_inputs = {
			'crt1': dev + '/crt1.o'
			'crti': dev + '/crti.o'
			'crtn': dev + '/crtn.o'
			'libc': lib + '/libc.so.6'
			'libm': lib + '/libm.so.6'
			'libgcc': lib + '/libgcc_s.so.1'
			'loader': lib + '/' + loader
		}
		compile = [os.getenv_opt('CC_GLIBC') or { 'clang' }, '--target=' + target,
			'--sysroot=' + sdk, '-isystem', sdk + '/usr/include/' + triplet, '-fuse-ld=lld',
			'-D_FILE_OFFSET_BITS=64', '-D_TIME_BITS=64', '-fno-pie']
		if arch == 'aarch64' { compile << '-mno-outline-atomics' }
		if arch == 'i386' { compile << '-msse2' }
		interpreter := if arch == 'x86_64' { '/lib64/' + loader } else { '/lib/' + loader }
		compile << ['-pthread', '-w', '-nostdlib', '-no-pie', link_inputs['crt1'],
			link_inputs['crti'], work + '/workloads.c', link_inputs['libc'], link_inputs['libm'],
			link_inputs['libgcc'], link_inputs['crtn'], '-Wl,--dynamic-linker=' + interpreter,
			'-Wl,-rpath,/usr/libexec/vinix-glibc/' + arch + '/lib', '-o',
			work + '/linux-compat-workloads']
	} else if arch == 'aarch64' {
		sdk := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { root + '/build-aarch64-userland/sysroot' }
		compile = [os.getenv_opt('CC_AARCH64') or { 'clang' }, '--target=aarch64-linux-musl',
			'--sysroot=' + sdk, '-fuse-ld=lld', '-L' + sdk + '/lib']
	} else if arch == 'i386' {
		if i386_sdk != '' {
			builtins := os.getenv_opt('VINIX_I386_BUILTINS') or {
				eprintln('VINIX_I386_BUILTINS must name the matching compiler-rt archive')
				exit(2)
			}
			compile = [os.getenv_opt('CC_I386') or { 'clang' }, '--target=i686-linux-musl',
				'--sysroot=' + i386_sdk, '-fuse-ld=lld', '-L' + i386_sdk + '/usr/lib']
			link_inputs = {
				'crt1': i386_sdk + '/usr/lib/crt1.o'
				'crti': i386_sdk + '/usr/lib/crti.o'
				'crtn': i386_sdk + '/usr/lib/crtn.o'
				'libc': i386_sdk + '/usr/lib/libc.a'
				'builtins': builtins
			}
		} else {
			compile = [os.getenv_opt('CC_I386') or { 'i686-linux-musl-gcc' }]
		}
		compile << '-msse2'
	} else {
		compile = [os.getenv_opt('CC_AMD64') or { 'x86_64-linux-musl-gcc' }]
	}
	if glibc {
		// The complete dynamic link command above uses only the pinned SDK.
	} else if link_inputs.len > 0 {
		// A musl SDK plus compiler-rt is sufficient; no host GCC CRT or libgcc
		// may accidentally be pulled into this i386 Linux executable.
		compile << ['-static', '-pthread', '-w', '-nostdlib', link_inputs['crt1'],
			link_inputs['crti'], work + '/workloads.c', '-lc', '-lm', link_inputs['builtins'],
			link_inputs['crtn'], '-o', work + '/linux-compat-workloads']
	} else {
		compile << ['-static', '-pthread', '-w', work + '/workloads.c', '-lm', '-o',
			work + '/linux-compat-workloads']
	}
	run(generate) or {
		eprintln(err.msg())
		exit(1)
	}
	run(compile) or {
		eprintln(err.msg())
		exit(1)
	}
	bytes := os.read_bytes(work + '/linux-compat-workloads') or {
		eprintln(err.msg())
		exit(1)
	}
	machine := if bytes.len >= 20 { int(bytes[18]) + (int(bytes[19]) << 8) } else { 0 }
	expected_class := if arch == 'i386' { 1 } else { 2 }
	if bytes.len < 20 || bytes[..4] != [u8(127), `E`, `L`, `F`] || bytes[4] != expected_class || bytes[5] != 1 || machine != if arch == 'aarch64' {
		183
	} else if arch == 'i386' {
		3
	} else {
		62
	} {
		eprintln('compiler produced the wrong ELF target')
		exit(1)
	}
	mut inputs := map[string]string{}
	for name, path in link_inputs {
		inputs[if glibc { 'glibc_' + name } else { 'i386_' + name }] = sha256.sum(os.read_bytes(path) or {
			eprintln(err.msg())
			exit(1)
		}).hex()
	}
	for source in if runtime {
		['tests/linux-compat/runtimefixture/core.v']
	} else {
		['tools/linux-compat/workloads/main.v', 'tools/linux-compat/workloads/diagnostics.v', 'tools/linux-compat/workloads/debugger.v', 'tools/linux-compat/workloads/packages.v', 'tools/linux-compat/workloads/games.v', 'tools/linux-compat/workloads/service_units.v', 'tools/linux-compat/workloads/browsers.v', 'tools/linux-compat/workloads/jit.v', 'tools/linux-compat/workloads/runtime_sources.v', 'tests/go/smoke.go', 'tests/java/VinixJavaSmoke.java']
	} {
		inputs[source] = sha256.sum(os.read_bytes(root + '/' + source) or {
			eprintln(err.msg())
			exit(1)
		}).hex()
	}
	inputs['generated_c'] = sha256.sum(os.read_bytes(work + '/workloads.c') or {
		eprintln(err.msg())
		exit(1)
	}).hex()
	os.write_file(work + '/build.json', json2.encode(BuildReceipt{arch, if glibc { 'glibc' } else { 'musl' }, [generate, compile], inputs, sha256.sum(bytes).hex()},
		prettify: true
	) + '\n') or {
		eprintln(err.msg())
		exit(1)
	}
	println(work + '/linux-compat-workloads')
}
