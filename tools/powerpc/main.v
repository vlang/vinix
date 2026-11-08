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

fn build(root string, output string, runtime_probe bool) ! {
	os.mkdir_all(output)!
	v := tool('VINIX_V_COMPILER', 'v')!
	zig := tool('VINIX_PPC_ZIG', 'zig')!
	headers := zig_headers(zig)!
	preserve_sources(root, output, v, zig)!
	cross_build(root, output, v, zig, headers, 'powerpc-boot', 'loader', 'vinix-of', 'vinix_of_entry')!
	cross_build(root, output, v, zig, headers, 'tests/powerpc/handoff', 'probe', 'handoff-probe', 'vinix_handoff_probe')!
	cross_build(root, output, v, zig, headers, 'kernel/powerpc/start', 'kernel', 'vinix-ppc', 'vinix_ppc_entry')!
	cross_build(root, output, v, zig, headers, 'userland/powerpc/init', 'init', 'init-ppc', 'vinix_user_init')!
	if runtime_probe {
		command([v, '-shared', '-no-builtin', '-no-closures', '-os', 'vinix', '-arch', 'ppc',
			'-target-libc-headers', '-gc', 'none', '-manualfree', '-o', output + '/libc.c', root + '/tests/powerpc/libc'])!
		command([zig, 'cc', '-target', 'powerpc-linux-musleabihf', '-mcpu=7450', '-mno-altivec',
			'-O2', '-fno-pic', '-fno-pie', '-fno-stack-protector', '-static', '-D_GNU_SOURCE',
			'-ffunction-sections', '-fdata-sections', '-Wl,--gc-sections', '-Wl,--build-id=none',
			'-Wl,-T,' + root + '/tests/powerpc/libc/linker.ld', output + '/libc.c', '-lc', '-lm',
			'-o', output + '/libc.elf'])!
		os.setenv('VINIX_PPC_INIT', output + '/libc.elf', true)
	}
	make_ramfs(output)!
	command([zig, 'objcopy', '-O', 'binary', output + '/vinix-of.elf', output + '/vinix-of.bin'])!
	make_iso(output)!
	for name in ['vinix-of.elf', 'vinix-of.bin', 'handoff-probe.elf', 'vinix-ppc-boot.iso'] {
		data := os.read_bytes(output + '/' + name)!
		os.write_file(output + '/' + name + '.sha256', sha256.hexhash(data.bytestr()) + '  ' + name + '\n')!
	}
}

fn cross_build(root string, output string, v string, zig string, headers string, source string, generated string, binary string, entry string) ! {
	mut generate := [v, '-shared', '-no-builtin', '-no-closures', '-enable-globals', '-os', 'vinix', '-arch',
		'ppc', '-target-libc-headers', '-nofloat', '-gc', 'none', '-manualfree', '-o',
		output + '/${generated}.c', '-path', '@vlib|' + root + '/kernel']
	if os.getenv('VINIX_PPC_TRACE') == '1' { generate << ['-d', 'ppc_trace_syscalls'] }
	if os.getenv('VINIX_PPC_TEST_ATA') == '1' { generate << ['-d', 'ppc_test_ata'] }
	generate << root + '/' + source
	command(generate)!
	// Use musl's type declarations, but the V freestanding runtime owns
	// memcpy/memset. V's exported voidptr lacks C's const qualifier.
	command([zig, 'cc', '-target', 'powerpc-linux-musl', '-mcpu=7450-hard_float', '-O2', '-D_STRING_H', '-isystem',
		headers + '/powerpc-linux-musl', '-isystem', headers + '/generic-musl', '-isystem',
		headers + '/powerpc-linux-any', '-isystem', headers + '/any-linux-any', '-ffreestanding',
		'-fno-builtin', '-fno-stack-protector', '-fno-pic', '-fno-pie', '-ffunction-sections',
		'-fdata-sections', '-mno-altivec', '-nostdlib', '-static', '-Wl,--gc-sections',
		'-Wl,--build-id=none', '-Wl,-e,' + entry, '-Wl,-T,' + root + '/' + source + '/linker.ld',
		output + '/${generated}.c', '-o', output + '/${binary}.elf'])!
}

