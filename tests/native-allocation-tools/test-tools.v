// SPDX-License-Identifier: GPL-2.0-or-later
module main

import allocationhost
import crypto.sha256
import hosttest
import json2
import os
import plist
import sourcecommand
import time

#include <signal.h>
#include <fcntl.h>

fn C.kill(i32, i32) i32

fn record_tool(name string, args []string) ! {
	path := os.getenv('VINIX_ALLOC_FIXTURE') + '/commands.jsonl'
	mut file := os.open_append(path)!
	defer { file.close() }
	file.write_string(json2.encode({
		'tool':         json2.Any(name)
		'argv':         json2.Any(args.map(json2.Any(it)))
		'cwd':          json2.Any(os.getwd())
		'library_path': json2.Any(os.getenv('DYLD_LIBRARY_PATH'))
	}) + '\n')!
}

fn seed_limine(work string) ! {
	path := work + '/iso-build/limine'
	mkdir_literal(path)!
	for name in ['BOOTX64.EFI', 'limine-uefi-cd.bin', 'limine-bios-cd.bin', 'limine-bios.sys',
		'limine.c', 'limine-bios-hdd.h'] {
		os.cp(os.getenv('VINIX_ALLOC_LIMINE') + '/' + name, path + '/' + name)!
	}
	os.cp(os.executable(), path + '/limine')!
	os.chmod(path + '/limine', 0o755)!
	os.utime(path + '/limine', time.now().unix() + 5, time.now().unix() + 5)!
}

fn mkdir_literal(path string) ! {
	if os.is_dir(path) { return }
	parent := path.all_before_last('/')
	if parent != '' && parent != path { mkdir_literal(parent)! }
	os.mkdir(path)!
}

