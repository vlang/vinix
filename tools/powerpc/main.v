// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import os
import strconv
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
	preserve_sources(root, output, v, zig)!
	cross_build(root, output, v, zig, headers, 'powerpc-boot', 'loader', 'vinix-of', 'vinix_of_entry')!
	cross_build(root, output, v, zig, headers, 'tests/powerpc/handoff', 'probe', 'handoff-probe', 'vinix_handoff_probe')!
	cross_build(root, output, v, zig, headers, 'kernel/powerpc/start', 'kernel', 'vinix-ppc', 'vinix_ppc_entry')!
	cross_build(root, output, v, zig, headers, 'userland/powerpc/init', 'init', 'init-ppc', 'vinix_user_init')!
	make_ramfs(output)!
	command([zig, 'objcopy', '-O', 'binary', output + '/vinix-of.elf', output + '/vinix-of.bin'])!
	make_iso(output)!
	for name in ['vinix-of.elf', 'vinix-of.bin', 'handoff-probe.elf', 'vinix-ppc-boot.iso'] {
		data := os.read_bytes(output + '/' + name)!
		os.write_file(output + '/' + name + '.sha256', sha256.hexhash(data.bytestr()) + '  ' + name + '\n')!
	}
}

fn cross_build(root string, output string, v string, zig string, headers string, source string, generated string, binary string, entry string) ! {
	command([v, '-shared', '-no-builtin', '-no-closures', '-enable-globals', '-os', 'vinix', '-arch',
		'ppc', '-target-libc-headers', '-nofloat', '-gc', 'none', '-manualfree', '-o',
		output + '/${generated}.c', '-path', '@vlib|' + root + '/kernel', root + '/' + source])!
	// Use musl's type declarations, but the V freestanding runtime owns
	// memcpy/memset. V's exported voidptr lacks C's const qualifier.
	command([zig, 'cc', '-target', 'powerpc-linux-musl', '-mcpu=7450', '-O2', '-D_STRING_H', '-isystem',
		headers + '/powerpc-linux-musl', '-isystem', headers + '/generic-musl', '-isystem',
		headers + '/powerpc-linux-any', '-isystem', headers + '/any-linux-any', '-ffreestanding',
		'-fno-builtin', '-fno-stack-protector', '-fno-pic', '-fno-pie', '-ffunction-sections',
		'-fdata-sections', '-mno-altivec', '-nostdlib', '-static', '-Wl,--gc-sections',
		'-Wl,--build-id=none', '-Wl,-e,' + entry, '-Wl,-T,' + root + '/' + source + '/linker.ld',
		output + '/${generated}.c', '-o', output + '/${binary}.elf'])!
}

