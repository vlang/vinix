// SPDX-License-Identifier: GPL-2.0-or-later
module allocationhost

import cachecli
import comparecore
import generators
import guesthost
import hosttest
import json2
import kernelcompare
import os
import sourcecommand
import time

pub enum VinixKind {
	current
	saved_final
	preboot
	kernel
}

pub struct VinixOptions {
pub:
	kernel             string
	sysroot            string
	state              string
	qemu               string = 'qemu-system-x86_64'
	firmware           string
	cc                 string = 'x86_64-linux-musl-gcc'
	allocator_check    string
	original_reference string
	iterations         int = 200000
	samples            int = 7
	timeout            int = 3600
	cpus               int = 1
}

struct InputError {
	message string
}

fn (failure InputError) msg() string { return failure.message }

fn (failure InputError) code() int { return 2 }

pub const machine = 'q35,vmport=off'
pub const accelerator = 'tcg,thread=single,tb-size=1024'
pub const cpu = 'Penryn,kvm=on,vendor=GenuineIntel,+ssse3,+sse4.2,+popcnt'
pub const kernel_flags = ['-std=c11', '-O2', '-Wall', '-Wextra', '-Werror', '-fno-builtin',
	'-ffreestanding', '-fno-stack-protector', '-mno-red-zone', '-mno-80387', '-mno-mmx', '-mno-sse',
	'-mno-sse2']

fn selected(program string) !string {
	return resolve(os.find_abs_path_of_executable(program) or { program })!
}

fn first_line(text string) !string {
	hosttest.module_decode_utf8(text)!
	lines := text.replace('\r\n', '\n').replace('\r', '\n').split_into_lines()
	if lines.len == 0 { return error('empty compiler version') }
	return lines[0]
}

pub fn allocator_script() string {
	return '\necho UALLOC-VERIFY-BEGIN\nfor linkage in dynamic static; do\n    echo UALLOC-LINKAGE mode=$linkage\n    extra=\n    [ "$linkage" = static ] && extra=-static\n    gcc ' + hosttest.shell_join(benchmark_flags) + ' -pthread $extra /root/allocator-check.c -o /root/allocator-check || {\n        echo ALLOC-FAIL stage=allocator-check-compile\n        while :; do sleep 60; done\n    }\n    /root/allocator-check || {\n        echo ALLOC-FAIL stage=allocator-check\n        while :; do sleep 60; done\n    }\ndone\necho UALLOC-VERIFY-COMPLETE\n'
}

pub fn init_script(check bool, iterations int, samples int, native bool) string {
	return '#!/bin/sh\nexec >/dev/com1 2>&1\nexport PATH=/usr/bin:/bin:/usr/sbin:/sbin\nmount -t proc proc /proc\necho ALLOC-COMPILE-BEGIN\ngcc --version | head -n 1\ngcc -dM -E - </dev/null | grep __clang__ && exit 1\n' +
		if check { allocator_script() } else { '' } + 'gcc ' + hosttest.shell_join(benchmark_flags) + if native {
		' -I /root'
	} else {
		''
	} + ' /root/alloc-bench.c -o /root/alloc-bench || {\n    echo ALLOC-FAIL stage=compile\n    while :; do sleep 60; done\n}\necho ALLOC-COMPILE-DONE\n/root/alloc-bench --label vinix --iterations ' + iterations.str() + ' --samples ' + samples.str() + ' || echo ALLOC-FAIL stage=benchmark\necho ALLOC-GUEST-DONE\nwhile :; do sleep 60; done\n'
}

pub fn vm_command(qemu string, firmware string, iso string, serial string, kind VinixKind, cpus int) []string {
	smp := if kind == .kernel {
		cpus.str() + ',sockets=1,cores=' + cpus.str() + ',threads=1'
	} else {
		'2,sockets=1,cores=2,threads=1'
	}
	return [qemu, '-machine', machine, '-accel', accelerator, '-cpu', cpu, '-smp', smp, '-m', '4096',
		'-display', 'none', '-monitor', 'none', '-drive',
		'if=pflash,format=raw,readonly=on,file=' + firmware, '-cdrom', iso, '-serial',
		'file:' + serial, '-no-reboot']
}

