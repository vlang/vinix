// SPDX-License-Identifier: GPL-2.0-or-later
// QMP input/capture for the 1024x768 Maps 26.42 guest used by this suite.
// Pixel probes only select when to interact; retain screenshots for review.
module main

import os
import stbi
import strconv
import time

struct ClientRect {
	x      int
	y      int
	width  int
	height int
}

struct PixelPoint {
	x int
	y int
}

// Legacy probes used a 480x640 client at (120,80). Keep its local coordinates
// while requiring the caller to measure the current onboarding client area.
const legacy_client = ClientRect{120, 80, 480, 640}

struct WaitOptions {
	client      ClientRect
	screen_only bool
}

fn wait_options(action string, args []string) !WaitOptions {
	mut remaining := []string{}
	mut screen_only := false
	for argument in args {
		if argument == '--screen-only' {
			if screen_only { return error('duplicate --screen-only option') }
			screen_only = true
		} else {
			remaining << argument
		}
	}
	if action == 'onboarding' {
		return WaitOptions{client_rect(remaining)!, screen_only}
	}
	if action != 'map' || remaining.len != 0 {
		return error('map accepts only the optional --screen-only flag')
	}
	return WaitOptions{legacy_client, screen_only}
}

fn can_probe(serial string, qmp_exists bool, screen_only bool) !bool {
	if serial.contains('APK-SUITE-EXIT id=') {
		return error('Maps exited while waiting for a screen')
	}
	return qmp_exists && (screen_only || serial.contains('ANDROID-WS-READY backend=vinix-native'))
}

fn client_rect(args []string) !ClientRect {
	if args.len != 5 || args[0] != '--client-rect' {
		return error('onboarding requires --client-rect X Y WIDTH HEIGHT from the current screenshot')
	}
	mut values := []int{cap: 4}
	for value in args[1..] {
		if value == '' || value.bytes().any(it < `0` || it > `9`) {
			return error('client rectangle values must be unsigned decimal integers')
		}
		values << int(strconv.parse_uint(value, 10, 31)!)
	}
	rect := ClientRect{values[0], values[1], values[2], values[3]}
	// Subtraction avoids overflow before rejecting rectangles outside the frame.
	if rect.x >= 1024 || rect.y >= 768 || rect.width <= 0 || rect.height <= 0
		|| rect.width > 1024 - rect.x || rect.height > 768 - rect.y {
		return error('client rectangle must fit wholly inside the 1024x768 screenshot')
	}
	return rect
}

fn (rect ClientRect) point(local_x int, local_y int) PixelPoint {
	return PixelPoint{rect.x + local_x * rect.width / 480,
		rect.y + local_y * rect.height / 640}
}

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

fn probe_image(image &stbi.Image, screen string, rect ClientRect) !bool {
	if image.width != 1024 || image.height != 768 {
		return error('Maps probe requires a 1024x768 screenshot')
	}
	mut white := 0
	mut black := 0
	mut cyan := 0
	unsafe {
		// Sample in canonical client coordinates so thresholds retain the same
		// meaning when the compositor stretches or shrinks the native surface.
		for y in 70 .. 420 {
			for x in 20 .. 460 {
				point := rect.point(x, y)
				i := (point.y * image.width + point.x) * 4
				if image.data[i] > 230 && image.data[i + 1] > 230 && image.data[i + 2] > 230 {
					white++
				}
				if y >= 120 && image.data[i] < 180 && image.data[i + 1] > 150 && image.data[i + 2] > 150 {
					cyan++
				}
			}
		}
		for y in 475 .. 517 {
			for x in 180 .. 299 {
				point := rect.point(x, y)
				i := (point.y * image.width + point.x) * 4
				if image.data[i] < 20 && image.data[i + 1] < 20 && image.data[i + 2] < 20 {
					black++
				}
			}
		}
	}
	return if screen == 'onboarding' { white > 50000 && black > 4500 } else { cyan > 25000 }
}

fn presented(path string, screen string, rect ClientRect) !bool {
	image := stbi.load(path, desired_channels: 4)!
	defer { image.free() }
	return probe_image(&image, screen, rect)
}

fn wait_screen(run string, screen string, options WaitOptions) ! {
	mode := if options.screen_only { 'screen-only runtime_readiness_required=false' } else { 'uart-and-screen runtime_readiness_required=true' }
	record(run, 'SCREEN-WAIT mode=' + mode + '; pixel matches require visual review')!
	begin := time.now().unix()
	for time.now().unix() - begin < 600 {
		serial := os.read_file(run + '/serial.log') or { '' }
		if can_probe(serial, os.exists(run + '/qmp.sock'), options.screen_only)! {
			capture(run, screen + '-probe')!
			if presented(run + '/' + screen + '-probe.png', screen, options.client)! {
				os.cp(run + '/' + screen + '-probe.png', run + '/' + screen + '.png')!
				record(run, 'PIXEL-PROBE-PRESENTED ' + screen + '; screenshot requires visual review')!
				return
			}
		}
		time.sleep(3 * time.second)
	}
	return error('timed out waiting for ' + screen)
}