fn boot(output string, test bool, media bool, kernel bool, shell bool) ! {
	qemu := tool('VINIX_PPC_QEMU', 'qemu-system-ppc')!
	mut args := ['-M', 'mac99,via=pmu', '-cpu', '7450', '-accel', 'tcg', '-m', '512', '-smp', '1',
		'-nic', 'none', '-no-reboot']
	if media {
		args << ['-cdrom', output + '/vinix-ppc-boot.iso', '-boot', 'd', '-prom-env',
			'boot-device=cd:\\BOOT.ELF;1', '-prom-env',
			if shell {
				'boot-file=cd:\\KERNEL.ELF;1 cd:\\RAMFS.TAR;1'
			} else if kernel {
				'boot-file=cd:\\KERNEL.ELF;1'
			} else {
				'boot-file=cd:\\PROBE.ELF;1'
			}]
	} else {
		args << ['-kernel', output + '/vinix-of.bin']
	}
	if !test {
		args << ['-nographic', '-serial', 'mon:stdio']
		mut argv := [qemu]
		argv << args
		command(argv)!
		return
	}
	log_path := output + if kernel {
		'/kernel-boot.log'
	} else if media {
		'/media-boot.log'
	} else {
		'/boot.log'
	}
	marker := if shell {
		'vinix$ '
	} else if kernel {
		'VINIX-PPC: PASS userspace MMU syscall and protection'
	} else if media {
		'VINIX-PPC: PASS ELF32 handoff probe'
	} else {
		'VINIX-PPC: PASS firmware discovery'
	}
	os.write_file(log_path, '')!
	args << ['-nographic', '-monitor', 'stdio']
	if shell {
		args << ['-chardev', 'socket,id=console,path=' + (output + '/serial.sock').replace(',', ',,') +
			',server=on,wait=off,logfile=' + log_path.replace(',', ',,'), '-serial', 'chardev:console']
	} else {
		args << ['-serial', 'file:' + log_path]
	}
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
		log = os.read_file(log_path)!
		if log.contains(marker) || log.contains('VINIX-PPC: FAIL') || log.contains('VINIX-PPC: PANIC') {
			break
		}
		time.sleep(10 * time.millisecond)
	}
	print(log)
	if !log.contains('VINIX-PPC: PASS firmware discovery')
		|| !log.contains('VINIX-PPC: PASS cpu clock atomics cache')
		|| !log.contains(marker) || log.contains('VINIX-PPC: FAIL') || log.contains('VINIX-PPC: PANIC') {
		return error('PPC boot did not reach the requested milestone; see ${log_path}')
	}
	if shell { exercise_shell(output, log_path)! }
	for line in log.split_into_lines() {
		if !line.starts_with('VINIX-PPC: FDT ') { continue }
		fields := line.trim_space().split(' ')
		if fields.len != 7 { return error('Invalid FDT report') }
		address := strconv.parse_uint(fields[2], 0, 32)!
		length := strconv.parse_uint(fields[4], 0, 32)!
		nodes := strconv.parse_uint(fields[6], 0, 32)!
		if length < 88 || length > 512 * 1024 || address + length > 512 * 1024 * 1024 {
			return error('Invalid FDT guest address')
		}
		path := output + '/firmware.dtb'
		if os.exists(path) { os.rm(path)! }
		quoted := path.replace('\\', '\\\\').replace('"', '\\"')
		child.stdin_write('pmemsave ${address} ${length} "${quoted}"\n')
		dump_deadline := time.now().add(3 * time.second)
		for time.now() < dump_deadline && (!os.exists(path) || os.file_size(path) != length) {
			time.sleep(10 * time.millisecond)
		}
		data := os.read_bytes(path)!
		if u64(validate_tree(data)!) != nodes { return error('FDT node count mismatch') }
		os.write_file(path + '.sha256', sha256.hexhash(data.bytestr()) + '  firmware.dtb\n')!
		println('Validated copied FDT (${nodes} nodes)')
		return
	}
	return error('Missing FDT report')
}

fn main() {
	root := os.real_path(@VMODROOT + '/../..')
	mut output := os.join_path(os.temp_dir(), 'vinix-powerpc-' + sha256.hexhash(root)[..12])
	args := os.args[1..]
	if args.len == 0 || args[0] !in ['build', 'run', 'test', 'test-media', 'test-kernel', 'test-shell'] {
		eprintln('Usage: v run tools/powerpc {build|run|test|test-media|test-kernel|test-shell} [OUTPUT_DIRECTORY]')
		exit(2)
	}
	if args.len > 2 {
		eprintln('Too many arguments')
		exit(2)
	}
	if args.len == 2 { output = os.abs_path(args[1]) }
	if output.contains('\n') || output.contains('\r') {
		eprintln('Invalid output path')
		exit(2)
	}
	build(root, output) or {
		eprintln(err)
		exit(1)
	}
	println('PowerPC build: ${output}')
	if args[0] != 'build' {
		boot(output, args[0] != 'run', args[0] != 'test', args[0] in ['run', 'test-kernel', 'test-shell'], args[0] in [
			'run',
			'test-shell',
		]) or {
			eprintln(err)
			exit(1)
		}
	}
	seal_results(output) or {
		eprintln(err)
		exit(1)
	}
}