struct VmContext {
	state   string
	timeout int
	check   bool
	kind    VinixKind
}

struct VmCompleted {}

fn (done VmCompleted) msg() string { return 'Allocation VM completed' }

fn (done VmCompleted) code() int { return 0 }

// WNOWAIT reserves the PID until this observer returns. Serial reads use the
// original deadlines, polling intervals, marker priority and UTF-8 replacement.
fn observe_vm(pid int, pointer voidptr) ! {
	context := unsafe { &VmContext(pointer) }
	serial := context.state + '/serial.log'
	deadline := time.sys_mono_now() + u64(context.timeout) * u64(time.second)
	mut last_stage := ''
	for time.sys_mono_now() < deadline {
		cachecli.checkpoint()!
		output := if os.exists(serial) {
			guesthost.replacement_text(os.read_bytes(serial)!).replace('\r\n', '\n').replace('\r', '\n')
		} else {
			''
		}
		if context.kind != .kernel {
			for marker in ['heap-bench: done', 'ALLOC-COMPILE-BEGIN', 'ALLOC-COMPILE-DONE'] {
				if output.contains(marker) && marker != last_stage {
					stages := ['ALLOC-COMPILE-DONE', 'ALLOC-COMPILE-BEGIN', 'heap-bench: done'].filter(output.contains(it))
					stage := if stages.len > 0 { stages[0] } else { '' }
					if stage != last_stage {
						println(stage)
						flush_stdout()
						last_stage = stage
					}
				}
			}
		}
		failures := if context.kind == .kernel {
			['KALLOC-ERROR', 'KERNEL PANIC', 'FATAL EXCEPTION']
		} else {
			['KERNEL PANIC', 'FATAL EXCEPTION', 'ALLOC-FAIL', 'ALLOC-ERROR', 'UALLOC-FAIL']
		}
		if failures.any(output.contains(it)) { return error('guest failed; see ' + serial) }
		if output.contains(if context.kind == .kernel { 'KALLOC-DONE' } else { 'ALLOC-GUEST-DONE' }) {
			if context.kind == .kernel {
				kernelcompare.parse_log(kernelcompare.log_text(output), 'vinix')!
				println(comparecore.lines(output).filter(it.contains('KALLOC-')).map(it.all_after('KALLOC-')).map('KALLOC-' + it).join('\n'))
			} else {
				if !output.contains('ALLOC-DONE') {
					return error('benchmark did not finish; see ' + serial)
				}
				if context.check && (!output.contains('UALLOC-VERIFY-COMPLETE') || comparecore.lines(output).filter(it.starts_with('UALLOC-DONE ')).len != 2) {
					return error('allocator verification incomplete; see ' + serial)
				}
				println(comparecore.lines(output).filter(it.starts_with('ALLOC-')).join('\n'))
			}
			flush_stdout()
			return VmCompleted{}
		}
		if sourcecommand.child_exited(pid)! {
			return error('QEMU exited; see ' + context.state + '/qemu.log')
		}
		checkpoint_sleep(if context.kind == .kernel {
			100 * time.millisecond
		} else {
			250 * time.millisecond
		})!
	}
	return error(if context.kind == .kernel {
		'kernel sampler timed out; see '
	} else {
		'guest timed out; see '
	} + serial)
}

pub fn capture_vm(argv []string, state string, timeout int, check bool, kind VinixKind) ! {
	context := VmContext{state, timeout, check, kind}
	cachecli.checkpoint()!
	// Completion markers deliberately end a still-running guest. The command
	// owner retires its private group before its sole reap on either outcome.
	sourcecommand.run_logged_owned(argv, os.environ(), cachecli.cancelled, state + '/qemu.log', false, '', observe_vm, unsafe { &context }, 5) or {
		if err is VmCompleted { return }
		return err
	}
}

