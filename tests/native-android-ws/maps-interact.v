// SPDX-License-Identifier: GPL-2.0-or-later
// QMP input/capture for the 1024x768 Maps 26.42 guest used by this suite.
// Pixel probes only select when to interact; retain screenshots for review.
module main

import os
import stbi
import time

fn record(run string, message string) ! {
	line := time.utc().str() + ' UTC ' + message + '\n'
	print(line)
	mut file := os.open_append(run + '/interaction.log')!
	defer { file.close() }
	file.write_string(line)!
}

// Drain both pipes in bounded batches: a noisy stream cannot starve the other
// stream or the deadline, and waiting never depends on a pipe reaching EOF.
fn drain(mut process os.Process, mut stdout os.File, mut stderr os.File) !bool {
	mut read := false
	for _ in 0 .. 32 {
		output := process.stdout_read()
		errors := process.stderr_read()
		if output.len == 0 && errors.len == 0 { break }
		if output.len > 0 { stdout.write_string(output)! }
		if errors.len > 0 { stderr.write_string(errors)! }
		read = true
	}
	return read
}

fn command(run string, arguments []string) ! {
	// Darwin's monotonic clock is relative to each process. Separate invocations
	// can therefore report the same value; include their PID and wall time.
	name := 'command-' + os.getpid().str() + '-' + time.utc().unix_nano().str() + '-' + time.sys_mono_now().str()
	out_path := run + '/' + name + '.stdout.log'
	err_path := run + '/' + name + '.stderr.log'
	if os.exists(out_path) || os.is_link(out_path) || os.exists(err_path) || os.is_link(err_path) {
		return error('command output path already exists: ' + name)
	}
	mut stdout := os.create(out_path)!
	defer { stdout.close() }
	mut stderr := os.create(err_path)!
	defer { stderr.close() }
	record(run, 'BEGIN ' + arguments.str() + ' timeout_seconds=30 stdout=' + out_path + ' stderr=' + err_path)!
	mut process := os.new_process(arguments[0])
	process.set_args(arguments[1..])
	process.set_redirect_stdio()
	process.set_stdin_path('/dev/null')
	process.use_pgroup = true
	process.run()
	defer {
		if process.pid > 0 && process.is_alive() {
			process.signal_pgkill()
			process.signal_kill()
			process.wait()
		}
		process.close()
	}
	if process.pid <= 0 { return error('could not start interaction command') }
	deadline := time.sys_mono_now() + u64(30 * time.second)
	mut timed_out := false
	for {
		drain(mut process, mut stdout, mut stderr)!
		if !process.is_alive() { break }
		if time.sys_mono_now() >= deadline {
			timed_out = true
			process.signal_pgkill()
			process.signal_kill()
			break
		}
		time.sleep(10 * time.millisecond)
	}
	process.wait()
	// The direct child has exited. Read already buffered output, without
	// blocking on descendants that might still hold inherited pipe ends.
	mut drain_capped := true
	for _ in 0 .. 32 {
		if !drain(mut process, mut stdout, mut stderr)! {
			drain_capped = false
			break
		}
	}
	record(run, 'END exit=' + process.code.str() + ' timed_out=' + timed_out.str() + ' output_drain_capped=' + drain_capped.str() + ' stdout=' + out_path + ' stderr=' + err_path)!
	if timed_out {
		return error('interaction command timed out after 30 seconds; see ' + out_path + ' and ' + err_path)
	}
	if drain_capped {
		return error('interaction command output drain limit reached; see ' + out_path + ' and ' + err_path)
	}
	if process.code != 0 {
		return error('interaction command exited ' + process.code.str() + '; see ' + out_path + ' and ' + err_path)
	}
}

fn capture(run string, name string) ! {
	if name == '' || name != os.base(name) || name in ['.', '..'] {
		return error('capture name must be a file basename')
	}
	command(run, ['build/android-run', 'screenshot', '--socket', run + '/qmp.sock', '--destination',
		run + '/' + name + '.png'])!
}

fn input(run string, arguments []string) ! {
	command(run, ['build/android-run', 'input', ...arguments, '--socket', run + '/qmp.sock', '--settle',
		'0.15'])!
}

fn presented(path string, screen string) !bool {
	image := stbi.load(path, desired_channels: 4)!
	defer { image.free() }
	if image.width != 1024 || image.height != 768 {
		return error('Maps probe requires a 1024x768 screenshot')
	}
	mut white := 0
	mut black := 0
	mut cyan := 0
	unsafe {
		for y in 150 .. 500 {
			for x in 140 .. 580 {
				i := (y * image.width + x) * 4
				if image.data[i] > 230 && image.data[i + 1] > 230 && image.data[i + 2] > 230 {
					white++
				}
				if y >= 200 && image.data[i] < 180 && image.data[i + 1] > 150 && image.data[i + 2] > 150 {
					cyan++
				}
			}
		}
		for y in 555 .. 597 {
			for x in 300 .. 419 {
				i := (y * image.width + x) * 4
				if image.data[i] < 20 && image.data[i + 1] < 20 && image.data[i + 2] < 20 {
					black++
				}
			}
		}
	}
	return if screen == 'onboarding' { white > 50000 && black > 4500 } else { cyan > 25000 }
}

fn wait_screen(run string, screen string) ! {
	begin := time.now().unix()
	for time.now().unix() - begin < 600 {
		serial := os.read_file(run + '/serial.log') or { '' }
		if serial.contains('APK-SUITE-EXIT id=') {
			return error('Maps exited while waiting for ' + screen)
		}
		if serial.contains('ANDROID-WS-READY backend=vinix-native') && os.exists(run + '/qmp.sock') {
			capture(run, screen + '-probe')!
			if presented(run + '/' + screen + '-probe.png', screen)! {
				os.cp(run + '/' + screen + '-probe.png', run + '/' + screen + '.png')!
				record(run, 'PIXEL-PROBE-PRESENTED ' + screen + '; screenshot requires visual review')!
				return
			}
		}
		time.sleep(3 * time.second)
	}
	return error('timed out waiting for ' + screen)
}

fn main() {
	if os.args.len < 3 {
		eprintln('usage: maps-interact RUN_DIRECTORY onboarding|map|capture NAME|input ARGS...')
		exit(2)
	}
	run := os.abs_path(os.args[1])
	action := os.args[2]
	run_action(run, action, os.args[3..]) or {
		eprintln(err)
		exit(1)
	}
}

fn run_action(run string, action string, args []string) ! {
	match action {
		'onboarding' {
			if args.len != 0 { return error('onboarding takes no extra arguments') }
			wait_screen(run, action)!
			// Click the label centre; 556 falls to its right in this layout.
			input(run, ['click', '524', '134'])!
			record(run, 'SKIP-CLICK')!
		}
		'map' {
			if args.len != 0 { return error('map takes no extra arguments') }
			wait_screen(run, action)!
		}
		'capture' {
			if args.len != 1 { return error('capture requires a name') }
			capture(run, args[0])!
		}
		'input' {
			if args.len == 0 { return error('input requires android-run input arguments') }
			input(run, args)!
		}
		else { return error('unknown action: ' + action) }
	}
}