fn fake_tool(name string, args []string) ! {
	record_tool(name, args)!
	work := os.getenv('VINIX_ALLOC_FIXTURE')
	mode := os.getenv('VINIX_ALLOC_MODE')
	if name == 'blocked-v' && args == ['version'] {
		println('V 0.5.1 controlled compiler')
		return
	}
	if name == 'blocked-v' || (name == 'fake-darwin-gcc' && '-S' in args && mode == 'blocked-kext') {
		blocked(work)!
		return
	}
	match name {
		'tar' {
			p := os.exec(['/usr/bin/tar', ...args])
			if p.exit_code != 0 {
				eprint(p.output)
				exit(p.exit_code)
			}
			if '-cf' in args { seed_limine(os.dir(args[args.index('-cf') + 1]))! }
		}
		'limine' { println('fixture Limine install') }
		'xorriso' {
			if '-as' in args {
				os.write_file(args[args.index('-o') + 1], 'controlled ISO')!
				os.cp(os.getenv('VINIX_AMD64_KERNEL'), os.getenv('VINIX_AMD64_ISO') + '.kernel')!
				println('fixture ISO built')
				eprintln('fixture ISO stderr')
			} else if '-extract' in args {
				iso := args[args.index('-indev') + 1]
				destination := args[args.index('-extract') + 2]
				if mode == 'wrong-kernel' {
					os.write_file(destination, 'different kernel')!
				} else {
					os.cp(iso + '.kernel', destination)!
				}
				println('fixture kernel extracted')
			} else {
				return error('unexpected xorriso arguments')
			}
		}
		'qemu-system-x86_64' {
			if args == ['--version'] {
				println('QEMU emulator version 10.0.0')
				return
			}
			serial := args[args.index('-serial') + 1].all_after('file:')
			state := os.dir(serial)
			mut child := os.new_process('/bin/sleep')
			child.set_args(['600'])
			child.run()
			os.write_file(state + '/pids', os.getpid().str() + '\n' + child.pid.str() + '\n')!
			text := match mode {
				'failure' {
					'ALLOC-COMPILE-BEGIN\nALLOC-FAIL stage=compile\nALLOC-DONE\nALLOC-GUEST-DONE\n'
				}
				'incomplete' { 'ALLOC-COMPILE-DONE\nALLOC-GUEST-DONE\n' }
				'checks-missing' { 'ALLOC-DONE\nALLOC-GUEST-DONE\n' }
				'duplicate-checks' {
					'UALLOC-DONE dynamic\nUALLOC-DONE static\nUALLOC-DONE extra\nUALLOC-VERIFY-COMPLETE\nALLOC-DONE\nALLOC-GUEST-DONE\n'
				}
				'kernel' { os.read_file(os.getenv('VINIX_ALLOC_KERNEL_LOG'))! }
				'timeout', 'early-exit' { 'heap-bench: done\n' }
				else {
					'heap-bench: done\nALLOC-COMPILE-BEGIN\nUALLOC-DONE dynamic\nUALLOC-DONE static\nUALLOC-VERIFY-COMPLETE\nALLOC-COMPILE-DONE\nALLOC-RESULT fixture\nALLOC-DONE\nALLOC-GUEST-DONE\n'
				}
			}
			os.write_file(serial, text)!
			print('o'.repeat(200000))
			eprint('e'.repeat(200000))
			flush_stdout()
			flush_stderr()
			os.write_file(state + '/ready', 'ready')!
			if mode == 'early-exit' { exit(7) }
			for { time.sleep(20 * time.millisecond) }
		}
		'fake-gcc' {
			if args == ['--version'] {
				println(if mode == 'clang-cc' { 'clang 19' } else { 'gcc 14.2.0' })
				return
			}
			p := os.exec([os.getenv('VINIX_ALLOC_REAL_GCC'), ...args])
			print(p.output)
			exit(p.exit_code)
		}
		'fake-darwin-gcc' {
			if '-dM' in args {
				println('#define __GNUC__ 14\n#define __APPLE__ 1\n#define __x86_64__ 1' + if mode == 'clang-kext' {
					'\n#define __clang__ 1'
				} else {
					''
				})
				return
			}
			if args == ['--version'] {
				println('gcc (controlled Darwin) 14.2.0')
				return
			}
			if args == ['-print-file-name=include'] {
				println(work + '/includes')
				return
			}
			if '-S' in args {
				os.write_file(args[args.index('-o') + 1], '// controlled GCC assembly\n')!
				println('gcc assembly')
				return
			}
			return error('unexpected GCC arguments')
		}
		'xcrun' {
			os.write_file(args[args.index('-o') + 1], 'controlled assembler/linker artifact')!
			println('xcrun ' + args[0])
		}
		'scp' {
			if args[args.len - 2].contains(':') && args.last().ends_with('bench.s') {
				os.write_file(args.last(), '// controlled guest assembly\n')!
			}
			println('controlled transfer')
		}
		'ssh' {
			command := args.last()
			if command.contains('-print-file-name=include') {
				println('/guest GCC/include')
				return
			}
			if command.contains('exec ') && command.contains('--label macos') {
				if mode == 'ssh-failure' {
					println('ALLOC-FAIL stage=benchmark')
					exit(7)
				}
				if mode == 'ssh-timeout' {
					blocked(work)!
					return
				}
				println('ALLOC-COMPILE-DONE\nALLOC-RESULT controlled\nALLOC-DONE')
				return
			}
			if command.contains('bench_pid=') {
				os.write_file(work + '/remote-retired', command)!
				return
			}
			println('controlled SSH')
		}
		else { return error('unknown fake tool') }
	}
}

fn invoke(args []string, timeout f64) !sourcecommand.Output {
	return sourcecommand.capture([os.getenv('VINIX_ALLOC_NATIVE_TOOL'), ...args], os.environ(), timeout, 8 * 1024 * 1024, unsafe { nil })!
}

fn setup(work string) ! {
	os.mkdir(work)!
	os.mkdir(work + '/bin')!
	os.mkdir(work + '/includes')!
	os.setenv('VINIX_ALLOC_FIXTURE', work, true)
	os.setenv('PATH', work + '/bin:' + os.getenv('PATH'), true)
	for name in ['tar', 'xorriso', 'qemu-system-x86_64', 'fake-gcc', 'fake-darwin-gcc', 'xcrun',
		'scp', 'ssh', 'blocked-v'] {
		os.cp(os.executable(), work + '/bin/' + name)!
		os.chmod(work + '/bin/' + name, 0o755)!
	}
	for path in ['usr/bin', 'bin', 'lib', 'usr/lib', 'usr/share/vinix'] {
		os.mkdir_all(work + '/sysroot/' + path)!
	}
	for path in ['usr/bin/gcc', 'bin/busybox', 'lib/ld-musl-x86_64.so.1', 'usr/lib/libc.a'] {
		os.write_file(work + '/sysroot/' + path, 'controlled input ' + path)!
	}
	os.symlink('/bin/busybox', work + '/sysroot/bin/sh')!
	os.symlink('missing-target', work + '/sysroot/dangling')!
	os.write_file(work + '/kernel', 'controlled supplied kernel')!
	os.write_file(work + '/firmware', 'controlled firmware')!
	os.write_file(work + '/allocator.c', 'immutable controlled input')!
	os.write_file(work + '/config.json', '{"qemu_version":"QEMU emulator version 10.0.0","machine":"q35,vmport=off","accelerator":"tcg,thread=single,tb-size=1024","cpu":"Penryn","smp":"2,sockets=1,cores=2,threads=1","memory_mb":4096}\n')!
}

