// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import os
import time

fn command(args []string) ! {
	println('  ' + args.join(' '))
	mut child := os.new_process(args[0])
	child.set_args(args[1..])
	child.wait()
	code := child.code
	child.close()
	if code != 0 { return error('${args[0]} failed (${code})') }
}

fn tool(env string, fallback string) !string {
	name := os.getenv_opt(env) or { fallback }
	return os.find_abs_path_of_executable(name)
}

fn zig_headers(zig string) !string {
	mut child := os.new_process(zig)
	child.set_args(['env'])
	child.set_redirect_stdio()
	child.run()
	text := child.stdout_slurp()
	child.wait()
	defer { child.close() }
	if child.code != 0 { return error('zig env failed') }
	// Zig 0.14+ emits ZON; earlier releases emit JSON.
	for line in text.split_into_lines() {
		if line.trim_space().starts_with('.lib_dir = ') || line.trim_space().starts_with('"lib_dir":') {
			path := line.all_after(if line.contains('=') { '=' } else { ':' }).trim_space().trim_right(',').trim('"')
			if os.is_dir(path + '/libc/include/generic-musl') { return path + '/libc/include' }
		}
	}
	return error('Cannot locate Zig musl headers')
}

fn build(root string, output string) ! {
	os.mkdir_all(output)!
	v := tool('VINIX_V_COMPILER', 'v')!
	zig := tool('VINIX_PPC_ZIG', 'zig')!
	headers := zig_headers(zig)!
	command([v, '-shared', '-no-builtin', '-no-closures', '-enable-globals', '-os', 'vinix', '-arch',
		'ppc', '-target-libc-headers', '-nofloat', '-gc', 'none', '-manualfree', '-o',
		output + '/loader.c', root + '/powerpc-boot'])!
	// Use musl's type declarations, but the V freestanding runtime owns
	// memcpy/memset. V's exported voidptr lacks C's const qualifier.
	command([zig, 'cc', '-target', 'powerpc-linux-musl', '-mcpu=7450', '-O2',
		'-D_STRING_H', '-isystem', headers + '/powerpc-linux-musl', '-isystem', headers + '/generic-musl',
		'-isystem', headers + '/powerpc-linux-any', '-isystem', headers + '/any-linux-any',
		'-ffreestanding', '-fno-builtin', '-fno-stack-protector', '-fno-pic', '-fno-pie',
		'-ffunction-sections', '-fdata-sections', '-mno-altivec', '-nostdlib', '-static',
		'-Wl,--gc-sections', '-Wl,--build-id=none', '-Wl,-e,vinix_of_entry',
		'-Wl,-T,' + root + '/powerpc-boot/linker.ld', output + '/loader.c', '-o',
		output + '/vinix-of.elf'])!
	command([zig, 'objcopy', '-O', 'binary', output + '/vinix-of.elf', output + '/vinix-of.bin'])!
	for name in ['vinix-of.elf', 'vinix-of.bin'] {
		data := os.read_bytes(output + '/' + name)!
		os.write_file(output + '/' + name + '.sha256', sha256.hexhash(data.bytestr()) + '  ' + name + '\n')!
	}
}

fn boot(output string, test bool) ! {
	qemu := tool('VINIX_PPC_QEMU', 'qemu-system-ppc')!
	mut args := ['-M', 'mac99,via=pmu', '-cpu', '7450', '-accel', 'tcg', '-m', '512', '-smp', '1',
		'-nic', 'none', '-kernel', output + '/vinix-of.bin', '-no-reboot']
	if !test {
		args << ['-serial', 'stdio']
		mut argv := [qemu]
		argv << args
		command(argv)!
		return
	}
	args << ['-nographic', '-monitor', 'none']
	mut child := os.new_process(qemu)
	child.set_args(args)
	child.set_redirect_stdio_merged()
	child.run()
	defer {
		if child.is_alive() { child.signal_kill() }
		child.wait()
		child.close()
	}
	mut log := ''
	deadline := time.now().add(20 * time.second)
	for time.now() < deadline && child.is_alive() {
		if child.is_pending(.stdout) {
			chunk := child.stdout_read()
			log += chunk
			print(chunk)
		}
		if log.contains('VINIX-PPC: PASS ppc32 big-endian firmware') { break }
		time.sleep(10 * time.millisecond)
	}
	os.write_file(output + '/boot.log', log)!
	if !log.contains('VINIX-PPC: PASS ppc32 big-endian firmware') {
		return error('PPC boot did not reach the firmware milestone; see ${output}/boot.log')
	}
}

fn main() {
	root := os.real_path(@VMODROOT + '/../..')
	mut output := os.join_path(os.temp_dir(), 'vinix-powerpc-' + sha256.hexhash(root)[..12])
	args := os.args[1..]
	if args.len == 0 || args[0] !in ['build', 'run', 'test'] {
		eprintln('Usage: v run tools/powerpc {build|run|test} [OUTPUT_DIRECTORY]')
		exit(2)
	}
	if args.len > 2 {
		eprintln('Too many arguments')
		exit(2)
	}
	if args.len == 2 { output = os.abs_path(args[1]) }
	build(root, output) or {
		eprintln(err)
		exit(1)
	}
	println('PowerPC build: ${output}')
	if args[0] != 'build' {
		boot(output, args[0] == 'test') or {
			eprintln(err)
			exit(1)
		}
	}
}