const idle_source = "module idle\n#include <unistd.h>\nfn C.sleep(u32) u32\n@[export: 'main']\npub fn run() i32 { for { C.sleep(60) }; return 0 }\n"

fn build_idle(work string, cc string, rootfs string) ! {
	directory := work + '/idle'
	os.mkdir(directory)!
	os.write_file(directory + '/core.v', idle_source)!
	generated := work + '/init.c'
	generators.generate_module(directory, generated, 'amd64', ['nofloat'])!
	run([cc, '-std=c11', '-O2', '-static', '-Wall', '-Wextra', '-Werror', '-Wno-unused-function',
		'-Wno-unused-parameter', generated, '-o', rootfs + '/sbin/init'])!
}

pub fn prepare_vinix(options VinixOptions, kind VinixKind) !([]string, string) {
	kernel := resolve(options.kernel)!
	sysroot := if kind == .kernel { '' } else { resolve(options.sysroot)! }
	qemu := selected(options.qemu)!
	firmware := resolve(if options.firmware == '' {
		os.dir(os.dir(qemu)) + '/share/qemu/edk2-x86_64-code.fd'
	} else {
		options.firmware
	})!
	cc := if kind == .kernel { selected(options.cc)! } else { '' }
	mut required := [kernel, firmware]
	if kind == .kernel {
		required << [root() + '/kernel/heapbench/core.v', qemu, cc]
	} else {
		if kind == .current {
			required << [here() + '/benchcore/core.v', here() + '/benchcore/bench-native-abi.h']
		}
		required << ['usr/bin/gcc', 'bin/busybox', 'lib/ld-musl-x86_64.so.1', 'usr/lib/libc.a'].map(sysroot + '/' + it)
	}
	check := if options.allocator_check == '' { '' } else { resolve(options.allocator_check)! }
	if check != '' { required << check }
	if options.original_reference != '' { required << resolve(options.original_reference)! }
	for path in required {
		if !os.is_file(path) { return InputError{'required input missing: ' + path} }
	}
	if kind == .kernel {
		compiler := checked([cc, '--version'])!.stdout.to_lower()
		if compiler.contains('clang') || !compiler.contains('gcc') {
			return InputError{'--cc must be genuine GNU GCC'}
		}
	}
	work := hosttest.work_dir(if options.state == '' { '.' } else { options.state }, 'vinix-alloc-')!
	rootfs := work + '/rootfs'
	mut generation := map[string]json2.Any{}
	mut source_hash := ''
	if kind == .kernel {
		generators.generate_sampler(work + '/heap_benchmark.c', 'amd64', false)!
		source_hash = digest(work + '/heap_benchmark.c')!
		for name in ['sbin', 'dev', 'tmp', 'proc'] { make_dirs(rootfs + '/' + name)! }
		build_idle(work, cc, rootfs)!
	} else {
		copy_rootfs(sysroot, rootfs)!
		for name in ['dev', 'proc', 'sys', 'tmp', 'root', 'sbin'] {
			os.mkdir(rootfs + '/' + name) or { if !os.is_dir(rootfs + '/' + name) { return err } }
		}
		os.chmod(rootfs + '/tmp', 0o1777)!
		source := rootfs + '/root/alloc-bench.c'
		if kind == .current {
			generation = generators.generate_bench(source, 'amd64')!
		} else if options.original_reference != '' {
			os.cp(resolve(options.original_reference)!, source)!
		} else {
			// Historical C remains an immutable test input, recovered from its
			// recorded Git object rather than maintained or regenerated as C.
			original := checked(['git', '-C', root(), 'show', '5b37c952^:tests/alloc-bench/bench.c'])!.stdout
			os.write_file(source, original)!
		}
		source_hash = digest(source)!
		if check != '' { os.cp(check, rootfs + '/root/allocator-check.c')! }
		init := rootfs + '/sbin/init'
		if os.exists(init) || os.is_link(init) { os.rm(init)! }
		os.write_file(init, init_script(check != '', options.iterations, options.samples, kind == .current))!
		os.chmod(init, 0o755)!
	}
	initramfs := work + '/initramfs.tar'
	mut env := os.environ()
	env['COPYFILE_DISABLE'] = '1'
	logged(['tar', '--format=ustar', '-cf', initramfs, '-C', rootfs, '.'], env, work + '/archive.log', false, '', -1)!
	iso := work + '/vinix.iso'
	for key, value in {
		'VINIX_AMD64_ISO_BUILD_DIR': work + '/iso-build'
		'VINIX_AMD64_KERNEL':        kernel
		'VINIX_AMD64_INITRAMFS':     initramfs
		'VINIX_AMD64_ISO':           iso
	} {
		env[key] = value
	}
	logged([root() + '/build-support/build-amd64-iso.sh'], env, work + '/image-build.log', false, '', -1)!
	boot_kernel := if kind == .preboot {
		work + '/iso-build/iso-root/boot/vinix'
	} else {
		work + '/boot-kernel'
	}
	if kind != .preboot {
		logged(['xorriso', '-osirrox', 'on', '-indev', iso, '-extract', '/boot/vinix', boot_kernel], os.environ(), work + '/image-build.log', true, '', -1)!
		if digest(boot_kernel)! != digest(kernel)! {
			return error('kernel embedded in completed ISO differs from supplied kernel')
		}
	}
	command := vm_command(qemu, firmware, iso, work + '/serial.log', kind, options.cpus)
	mut config := {
		'qemu_version':  json2.Any(first_line(checked([qemu, '--version'])!.stdout)!)
		'machine':       json2.Any(machine)
		'accelerator':   json2.Any(accelerator)
		'cpu':           json2.Any(cpu)
		'smp':           json2.Any(command[command.index('-smp') + 1])
		'memory_mb':     json2.Any(4096)
		'source_sha256': json2.Any(source_hash)
		'kernel_sha256': json2.Any(digest(boot_kernel)!)
		'compile_flags': json2.Any((if kind == .kernel { kernel_flags } else { benchmark_flags }).map(json2.Any(it)))
		'argv':          json2.Any(command.map(json2.Any(it)))
	}
	if kind != .preboot {
		config['kernel_verification'] = 'extracted from completed ISO and matched supplied kernel'
	}
	if kind == .kernel {
		config['sampler_header_sha256'] = digest(root() + '/kernel/c/heap_benchmark_v.h')!
		config['sampler_language'] = 'V'
		config['platform_compile_flags'] = ['-fno-PIC', '-mcmodel=kernel'].map(json2.Any(it))
		config['sampler_build_provenance'] = 'caller must verify supplied kernel used the recorded source and flags'
		config['execution_context'] = 'pre-scheduler'
	} else {
		config['iterations'] = options.iterations
		config['samples'] = options.samples
		if kind == .current {
			config['v_generation'] = generation
			config['native_header_sha256'] = generation['native_header_sha256']!
		}
		config['libc_sha256'] = digest(rootfs + '/lib/ld-musl-x86_64.so.1')!
		config['libc_a_sha256'] = digest(rootfs + '/usr/lib/libc.a')!
		manifest := rootfs + '/usr/share/vinix/musl-build.json'
		if os.is_file(manifest) {
			data := hosttest.decode_json(os.read_file(manifest)!)!
			config['libc_build'] = data
			for field, actual in {
				'libc_so_sha256': config['libc_sha256']!
				'libc_a_sha256':  config['libc_a_sha256']!
			} {
				if (data.as_map()[field] or { json2.Any(json2.Null{}) }) != actual {
					return error('staged libc does not match build manifest: ' + field)
				}
			}
		}
		if check != '' {
			config['allocator_check_sha256'] = digest(rootfs + '/root/allocator-check.c')!
		}
	}
	write_json(work + '/config.json', config)!
	println(if kind == .kernel {
		'Booting kernel sampler; output: '
	} else {
		'Booting benchmark; output: '
	} + work + '/serial.log')
	flush_stdout()
	return command, work
}
