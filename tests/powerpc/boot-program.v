// SPDX-License-Identifier: GPL-2.0-or-later
// Capture a bounded native application boot; success requires a caller marker.
module main

import crypto.sha256
import os
import time

fn main() {
	if os.args.len != 3 {
		eprintln('Usage: v run tests/powerpc/boot-program.v IMAGE_DIRECTORY EXPECTED_LOG_MARKER')
		exit(2)
	}
	boot(os.real_path(os.args[1]), os.args[2]) or {
		eprintln(err)
		exit(1)
	}
}

fn capture_screen(mut child os.Process, capture string, name string) ! {
	path := capture + '/' + name + '.ppm'
	child.stdin_write('screendump "' + path.replace('\\', '\\\\').replace('"', '\\"') + '"\n')
	time.sleep(500 * time.millisecond)
	if !os.is_file(path) { return error('QEMU did not capture ' + path) }
}

fn boot(output string, marker string) ! {
	if marker == '' { return error('An expected application marker is required') }
	capture := os.getenv_opt('VINIX_PPC_CAPTURE_DIR') or { output }
	os.mkdir_all(capture)!
	qemu := os.find_abs_path_of_executable(os.getenv_opt('VINIX_PPC_QEMU') or { 'qemu-system-ppc' })!
	logfile := capture + '/program.log'
	args := ['-M', 'mac99,via=pmu', '-cpu', '7450', '-accel', 'tcg', '-m', '512', '-smp', '1',
		'-nic', 'user,model=sungem', '-g', '800x600x32', '-display', 'none', '-no-reboot', '-cdrom',
		output + '/vinix-ppc-boot.iso', '-boot', 'd', '-prom-env', 'boot-device=cd:\\BOOT.ELF;1',
		'-prom-env', 'boot-file=cd:\\KERNEL.ELF;1 cd:\\RAMFS.TAR;1', '-prom-env', 'output-device=scca',
		'-serial', 'file:' + logfile, '-monitor', 'stdio']
	os.write_file(capture + '/program-qemu.txt', args.join('\n') + '\n')!
	os.write_file(logfile, '')!
	mut child := os.new_process(qemu)
	child.set_args(args)
	child.set_redirect_stdio_merged()
	child.run()
	defer {
		if child.is_alive() { child.signal_kill() }
		child.wait()
		os.write_file(capture + '/program-monitor.log', child.stdout_slurp()) or {}
		child.close()
	}
	deadline := time.now().add(60 * time.second)
	mut log := ''
	for child.is_alive() && time.now() < deadline {
		log = os.read_file(logfile)!
		if log.contains(marker) || log.contains('VINIX-PPC: PANIC') || log.contains('init exited') {
			break
		}
		time.sleep(20 * time.millisecond)
	}
	// Startup markers precede the first rendered frame. Let the application
	// finish that frame before asking QEMU to copy the scanout.
	time.sleep(5 * time.second)
	log = os.read_file(logfile)!
	// Preserve even failed screens; a captured screen alone is not a pass.
	child.stdin_write('info registers\n')
	capture_screen(mut child, capture, 'program')!
	if log.contains(marker) && os.getenv('VINIX_PPC_TEST_SETUP') == '1' {
		// The real 800x600 first-run form starts with the name focused. Type
		// through USB, then click the password field and type there. Never
		// submit credentials or bypass registration in this capture test.
		for key in ['v', 'i', 'n', 'i', 'x'] {
			child.stdin_write('sendkey ' + key + ' 30\n')
			time.sleep(150 * time.millisecond)
		}
		time.sleep(2 * time.second)
		capture_screen(mut child, capture, 'program-typed')!
		child.stdin_write('mouse_move 0 6\n')
		time.sleep(150 * time.millisecond)
		child.stdin_write('mouse_button 1\n')
		time.sleep(150 * time.millisecond)
		child.stdin_write('mouse_button 0\n')
		for key in ['x', 'y', 'z'] {
			child.stdin_write('sendkey ' + key + ' 30\n')
			time.sleep(150 * time.millisecond)
		}
		time.sleep(2 * time.second)
		capture_screen(mut child, capture, 'program-clicked')!
		time.sleep(2 * time.second)
		child.stdin_write('info registers\n')
		capture_screen(mut child, capture, 'program-settled')!
		if os.getenv('VINIX_PPC_TEST_STABILITY') == '1' {
			for i in 0 .. 20 {
				capture_screen(mut child, capture, 'stability-${i:02}')!
			}
		}
	}
	log = os.read_file(logfile)!
	print(log)
	os.cp(@FILE, capture + '/boot-program.v')!
	mut sums := ''
	for name in ['program.log', 'program.ppm', 'program-typed.ppm', 'program-clicked.ppm',
		'program-settled.ppm', 'boot-program.v', 'program-qemu.txt', 'init-ppc.elf', 'vinix-ppc.elf',
		'vinix-ppc-boot.iso'] {
		path := if name.starts_with('program') || name == 'boot-program.v' {
			capture + '/' + name
		} else {
			output + '/' + name
		}
		if os.is_file(path) {
			sums += sha256.hexhash(os.read_bytes(path)!.bytestr()) + '  ' + path + '\n'
		}
	}
	for name in os.ls(capture)! {
		if name.starts_with('stability-') && name.ends_with('.ppm') {
			path := capture + '/' + name
			sums += sha256.hexhash(os.read_bytes(path)!.bytestr()) + '  ' + path + '\n'
		}
	}
	os.write_file(capture + '/PROGRAM-SHA256SUMS', sums)!
	if !log.contains(marker) || log.contains('VINIX-PPC: PANIC') || log.contains('init exited') {
		return error('Application did not reach ' + marker)
	}
}
