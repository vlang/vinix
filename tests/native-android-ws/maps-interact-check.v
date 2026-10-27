// SPDX-License-Identifier: GPL-2.0-or-later
// Exercise the real driver against a controlled V command, without a guest.
// Usage: v run maps-interact-check.v DRIVER FRESH_EXTERNAL_STATE_DIRECTORY
module main

import os
import stbi
import time

#include <signal.h>

fn C.kill(i32, i32) i32

fn screenshot_fixture() ! {
	at := os.args.index('--destination')
	assert at >= 0 && at + 1 < os.args.len
	path := os.args[at + 1]
	mut pixels := []u8{len: 1024 * 768 * 4, init: 255}
	if os.base(os.dir(path)) == 'screen-only-onboarding' {
		// Current client origin (198,95), black sign-in region in local space.
		for y in 570 .. 612 {
			for x in 378 .. 497 {
				i := (y * 1024 + x) * 4
				for channel in 0 .. 3 { pixels[i + channel] = 0 }
			}
		}
	} else {
		for i in 0 .. 1024 * 768 {
			pixels[i * 4] = 100
			pixels[i * 4 + 1] = 200
			pixels[i * 4 + 2] = 200
		}
	}
	stbi.stbi_write_png(path, 1024, 768, 4, pixels.data, 1024 * 4)!
}

fn fixture() ! {
	if os.args.len > 1 && os.args[1] == 'screenshot' {
		screenshot_fixture()!
		return
	}
	assert os.args.len > 2 && os.args[1] == 'input'
	mode := os.args[2]
	at := os.args.index('--socket')
	assert at >= 0 && at + 1 < os.args.len
	run := os.dir(os.args[at + 1])
	os.write_file(run + '/command.pid', os.getpid().str())!
	match mode {
		'click' {
			assert os.args.len > 4
			os.write_file(run + '/click.txt', os.args[3] + ',' + os.args[4])!
		}
		'stamp' {
			assert os.args.len > 3
			println('stdout token=' + os.args[3])
			eprintln('stderr token=' + os.args[3])
		}
		'flood' {
			mut output := os.stdout()
			mut errors := os.stderr()
			output.write_string('O'.repeat(262144) + '\x00\xffDONE-OUT\n')!
			errors.write_string('E'.repeat(262144) + '\x00\xfeDONE-ERR\n')!
		}
		'fail' {
			eprintln('controlled command failure')
			exit(7)
		}
		'hang' {
			println('controlled command waiting forever')
			flush_stdout()
			for { time.sleep(time.second) }
		}
		else { return error('unknown fixture mode') }
	}
}

fn check_screen_only(driver string, state string, screen string) ! {
	run := state + '/screen-only-' + screen
	os.mkdir(run)!
	os.write_file(run + '/serial.log', 'Broker keeps Maps runtime diagnostics private.\n')!
	os.write_file(run + '/qmp.sock', 'fixture endpoint, never connected')!
	arguments := if screen == 'onboarding' {
		[run, screen, '--client-rect', '198', '95', '480', '640', '--screen-only']
	} else { [run, screen, '--screen-only'] }
	mut process := os.new_process(driver)
	process.set_args(arguments)
	process.set_work_folder(state)
	process.set_redirect_stdio_merged()
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
	assert process.pid > 0
	mut output := ''
	deadline := time.sys_mono_now() + u64(10 * time.second)
	for process.is_alive() {
		output += process.stdout_read()
		if time.sys_mono_now() >= deadline { return error('screen-only driver exceeded fixture deadline') }
		time.sleep(10 * time.millisecond)
	}
	process.wait()
	output += process.stdout_read()
	os.write_file(run + '/driver.log', output)!
	assert process.code == 0, output
	timeline := os.read_file(run + '/interaction.log')!
	assert timeline.contains('SCREEN-WAIT mode=screen-only runtime_readiness_required=false')
	assert timeline.contains('PIXEL-PROBE-PRESENTED ' + screen + '; screenshot requires visual review')
	assert os.is_file(run + '/' + screen + '.png')
	if screen == 'onboarding' {
		assert os.read_file(run + '/click.txt')! == '602,149'
		assert timeline.contains('SKIP-CLICK screen=602,149')
	} else { assert !os.exists(run + '/click.txt') }
	println('MAPS-INTERACT-CHECK PASS screen-only ' + screen + ' no UART readiness marker')
}