fn retired(state string) ! {
	ids := os.read_file(state + '/pids')!.split_into_lines().map(it.int())
	deadline := time.sys_mono_now() + u64(5 * time.second)
	for ids.any(C.kill(it, 0) == 0) && time.sys_mono_now() < deadline {
		time.sleep(20 * time.millisecond)
	}
	assert ids.all(C.kill(it, 0) != 0), 'QEMU descendants survived'
}

fn vm_cases(work string) ! {
	for kind in ['vinix', 'vinix-saved', 'vinix-preboot', 'kernel'] {
		for mode in if kind == 'kernel' {
			['kernel', 'early-exit', 'timeout', 'wrong-kernel', 'clang-cc']
		} else if kind == 'vinix-preboot' {
			['success']
		} else {
			['success', 'failure', 'incomplete', 'checks-missing', 'duplicate-checks', 'early-exit',
				'timeout', 'wrong-kernel']
		} {
			state := work + '/' + kind + '-' + mode
			os.setenv('VINIX_ALLOC_MODE', mode, true)
			mut args := [kind, '--kernel', work + '/kernel', '--firmware', work + '/firmware',
				'--state-dir', state, '--qemu', work + '/bin/qemu-system-x86_64', '--timeout',
				'1']
			if kind == 'kernel' {
				args << ['--cc', work + '/bin/fake-gcc']
			} else {
				args << ['--sysroot', work + '/sysroot', '--allocator-check', work + '/allocator.c']
			}
			result := invoke(args, 90)!
			expected := if mode == 'clang-cc' {
				2
			} else if mode == 'kernel' || (mode == 'success' && kind != 'vinix-preboot') {
				0
			} else {
				1
			}
			assert result.status == expected, args.str() + result.str()
			if os.exists(state + '/pids') { retired(state)! }
			if mode == 'success' && kind != 'vinix-preboot' {
				assert os.file_size(state + '/qemu.log') == 400000
				assert os.read_file(state + '/image-build.log')!.contains('fixture ISO built\nfixture ISO stderr\n')
				assert os.read_file(state + '/image-build.log')!.ends_with('fixture kernel extracted\n')
				assert os.readlink(state + '/rootfs/bin/sh')! == '/bin/busybox'
				assert os.readlink(state + '/rootfs/dangling')! == 'missing-target'
				assert os.stat(state + '/rootfs/tmp')!.mode & 0o7777 == 0o1777
				config := hosttest.decode_json(os.read_file(state + '/config.json')!)!.as_map()
				assert config['kernel_sha256']!.str() == sha256.sum(os.read_bytes(work + '/kernel')!).hex()
				assert config['kernel_verification']!.str() == 'extracted from completed ISO and matched supplied kernel'
				if kind == 'vinix' {
					assert 'v_generation' in config
				} else {
					assert 'v_generation' !in config
				}
			}
			println('VM / image / markers / retirement: PASS ' + kind + ' ' + mode)
			flush_stdout()
		}
	}
}