fn self_test() ! {
	for action in ['onboarding', 'map'] {
		geometry := if action == 'onboarding' { ['--client-rect', '171', '94', '480', '640'] } else { []string{} }
		if wait_options(action, geometry)!.screen_only { return error('default screen wait bypassed UART') }
		for arguments in [[...geometry, '--screen-only'], ['--screen-only', ...geometry]] {
			if !wait_options(action, arguments)!.screen_only { return error('screen-only opt-in was lost') }
		}
		if _ := wait_options(action, [...geometry, '--screen-only', '--screen-only']) {
			return error('duplicate screen-only option accepted')
		}
	}
	if _ := wait_options('map', ['--private-log', '/private/maps.log']) {
		return error('unsupported private log argument accepted')
	}
	for qmp_exists in [false, true] {
		for screen_only in [false, true] {
			if can_probe('', qmp_exists, screen_only)! != (qmp_exists && screen_only)
				|| can_probe('ANDROID-WS-READY backend=vinix-native', qmp_exists, screen_only)! != qmp_exists {
				return error('screen wait ignored readiness mode or missing QMP')
			}
			if _ := can_probe('APK-SUITE-EXIT id=google-maps', qmp_exists, screen_only) {
				return error('screen wait ignored an observed app exit')
			}
		}
	}
	for arguments in [ []string{}, ['--client-rect', '0', '0', '480'],
		['--origin', '0', '0', '480', '640'], ['--client-rect', '-1', '0', '480', '640'],
		['--client-rect', '+1', '0', '480', '640'], ['--client-rect', '1_0', '0', '480', '640'],
		['--client-rect', '', '0', '480', '640'], ['--client-rect', '0 ', '0', '480', '640'],
		['--client-rect', '2147483648', '0', '1', '1'],
		['--client-rect', '1024', '0', '1', '1'], ['--client-rect', '0', '768', '1', '1'],
		['--client-rect', '0', '0', '0', '640'], ['--client-rect', '0', '0', '480', '0'],
		['--client-rect', '1000', '0', '25', '640'], ['--client-rect', '0', '700', '480', '69'],
		['--client-rect', '0', '0', '480', '640', 'extra']] {
		if _ := client_rect(arguments) { return error('invalid client rectangle accepted: ' + arguments.str()) }
	}
	if client_rect(['--client-rect', '120', '80', '480', '640'])! != legacy_client
		|| legacy_client.point(404, 54) != PixelPoint{524, 134} {
		return error('legacy client geometry changed')
	}
	if client_rect(['--client-rect', '171', '94', '480', '640'])!.point(404, 54) != PixelPoint{575, 148}
		|| client_rect(['--client-rect', '20', '30', '240', '320'])!.point(404, 54) != PixelPoint{222, 57}
		|| client_rect(['--client-rect', '50', '40', '960', '640'])!.point(404, 54) != PixelPoint{858, 94}
		|| client_rect(['--client-rect', '1023', '767', '1', '1'])!.point(479, 639) != PixelPoint{1023, 767} {
		return error('translated or scaled client point is wrong')
	}
	for rect in [legacy_client, ClientRect{171, 94, 480, 640}, ClientRect{20, 30, 240, 320},
		ClientRect{50, 40, 960, 640}] {
		mut pixels := []u8{len: 1024 * 768 * 4}
		image := stbi.Image{width: 1024, height: 768, nr_channels: 4, data: unsafe { &u8(pixels.data) }}
		if probe_image(&image, 'onboarding', rect)! { return error('blank image passed onboarding probe') }
		for y in rect.y .. rect.y + rect.height {
			for x in rect.x .. rect.x + rect.width {
				i := (y * 1024 + x) * 4
				for channel in 0 .. 3 { pixels[i + channel] = 255 }
			}
		}
		if probe_image(&image, 'onboarding', rect)! { return error('white image without sign-in passed probe') }
		for y in 475 .. 517 {
			for x in 180 .. 299 {
				point := rect.point(x, y)
				i := (point.y * 1024 + point.x) * 4
				for channel in 0 .. 3 { pixels[i + channel] = 0 }
			}
		}
		if !probe_image(&image, 'onboarding', rect)! { return error('translated/scaled onboarding probe was lost') }
		if rect == ClientRect{171, 94, 480, 640} && probe_image(&image, 'onboarding', legacy_client)! {
			return error('stale coordinates matched translated onboarding')
		}
	}
	println('MAPS-INTERACT-SELFTEST-PASS explicit-client-rectangle strict-bounds scaled-click translated-pixel-probes stale-coordinate-rejection explicit-screen-only-readiness QMP-required app-exit-rejection')
}

fn main() {
	if os.args.len == 2 && os.args[1] == '--self-test' {
		self_test() or { eprintln(err); exit(1) }
		return
	}
	if os.args.len < 3 {
		eprintln('usage: maps-interact --self-test | RUN_DIRECTORY onboarding --client-rect X Y WIDTH HEIGHT [--screen-only] | map [--screen-only] | capture NAME | input ARGS...')
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
			options := wait_options(action, args)!
			rect := options.client
			point := rect.point(404, 54)
			record(run, 'ONBOARDING-CLIENT x=${rect.x} y=${rect.y} width=${rect.width} height=${rect.height} skip_local=404,54 skip_screen=${point.x},${point.y}')!
			wait_screen(run, action, options)!
			input(run, ['click', point.x.str(), point.y.str()])!
			record(run, 'SKIP-CLICK screen=${point.x},${point.y}')!
		}
		'map' {
			wait_screen(run, action, wait_options(action, args)!)!
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