fn check(driver string, state string, mode string) ! {
	run := state + '/' + mode
	os.mkdir_all(run)!
	mut log := os.create(run + '/driver.log')!
	defer { log.close() }
	mut process := os.new_process(driver)
	process.set_args([run, 'input', mode])
	process.set_work_folder(state)
	process.set_redirect_stdio_merged()
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
	assert process.pid > 0
	start := time.sys_mono_now()
	for process.is_alive() {
		log.write_string(process.stdout_read())!
		if time.sys_mono_now() - start >= u64(40 * time.second) {
			return error('driver exceeded outer test deadline')
		}
		time.sleep(10 * time.millisecond)
	}
	process.wait()
	log.write_string(process.stdout_read())!
	elapsed := time.sys_mono_now() - start
	timeline := os.read_file(run + '/interaction.log')!
	assert timeline.contains('BEGIN ') && timeline.contains('END exit=')
	assert timeline.contains('output_drain_capped=false'), timeline
	outputs := os.ls(run)!.filter(it.ends_with('.stdout.log'))
	errors := os.ls(run)!.filter(it.ends_with('.stderr.log'))
	assert outputs.len == 1 && errors.len == 1
	stdout := os.read_file(run + '/' + outputs[0])!
	stderr := os.read_file(run + '/' + errors[0])!
	if mode == 'flood' {
		assert process.code == 0 && timeline.contains('timed_out=false')
		assert stdout == 'O'.repeat(262144) + '\x00\xffDONE-OUT\n'
		assert stderr == 'E'.repeat(262144) + '\x00\xfeDONE-ERR\n'
	} else {
		assert process.code == 1
		if mode == 'fail' {
			assert timeline.contains('END exit=7 timed_out=false')
			assert stderr.contains('controlled command failure')
		} else {
			assert elapsed >= u64(29 * time.second) && elapsed < u64(35 * time.second)
			assert timeline.contains('timed_out=true')
			assert stdout.contains('controlled command waiting forever')
		}
	}
	pid := os.read_file(run + '/command.pid')!.int()
	assert pid > 0 && C.kill(i32(pid), 0) == -1, 'command survived or was not reaped'
	println('MAPS-INTERACT-CHECK PASS ' + mode + ' elapsed_ms=' + (elapsed / u64(time.millisecond)).str())
}

fn check_separate_invocations(driver string, state string) ! {
	run := state + '/separate-invocations'
	os.mkdir(run)!
	mut streams := map[string]string{}
	for index in 0 .. 32 {
		token := index.str()
		mut process := os.new_process(driver)
		process.set_args([run, 'input', 'stamp', token])
		process.set_work_folder(state)
		process.set_redirect_stdio_merged()
		process.set_stdin_path('/dev/null')
		process.run()
		process.wait()
		output := process.stdout_read()
		code := process.code
		process.close()
		assert code == 0, output
		for path, expected in streams { assert os.read_file(path)! == expected, path + ' overwritten' }
		for path in os.ls(run)! {
			if !path.ends_with('.stdout.log') && !path.ends_with('.stderr.log') { continue }
			full := run + '/' + path
			if full in streams { continue }
			stream := if path.ends_with('.stdout.log') { 'stdout' } else { 'stderr' }
			assert os.read_file(full)! == stream + ' token=' + token + '\n', full
			streams[full] = os.read_file(full)!
		}
		assert streams.len == (index + 1) * 2, 'stream path reused by another driver process'
	}
	timeline := os.read_file(run + '/interaction.log')!
	assert timeline.split_into_lines().filter(it.contains(' BEGIN ')).len == 32
	assert timeline.split_into_lines().filter(it.contains(' END exit=0 ')).len == 32
	println('MAPS-INTERACT-CHECK PASS separate invocations=32 preserved streams=64')
}

fn execute_checks() ! {
	if os.base(os.executable()) == 'android-run' {
		fixture()!
		return
	}
	assert os.args.len == 3 || (os.args.len == 4 && os.args[3] == '--screen-only'),
		'usage: maps-interact-check DRIVER FRESH_EXTERNAL_STATE_DIRECTORY [--screen-only]'
	driver := os.real_path(os.args[1])
	state := os.abs_path(os.args[2])
	assert os.is_file(driver) && !os.exists(state)
	os.mkdir_all(state + '/build')!
	os.cp(os.executable(), state + '/build/android-run')!
	os.chmod(state + '/build/android-run', 0o755)!
	for screen in ['onboarding', 'map'] { check_screen_only(driver, state, screen)! }
	if os.args.len == 4 { return }
	check_separate_invocations(driver, state)!
	for mode in ['flood', 'fail', 'hang'] { check(driver, state, mode)! }
	println('MAPS-INTERACT-CHECK PASS output preservation, exit failure, 30-second timeout and command reap; evidence=' + state)
}

fn main() {
	execute_checks() or { panic(err) }
}