fn mac_cases(work string) ! {
	for sdk in [false, true] {
		for mode in ['success', 'ssh-failure', 'ssh-timeout'] {
			os.setenv('VINIX_ALLOC_MODE', mode, true)
			os.rm(work + '/remote-retired') or {}
			state := work + '/mac-' + sdk.str() + '-' + mode
			mut args := ['macos', '--port', '2222', '--user', 'test-user', '--identity',
				work + "/identity 'quote'", '--vm-config', work + '/config.json', '--state-dir',
				state, '--gcc', "/guest/gcc 'quoted'", '--timeout', '1']
			if sdk {
				args << ['--guest-sdk', "/guest/sdk 'quoted'", '--host-sdk', work + '/host-sdk']
			}
			result := invoke(args, 90)!
			assert result.status == if mode == 'success' { 0 } else { 1 }, result.str()
			if mode != 'success' {
				assert os.exists(work + '/remote-retired')
				assert os.read_file(work + '/remote-retired')!.contains('ps -p "$bench_pid" -o command=')
			}
			config := hosttest.decode_json(os.read_file(state + '/config.json')!)!.as_map()
			assert config['build_method']!.str() == if sdk {
				'guest GCC C-to-assembly; host Apple assembler/linker'
			} else {
				'guest GCC driver'
			}
			assert config['guest_compile_command']!.str().contains('\'"\'"\'')
			assert ('host_link_command' in config) == sdk
			println('SSH / driver / SDK / failure cleanup: PASS ' + sdk.str() + ' ' + mode)
			flush_stdout()
		}
	}
	for mode in ['success', 'clang-kext'] {
		os.setenv('VINIX_ALLOC_MODE', mode, true)
		state := work + '/kext-' + mode
		result := invoke(['kext', '--gcc', work + '/bin/fake-darwin-gcc', '--library-path',
			'/controlled/lib', '--vm-config', work + '/config.json', '--state-dir', state], 90)!
		assert result.status == if mode == 'success' { 0 } else { 2 }, result.str()
		if mode == 'success' {
			manifest := hosttest.decode_json(os.read_file(state + '/config.json')!)!.as_map()
			assert manifest['build_commands']!.as_array().len == 5
			frozen := hosttest.decode_json(os.read_file(allocationhost.root() + '/tests/alloc-bench/results/2026-10-02/kernel-macos-1/config.json')!)!.as_map()
			assert manifest['compile_flags']!.as_array() == frozen['compile_flags']!.as_array()
			assert manifest['platform_compile_flags']!.as_array() == frozen['platform_compile_flags']!.as_array()
			assert manifest['compiler_library_path']!.str() == '/controlled/lib'
			assert manifest['binary_sha256']!.str() == sha256.sum(os.read_bytes(state + '/AllocKernelBench.kext/Contents/MacOS/AllocKernelBench')!).hex()
			info := plist.parse(os.read_bytes(state + '/AllocKernelBench.kext/Contents/Info.plist')!)!
			assert info.kind == .dictionary && info.fields.len == 10
			for field, expected in {
				'CFBundleDevelopmentRegion':     'English'
				'CFBundleExecutable':            'AllocKernelBench'
				'CFBundleIdentifier':            'org.vinix.AllocKernelBench'
				'CFBundleInfoDictionaryVersion': '6.0'
				'CFBundleName':                  'AllocKernelBench'
				'CFBundlePackageType':           'KEXT'
				'CFBundleShortVersionString':    '1.0.0'
				'CFBundleVersion':               '1.0.0'
				'OSBundleRequired':              'Root'
			} {
				assert info.fields[field]!.kind == .string && info.fields[field]!.text == expected
			}
			libraries := info.fields['OSBundleLibraries']!
			assert libraries.kind == .dictionary && libraries.fields.len == 2
			for field in ['com.apple.kpi.iokit', 'com.apple.kpi.libkern'] {
				assert libraries.fields[field]!.text == '8.0.0'
			}
			info.free()
		} else {
			assert !os.exists(state)
		}
		println('KEXT / probes / recipes / bundle / manifest: PASS ' + mode)
		flush_stdout()
	}
}