fn boot(output string, test bool, media bool, kernel bool, shell bool, runtime_probe bool) ! {
	qemu := tool('VINIX_PPC_QEMU', 'qemu-system-ppc')!
	graphics := os.getenv('VINIX_PPC_GRAPHICS') == '1'
	hubs := os.getenv('VINIX_PPC_USB_HUB') == '1'
	depth := os.getenv_opt('VINIX_PPC_DEPTH') or { '32' }
	if depth != '15' && depth != '32' { return error('VINIX_PPC_DEPTH must be 15 or 32') }
	memory := strconv.parse_uint(os.getenv_opt('VINIX_PPC_MEMORY') or { '512' }, 10, 32)!
	if memory < 128 || memory > 2048 { return error('VINIX_PPC_MEMORY must be 128..2048 MiB') }
	mut args := ['-M', if hubs { 'mac99,via=pmu,usb=off' } else { 'mac99,via=pmu' }, '-cpu', '7450', '-accel', 'tcg', '-m', memory.str(), '-smp', '1',
		'-nic', 'user,model=sungem,id=net0', '-no-reboot']
	args << ['-g', '800x600x' + depth]
	if disk := os.getenv_opt('VINIX_PPC_DISK') {
		if !os.is_file(disk) { return error('VINIX_PPC_DISK must name an existing image') }
		args << ['-drive', 'file=' + os.real_path(disk).replace(',', ',,') + ',format=raw,if=ide,index=0,cache=writeback']
	}
	if hubs {
		args << ['-device', 'pci-ohci,id=ohci', '-device', 'usb-hub,id=hub,bus=ohci.0,port=1',
			'-device', 'usb-kbd,bus=ohci.0,port=1.1', '-device', 'usb-hub,id=nested,bus=ohci.0,port=1.2,ports=4,port-power=on',
			'-device', 'usb-mouse,bus=ohci.0,port=1.2.1']
	}
	if graphics { args << ['-prom-env', 'output-device=scca'] }
	if shell {
		args << ['-audiodev', if test { 'wav,id=sound,path=' + (output + '/audio.wav').replace(',', ',,') + ',out.frequency=48000,out.channels=2,out.format=s16' } else { (os.getenv_opt('VINIX_PPC_AUDIO') or { 'coreaudio' }) + ',id=sound' },
			'-device', 'usb-audio,id=usb_sound,audiodev=sound,' + if hubs { 'bus=ohci.0,port=1.2.2' } else { 'port=3' }]
	}
	if media {
		args << ['-cdrom', output + '/vinix-ppc-boot.iso', '-boot', 'd', '-prom-env',
			'boot-device=cd:\\BOOT.ELF;1', '-prom-env',
			if shell || runtime_probe {
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
		if !graphics { args << '-nographic' }
		args << ['-serial', 'mon:stdio']
		record_qemu(output, qemu, args)!
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
	marker := if runtime_probe {
		'Vinix: init exited, status 0x00000000'
	} else if shell {
		'vinix$ '
	} else if kernel {
		'VINIX-PPC: PASS userspace MMU syscall and protection'
	} else if media {
		'VINIX-PPC: PASS ELF32 handoff probe'
	} else {
		'VINIX-PPC: PASS firmware discovery'
	}
	os.write_file(log_path, '')!
	if graphics { args << ['-display', 'none'] } else { args << '-nographic' }
	args << ['-monitor', 'stdio']
	if shell {
		args << ['-chardev', 'socket,id=console,path=' + (output + '/serial.sock').replace(',', ',,') +
			',server=on,wait=off,logfile=' + log_path.replace(',', ',,'), '-serial', 'chardev:console']
		args << ['-object', 'filter-dump,id=packets,netdev=net0,file=' + (output + '/network.pcap').replace(',', ',,')]
	} else {
		args << ['-serial', 'file:' + log_path]
	}
	record_qemu(output, qemu, args)!
	mut child := os.new_process(qemu)
	child.set_args(args)
	child.set_redirect_stdio_merged()
	child.run()
	child.stdin_write('info usb\n')
	defer {
		if child.is_alive() { child.signal_kill() }
		child.wait()
		os.write_file(output + '/qemu.log', child.stdout_slurp()) or {}
		child.close()
	}
	mut log := ''
	mut runtime_keyboard_sent := false
	mut runtime_pointer_sent := false
	deadline := time.now().add(60 * time.second)
	for time.now() < deadline && child.is_alive() {
		log = os.read_file(log_path)!
		if runtime_probe && !runtime_keyboard_sent && log.contains('VINIX-PPC: WAIT libc poll keyboard') {
			time.sleep(100 * time.millisecond)
			child.stdin_write('sendkey k 30\n')
			runtime_keyboard_sent = true
		}
		if runtime_probe && !runtime_pointer_sent && log.contains('VINIX-PPC: WAIT libc poll pointer') {
			time.sleep(100 * time.millisecond)
			child.stdin_write('mouse_move 7 -4\n')
			runtime_pointer_sent = true
		}
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
	if runtime_probe && !log.contains('VINIX-PPC: PASS libc argv auxv TLS heap mmap FPU clock') {
		return error('Libc runtime probe did not pass')
	}
	if shell {
		if hubs && (!log.contains('USB hub ready, depth 0x00000001') || !log.contains('USB hub ready, depth 0x00000002')) {
			return error('Both USB hub tiers must enumerate before input and audio tests')
		}
		exercise_usb(mut child, output, log_path, graphics)!
		exercise_shell(mut child, output, log_path)!
		validate_packets(os.read_bytes(output + '/network.pcap')!)!
	}
	if graphics {
		if !log.contains('VINIX-PPC: PASS framebuffer console') { return error('Framebuffer console missing') }
		screenshot(mut child, output + '/screen.ppm')!
		println('PASS framebuffer RGB byte order and rendered console')
	}
	for line in log.split_into_lines() {
		if !line.starts_with('VINIX-PPC: FDT ') { continue }
		fields := line.trim_space().split(' ')
		if fields.len != 7 { return error('Invalid FDT report') }
		address := strconv.parse_uint(fields[2], 0, 32)!
		length := strconv.parse_uint(fields[4], 0, 32)!
		nodes := strconv.parse_uint(fields[6], 0, 32)!
		if length < 88 || length > 512 * 1024 || address + length > memory * 1024 * 1024 {
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
		if shell {
			child.stdin_write('device_del usb_sound\n')
			time.sleep(100 * time.millisecond)
			child.stdin_write('quit\n')
			quit_deadline := time.now().add(3 * time.second)
			for child.is_alive() && time.now() < quit_deadline { time.sleep(10 * time.millisecond) }
			if child.is_alive() { return error('QEMU did not flush audio on shutdown') }
			child.wait()
			validate_audio(os.read_bytes(output + '/audio.wav')!)!
		}
		return
	}
	return error('Missing FDT report')
}

fn main() {
	root := os.real_path(@VMODROOT + '/../..')
	mut output := os.join_path(os.temp_dir(), 'vinix-powerpc-' + sha256.hexhash(root)[..12])
	args := os.args[1..]
	if args.len == 0 || args[0] !in ['build', 'run', 'test', 'test-media', 'test-kernel', 'test-shell', 'test-runtime'] {
		eprintln('Usage: v run tools/powerpc {build|run|test|test-media|test-kernel|test-shell|test-runtime} [OUTPUT_DIRECTORY]')
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
	build(root, output, args[0] == 'test-runtime') or {
		eprintln(err)
		exit(1)
	}
	println('PowerPC build: ${output}')
	if args[0] != 'build' {
		boot(output, args[0] != 'run', args[0] != 'test', args[0] in ['run', 'test-kernel', 'test-shell', 'test-runtime'], args[0] in [
			'run',
			'test-shell',
		], args[0] == 'test-runtime') or {
			eprintln(err)
			exit(1)
		}
	}
	seal_results(output) or {
		eprintln(err)
		exit(1)
	}
}
