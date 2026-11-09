// SPDX-License-Identifier: GPL-2.0-or-later
// Capture a bounded native application boot; success requires a caller marker.
module main

import crypto.sha256
import os
import json2
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
	monitor(mut child, 'screendump "' + path.replace('\\', '\\\\').replace('"', '\\"') + '"\n')
	time.sleep(500 * time.millisecond)
	if !os.is_file(path) { return error('QEMU did not capture ' + path) }
}

fn click_at(mut child os.Process, position string) {
	monitor(mut child, 'mouse_move -2000 -2000')
	time.sleep(200 * time.millisecond)
	monitor(mut child, 'mouse_move ' + position)
	time.sleep(200 * time.millisecond)
	monitor(mut child, 'mouse_button 1')
	time.sleep(180 * time.millisecond)
	monitor(mut child, 'mouse_button 0')
}

fn boot(output string, marker string) ! {
	if marker == '' { return error('An expected application marker is required') }
	capture := os.getenv_opt('VINIX_PPC_CAPTURE_DIR') or { output }
	os.mkdir_all(capture)!
	qemu := os.find_abs_path_of_executable(os.getenv_opt('VINIX_PPC_QEMU') or { 'qemu-system-ppc' })!
	logfile := capture + '/program.log'
	mut args := ['-M', 'mac99,via=pmu', '-cpu', '7450', '-accel', 'tcg', '-m', '512', '-smp', '1',
		'-nic', 'user,model=sungem', '-g', '800x600x32', '-display', 'none', '-no-reboot', '-cdrom',
		output + '/vinix-ppc-boot.iso', '-boot', 'd', '-prom-env', 'boot-device=cd:\\BOOT.ELF;1',
		'-prom-env', 'boot-file=cd:\\KERNEL.ELF;1 cd:\\RAMFS.TAR;1', '-prom-env', 'output-device=scca',
		'-serial', 'file:' + logfile, '-monitor', 'none', '-qmp', 'stdio']
	if disk := os.getenv_opt('VINIX_PPC_DISK') {
		if !os.is_file(disk) { return error('VINIX_PPC_DISK must exist') }
		args << ['-drive', 'file=' + os.real_path(disk).replace(',', ',,') + ',format=raw,if=ide,index=0,cache=writeback']
	}
	os.write_file(capture + '/program-qemu.txt', args.join('\n') + '\n')!
	os.write_file(logfile, '')!
	mut child := os.new_process(qemu)
	child.set_args(args)
	child.set_redirect_stdio_merged()
	child.run()
	child.stdin_write('{"execute":"qmp_capabilities"}\n')
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
	monitor(mut child, 'info registers\n')
	capture_screen(mut child, capture, 'program')!
	if log.contains(marker) && os.getenv('VINIX_PPC_TEST_ACCOUNT') == '1' {
		// Disposable fixture credentials, entered through the real USB keyboard.
		// Tab changes fields; Return submits the real registration form.
		for key in ['v', 'i', 'n', 'i', 'x', 'tab', 't', 'e', 's', 't', '1', '2', '3',
			'tab', 't', 'e', 's', 't', '1', '2', '3', 'ret'] {
			monitor(mut child, 'sendkey ' + key + ' 30\n')
			time.sleep(150 * time.millisecond)
		}
		for _ in 0 .. 60 {
			time.sleep(time.second)
			if os.read_file(logfile)!.contains('first canvas presented') { break }
		}
		time.sleep(2 * time.second)
		capture_screen(mut child, capture, 'program-registered')!
	}
	if log.contains(marker) && os.getenv('VINIX_PPC_TEST_SETUP') == '1' {
		// The real 800x600 first-run form starts with the name focused. Type
		// through USB, then click the password field and type there. Never
		// submit credentials or bypass registration in this capture test.
		for key in ['v', 'i', 'n', 'i', 'x'] {
			monitor(mut child, 'sendkey ' + key + ' 30\n')
			time.sleep(150 * time.millisecond)
		}
		time.sleep(2 * time.second)
		capture_screen(mut child, capture, 'program-typed')!
		monitor(mut child, 'mouse_move 0 6\n')
		time.sleep(150 * time.millisecond)
		monitor(mut child, 'mouse_button 1\n')
		time.sleep(150 * time.millisecond)
		monitor(mut child, 'mouse_button 0\n')
		for key in ['x', 'y', 'z'] {
			monitor(mut child, 'sendkey ' + key + ' 30\n')
			time.sleep(150 * time.millisecond)
		}
		time.sleep(2 * time.second)
		capture_screen(mut child, capture, 'program-clicked')!
		time.sleep(2 * time.second)
		monitor(mut child, 'info registers\n')
		capture_screen(mut child, capture, 'program-settled')!
		if os.getenv('VINIX_PPC_TEST_STABILITY') == '1' {
			for i in 0 .. 20 {
				capture_screen(mut child, capture, 'stability-${i:02}')!
			}
		}
	}
	if log.contains(marker) && os.getenv('VINIX_PPC_TEST_DISPLAY_STABILITY') == '1' {
		// Use the persisted GUI fixture with its initial System window. Cross
		// many two-second output-discovery polls, including a held mouse drag.
		for i in 0 .. 20 { capture_screen(mut child, capture, 'display-idle-${i:02}')! }
		// Fresh accounts restore Files on login now that it can launch. Close
		// that known fixture window so the existing checker sees only System.
		if os.read_file(logfile)!.contains('vinix-desktop: opened Files') {
			click_at(mut child, '784 98')
			time.sleep(2 * time.second)
		}
		monitor(mut child, 'mouse_move -2000 -2000')
		time.sleep(300 * time.millisecond)
		monitor(mut child, 'mouse_move 480 70')
		time.sleep(300 * time.millisecond)
		capture_screen(mut child, capture, 'display-before-drag')!
		monitor(mut child, 'mouse_button 1')
		time.sleep(300 * time.millisecond)
		for i in 0 .. 6 {
			monitor(mut child, 'mouse_move -20 8')
			capture_screen(mut child, capture, 'display-drag-${i:02}')!
		}
		// A spurious output reset cancels the held drag; the final movement
		// then moves only the pointer. Check the final window position too.
		for i in 0 .. 6 { capture_screen(mut child, capture, 'display-held-${i:02}')! }
		monitor(mut child, 'mouse_move -100 30')
		time.sleep(300 * time.millisecond)
		monitor(mut child, 'mouse_button 0')
		capture_screen(mut child, capture, 'display-after-drag')!
		monitor(mut child, 'mouse_move -2000 -2000')
		time.sleep(300 * time.millisecond)
		monitor(mut child, 'mouse_move 20 584')
		time.sleep(300 * time.millisecond)
		for action in ['open', 'close'] {
			monitor(mut child, 'mouse_button 1')
			time.sleep(150 * time.millisecond)
			monitor(mut child, 'mouse_button 0')
			time.sleep(time.second)
			capture_screen(mut child, capture, 'display-menu-' + action)!
		}
		for i in 0 .. 20 { capture_screen(mut child, capture, 'display-settled-${i:02}')! }
	}
	if log.contains(marker) && os.getenv('VINIX_PPC_TEST_APPS') == '1' {
		for app in ['files', 'settings', 'editor', 'calculator', 'terminal'] {
			position := match app {
				'files' { '60 43' }
				'settings' { '60 370' }
				'editor' { '150 43' }
				'calculator' { '60 207' }
				else { '60 289' }
			}
			click_at(mut child, position)
			title := match app { 'files' { 'Files' } 'settings' { 'Settings' } 'editor' { 'Text Editor' } 'calculator' { 'Calculator' } else { 'Terminal' } }
			limit := time.now().add(90 * time.second)
			for child.is_alive() && time.now() < limit {
				if os.read_file(logfile)!.contains('vinix-desktop: opened ' + title) { break }
				time.sleep(100 * time.millisecond)
			}
			time.sleep(2 * time.second)
			capture_screen(mut child, capture, 'apps-' + app)!
			if !os.read_file(logfile)!.contains('vinix-desktop: opened ' + title) { return error('Shortcut did not open ' + title) }
			keys := match app {
				'editor' { ['p', 'p', 'c', 'spc', 'e', 'd', 'i', 't', 'o', 'r'] }
				'calculator' { ['2', 'shift-equal', '2', 'ret'] }
				'terminal' { ['u', 'n', 'a', 'm', 'e', 'ret'] }
				else { []string{} }
			}
			for key in keys { monitor(mut child, 'sendkey ' + key); time.sleep(200 * time.millisecond) }
			if keys.len > 0 {
				time.sleep(2 * time.second)
				capture_screen(mut child, capture, 'apps-' + app + '-typed')!
			}
			close_position := match app { 'files' { '784 98' } 'settings' { '776 124' } 'calculator' { '548 59' } else { '784 202' } }
			// Editor has unsaved text; leave it open for now instead of answering
			// its save prompt. Later app placement still follows monotonically increasing IDs.
			if app != 'editor' { click_at(mut child, close_position) }
			time.sleep(time.second)
		}
		// Reuse slots more times than the kernel's process table can hold.
		// The calculator is clamped vertically to y=48 at this resolution.
		for cycle in 0 .. 8 {
			opened := 'vinix-desktop: opened Calculator'
			before := os.read_file(logfile)!.count(opened)
			click_at(mut child, '60 207')
			limit := time.now().add(90 * time.second)
			for child.is_alive() && time.now() < limit {
				if os.read_file(logfile)!.count(opened) > before { break }
				time.sleep(100 * time.millisecond)
			}
			if os.read_file(logfile)!.count(opened) != before + 1 { return error('Calculator slot reuse failed') }
			time.sleep(time.second)
			capture_screen(mut child, capture, 'apps-reopen-${cycle}')!
			click_at(mut child, '${444 + (cycle % 6) * 26} 59')
			time.sleep(time.second)
			capture_screen(mut child, capture, 'apps-closed-${cycle}')!
		}
	}
	log = os.read_file(logfile)!
	print(log)
	os.cp(@FILE, capture + '/boot-program.v')!
	mut sums := ''
	for name in ['program.log', 'program.ppm', 'program-typed.ppm', 'program-clicked.ppm',
		'program-settled.ppm', 'program-registered.ppm', 'boot-program.v', 'program-qemu.txt', 'init-ppc.elf', 'vinix-ppc.elf',
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
		if (name.starts_with('stability-') || name.starts_with('display-') || name.starts_with('apps-')) && name.ends_with('.ppm') {
			path := capture + '/' + name
			sums += sha256.hexhash(os.read_bytes(path)!.bytestr()) + '  ' + path + '\n'
		}
	}
	os.write_file(capture + '/PROGRAM-SHA256SUMS', sums)!
	if os.getenv('VINIX_PPC_TEST_ACCOUNT') == '1' && !log.contains('user profile ready') {
		return error('Real GUI registration did not save the account')
	}
	if !log.contains(marker) || log.contains('VINIX-PPC: PANIC') || log.contains('init exited') {
		return error('Application did not reach ' + marker)
	}
}

struct MonitorCommand {
 execute string = "human-monitor-command"
 arguments map[string]string
}

fn monitor(mut child os.Process, command string) {
 child.stdin_write(json2.encode(MonitorCommand{arguments: {"command-line": command.trim_space()}}) + "\n")
}