fn main() {
	name := os.base(os.args[0])
	if name in ['tar', 'limine', 'xorriso', 'qemu-system-x86_64', 'fake-gcc', 'fake-darwin-gcc',
		'xcrun', 'scp', 'ssh', 'blocked-v'] {
		fake_tool(name, os.args[1..]) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len == 3 && os.args[1] == '--drivers' {
		setup(os.args[2]) or {
			eprintln(err)
			exit(1)
		}
		driver_cases(os.args[2]) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	if os.args.len != 2 {
		eprintln('usage: test-tools NEW_STATE')
		exit(2)
	}
	setup(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
	vm_cases(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
	mac_cases(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
	cli_cases(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
	signal_cases(os.args[1]) or {
		eprintln(err)
		exit(1)
	}
	println('NATIVE ALLOCATION CONTROLLERS: PASS')
}

fn blocked(work string) ! {
	state := os.getenv_opt('VINIX_ALLOC_BLOCK_STATE') or { work }
	mut child := os.new_process('/bin/sleep')
	child.set_args(['600'])
	child.run()
	os.write_file(state + '/pids', os.getpid().str() + '\n' + child.pid.str() + '\n')!
	println('partial controlled output')
	flush_stdout()
	os.write_file(state + '/ready', 'ready')!
	for { time.sleep(20 * time.millisecond) }
}

struct SignalCase {
	work   string
	signal int
}

fn notify(pid int, pointer voidptr) ! {
	context := unsafe { &SignalCase(pointer) }
	deadline := time.sys_mono_now() + u64(45 * time.second)
	for !os.exists(context.work + '/ready') {
		if sourcecommand.child_exited(pid)! || time.sys_mono_now() >= deadline {
			return error('allocation signal fixture was not ready')
		}
		time.sleep(20 * time.millisecond)
	}
	assert C.kill(pid, context.signal) == 0
}

fn cli_cases(work string) ! {
	for args in [['vinix'], ['kernel'], ['macos'], ['kext'], ['measure'], ['control'],
		['vinix-driver'], ['macos-driver'], ['vinix', '--timeout', 'bad'],
		['bench', '--host-arch', 'wrong'], ['sampler', '--model'], ['bench', '--build-only'],
		['bench', '--arch', 'x86_64'], ['kernel', '--sysroot', 'wrong'], ['vinix', '--cpus', '2'],
		['control', '--bad']] {
		result := invoke(args, 30)!
		assert result.status == 2, args.str() + result.str()
	}
	protected := work + '/protected'
	os.mkdir(protected)!
	os.write_file(protected + '/keep', 'unchanged')!
	for kind in ['bench', 'sampler', 'vinix', 'kernel', 'macos', 'kext', 'measure'] {
		mut args := [kind]
		if kind == 'measure' {
			args << [protected, '--runtime', work, '--config', work + '/config.json']
		} else {
			args << ['--state-dir', protected]
		}
		if kind in ['vinix', 'kernel'] {
			args << ['--kernel', work + '/kernel', '--firmware', work + '/firmware', '--qemu',
				work + '/bin/qemu-system-x86_64']
		}
		if kind == 'vinix' { args << ['--sysroot', work + '/sysroot'] }
		if kind == 'kernel' { args << ['--cc', work + '/bin/fake-gcc'] }
		if kind == 'macos' {
			args << ['--port', '2222', '--user', 'test', '--identity', work + '/id', '--vm-config',
				work + '/config.json']
		}
		if kind == 'kext' { args << ['--gcc', work + '/bin/fake-darwin-gcc'] }
		os.setenv('VINIX_ALLOC_MODE', 'success', true)
		result := invoke(args, 30)!
		assert result.status == 1, result.str()
		assert os.read_file(protected + '/keep')! == 'unchanged'
	}
	println('ALLOCATION CLI / rejected options / protected state: PASS')
	flush_stdout()
}

fn signal_cases(work string) ! {
	for kind in ['bench', 'sampler', 'vinix', 'kernel', 'macos', 'kext'] {
		for signal in [2, 15] {
			if kind == 'macos' { os.rm(work + '/remote-retired') or {} }
			state := work + '/signal-' + kind + '-' + signal.str()
			mut args := [kind, '--state-dir', state]
			fixture := if kind in ['bench', 'sampler'] {
				work + '/blocked-' + kind + '-' + signal.str()
			} else {
				state
			}
			if kind in ['bench', 'sampler'] {
				os.mkdir(fixture)!
				os.setenv('V', work + '/bin/blocked-v', true)
			}
			os.setenv('VINIX_ALLOC_FIXTURE', fixture, true)
			os.setenv('VINIX_ALLOC_MODE', if kind == 'macos' {
				'ssh-timeout'
			} else if kind == 'kext' {
				'blocked-kext'
			} else {
				'timeout'
			}, true)
			if kind in ['vinix', 'kernel'] {
				args << ['--kernel', work + '/kernel', '--firmware', work + '/firmware', '--qemu',
					work + '/bin/qemu-system-x86_64']
			}
			if kind == 'vinix' { args << ['--sysroot', work + '/sysroot'] }
			if kind == 'kernel' { args << ['--cc', work + '/bin/fake-gcc'] }
			if kind == 'macos' {
				args << ['--port', '2222', '--user', 'test', '--identity', work + '/id', '--vm-config',
					work + '/config.json']
			}
			if kind == 'kext' { args << ['--gcc', work + '/bin/fake-darwin-gcc'] }
			// Tar fixtures seed only the exact pinned Limine inputs. Their record
			// directory must exist before image construction creates the state.
			os.setenv('VINIX_ALLOC_FIXTURE', work, true)
			if kind in ['bench', 'sampler', 'macos', 'kext'] {
				os.setenv('VINIX_ALLOC_BLOCK_STATE', fixture, true)
			}
			data := SignalCase{fixture, signal}
			result := sourcecommand.capture_owned([
				os.getenv('VINIX_ALLOC_NATIVE_TOOL'),
				...args,
			], os.environ(), 60, 8 * 1024 * 1024, unsafe { nil }, unsafe { nil }, notify, unsafe { &data }, 0)!
			if kind in ['bench', 'sampler'] {
				os.setenv('V', os.getenv('VINIX_ALLOC_REAL_V'), true)
			}
			os.unsetenv('VINIX_ALLOC_BLOCK_STATE')
			assert result.status == 128 + signal, kind + result.str()
			retired(fixture)!
			if kind == 'macos' {
				assert os.exists(work + '/remote-retired')
			}
			println('ALLOCATION signal / partial output / private descendants: PASS ' + kind + ' ' + signal.str())
			flush_stdout()
		}
	}
}

fn driver_cases(input string) ! {
	work := os.real_path(input)
	base := work + '/driver-home'
	os.mkdir_all(base + '/scripts')!
	os.mkdir(base + '/build')!
	os.mkdir_all(base + '/third_party/useralloc-libc/build/useralloc')!
	os.symlink(work + '/sysroot', base + '/third_party/useralloc-libc/build/useralloc/variant')!
	os.mkdir_all(work + '/share/qemu')!
	os.cp(work + '/firmware', work + '/share/qemu/edk2-x86_64-code.fd')!
	origin := base + '/scripts/driver'
	os.write_file(origin, 'native driver origin')!
	for mode in ['success', 'early-exit'] {
		os.setenv('VINIX_ALLOC_MODE', mode, true)
		name := 'run with \\literal.' + mode
		state := base + '/build/' + name
		result := invoke(['vinix-driver', origin, name,
			if mode == 'success' { 'variant' } else { work + '/sysroot' }, work + '/kernel'], 90)!
		assert result.status == if mode == 'success' { 0 } else { 1 }, result.str()
		retired(state)!
		record := hosttest.decode_json(os.read_file(hosttest.replace_suffix(state, '.exit.json'))!)!.as_map()
		assert record['exit_code']!.int() == result.status
		assert record['argv']!.as_array()[1]!.str() == 'vinix'
		assert record['argv']!.as_array().map(it.str()).contains(work + '/kernel')
		for key in ['started_utc', 'finished_utc'] {
			assert record[key]!.str().contains('T') && record[key]!.str().ends_with('+00:00')
		}
		assert os.read_file(hosttest.replace_suffix(state, '.runner.log'))!.contains(if mode == 'success' {
			'ALLOC-DONE'
		} else {
			'QEMU exited'
		})
		commands := os.read_file(work + '/commands.jsonl')!.split_into_lines().map(hosttest.decode_json(it) or { panic(err) })
		qemu := commands.filter(it.as_map()['tool'] or { json2.Any('') } == json2.Any('qemu-system-x86_64'))
		assert qemu.last().as_map()['cwd']!.str() == base
	}
	missing := invoke(['vinix-driver', origin, 'missing', 'variant', work + '/missing-kernel'], 30)!
	assert missing.status == 1 && !os.exists(base + '/build/missing.exit.json')
	for valid in [true, false] {
		manifest := work + '/sysroot/usr/share/vinix/musl-build.json'
		os.write_file(manifest, json2.encode({
			'libc_so_sha256': json2.Any(if valid {
				sha256.sum(os.read_bytes(work + '/sysroot/lib/ld-musl-x86_64.so.1')!).hex()
			} else {
				'wrong'
			})
			'libc_a_sha256':  json2.Any(sha256.sum(os.read_bytes(work + '/sysroot/usr/lib/libc.a')!).hex())
		}))!
		os.setenv('VINIX_ALLOC_MODE', 'success', true)
		state := work + '/manifest-' + valid.str()
		result := invoke(['vinix', '--kernel', work + '/kernel', '--sysroot', work + '/sysroot',
			'--state-dir', state, '--firmware', work + '/firmware', '--qemu',
			work + '/bin/qemu-system-x86_64', '--build-only'], 90)!
		assert result.status == if valid { 0 } else { 1 }, result.str()
		if valid {
			assert os.exists(state + '/config.json')
		} else {
			assert result.stderr.contains('staged libc does not match build manifest') && !os.exists(state + '/config.json')
		}
	}
	println('SAVED VINIX DRIVERS / cwd / literal paths / success and failure exit records / libc hash admission: PASS')
}
