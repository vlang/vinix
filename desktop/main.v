// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// vinix-desktop — a small desktop environment for Vinix.
//
// It maps /dev/fb0, reads the pointer from /dev/pointer and the keyboard from
// its controlling terminal, and composes every frame itself. The screen is
// described as a ui2 element tree that is rebuilt each frame; render.v paints
// that tree and collects the hit targets the window manager routes clicks
// through.
module main

// What the loop asks to wait after a frame changed. Vinix wakes a sleeping
// thread on the scheduler's timeslice, so the shortest sleep that actually
// happens is around twice this and never less than about 12 ms. This cadence
// tracks a dragged window closely.
const default_frame_interval_ms = i64(16)

// This is the longest the quiet path waits before checking clocks and hosted
// applications. Pointer and keyboard readiness end the wait immediately, so
// input does not inherit this latency. A terminal keystroke also makes its next
// refresh immediate; only genuinely background output waits for the cadence.
const default_idle_interval_ms = i64(1000)

// The desktop's own shortcuts, as a raw terminal delivers them. The keyboard
// is read in raw mode, so a control chord arrives as one byte and nothing else
// can be mistaken for it.
const key_ctrl_k = u8(0x0b)
const key_ctrl_n = u8(0x0e)
const key_ctrl_p = u8(0x10)
const key_ctrl_q = u8(0x11)
// F1 and F2, as the Apple SPI keyboard encodes them. They are the brightness
// keys printed on the machine's own keycaps, so they drive the panel here.
const key_f1 = '\x1bOP'
const key_f2 = '\x1bOQ'

// One step of the bar in Settings, so the two agree.
const brightness_step = 5

// The reload helper removes this before asking PID 1 to replace the session.
// Recreate it only after the replacement has painted its first frame and
// completed the startup application handshakes, so an out-of-group watchdog
// can distinguish a responsive desktop from a process that merely exec'd.
const desktop_session_ready_path = '/run/vinix-desktop-ready'

struct Options {
	framebuffer     string = '/dev/fb0'
	pointer         string = '/dev/pointer'
	tz_offset       i64
	frame_interval  i64 = default_frame_interval_ms
	idle_interval   i64 = default_idle_interval_ms
	stats           bool
	trace_selectors bool
	// Applications to open at startup, by the title on their shortcut. The
	// desktop is otherwise only reachable through the pointer, which leaves a
	// scripted boot no way to ask for the one thing worth measuring: how long
	// a real application takes to appear in a window.
	open []string
}

fn parse_options(args []string) Options {
	gpu_present_startup_stage(c'initializing command-line defaults')
	mut options := Options{}
	gpu_present_startup_stage(c'command-line defaults initialized')
	for arg in args {
		gpu_present_startup_stage(c'parsing command-line option')
		if arg.starts_with('--fb=') {
			options = Options{
				...options
				framebuffer: arg[5..]
			}
		} else if arg.starts_with('--pointer=') {
			options = Options{
				...options
				pointer: arg[10..]
			}
		} else if arg.starts_with('--frame-ms=') {
			// 0 runs the loop flat out, which is how the cost of a frame is
			// measured separately from the cost of waiting between frames. An
			// explicit value also disables the distinct idle cadence.
			interval := arg[11..].i64()
			options = Options{
				...options
				frame_interval: interval
				idle_interval:  interval
			}
		} else if arg.starts_with('--open=') {
			mut titles := options.open.clone()
			titles << arg[7..]
			options = Options{
				...options
				open: titles
			}
		} else if arg == '--stats' {
			options = Options{
				...options
				stats: true
			}
		} else if arg == '--trace-selectors' {
			options = Options{
				...options
				trace_selectors: true
			}
		} else if arg.starts_with('--tz=') {
			// Hours east of UTC. Vinix has no time zone database, so the
			// offset the clock should show has to be told to it.
			options = Options{
				...options
				tz_offset: i64(arg[5..].f64() * 3600)
			}
		}
	}
	gpu_present_startup_stage(c'command-line option scan complete')
	return options
}

fn sleep_ms(ms i64) {
	desktop_sleep_ms(ms)
}

fn desktop_publish_session_ready() {
	message := 'ready\n'
	if !desktop_write_file(desktop_session_ready_path, message.str, u64(message.len)) {
		eprintln('vinix-desktop: could not publish the session-ready marker')
		return
	}
	if desktop_is_system_session() {
		eprintln('vinix-desktop: ready')
	}
}

fn main() {
	gpu_present_startup_stage(c'entered main')
	gpu_present_startup_stage(c'collecting process arguments')
	all_args := arguments()
	gpu_present_startup_stage(c'process arguments collected')
	// Both parsers only recognise option prefixes, so argv[0] is harmless.
	// Passing the captured array directly also avoids V's array-slice path,
	// which is not returning on the native M1 boot.
	gpu_present_startup_stage(c'using captured arguments without slicing')
	gpu_present_startup_stage(c'checking application subprocess mode')
	if app_options := app_process_options(all_args) {
		gpu_present_startup_stage(c'dispatching application subprocess')
		run_app_process(app_options)
		return
	}
	gpu_present_startup_stage(c'application subprocess mode not requested')
	gpu_present_startup_stage(c'desktop process selected')
	desktop_ignore_broken_pipe()
	gpu_present_startup_stage(c'SIGPIPE ignored')
	desktop_install_power_signals()
	gpu_present_startup_stage(c'power signal handlers installed')
	gpu_present_startup_stage(c'entering command-line parser')
	options := parse_options(all_args)
	gpu_present_startup_stage(c'command line parsed')

	gpu_present_startup_stage(c'opening framebuffer')
	mut fb := open_framebuffer(options.framebuffer) or {
		eprintln('vinix-desktop: ${err}')
		exit(1)
	}
	gpu_present_startup_stage(c'framebuffer mapped')
	defer {
		fb.close()
	}

	gpu_present_startup_stage(c'loading preferences')
	mut preferences := desktop_load_preferences(desktop_home)
	gpu_present_startup_stage(c'preferences loaded')
	scale := preferences.configure_scale(fb.width, fb.height)
	gpu_present_startup_stage(c'display scale configured')
	gpu_present_startup_stage(c'allocating canvas')
	canvas := new_scaled_canvas(desktop_scaled_extent(fb.width, scale),
		desktop_scaled_extent(fb.height, scale), fb.width, fb.height, scale)
	gpu_present_startup_stage(c'canvas allocated')
	gpu_present_startup_stage(c'loading fonts')
	fonts := load_fonts()
	gpu_present_startup_stage(c'fonts loaded')
	mut desktop := Desktop{
		settings:          preferences.settings
		canvas:            canvas
		fonts:             fonts
		shortcut_order:    load_shortcut_order(desktop_home)
		tz_offset_seconds: options.tz_offset
		trace_selectors:   options.trace_selectors
	}
	gpu_present_startup_stage(c'desktop state allocated')
	gpu_present_startup_stage(c'loading application icons')
	desktop.load_app_icons()
	gpu_present_startup_stage(c'application icons loaded')

	gpu_present_startup_stage(c'opening pointer device')
	mut pointer := open_pointer(options.pointer)
	defer {
		pointer.close()
	}
	desktop.pointer_present = pointer.available()
	desktop.pointer_x = desktop.canvas.width / 2
	desktop.pointer_y = desktop.canvas.height / 2
	mut titlebar_click := TitlebarClick{}
	gpu_present_startup_stage(c'pointer device ready')

	gpu_present_startup_stage(c'opening keyboard device')
	mut keyboard := open_keyboard()
	defer {
		keyboard.close()
	}
	gpu_present_startup_stage(c'keyboard device ready')

	// First launch is an exclusive setup mode: ordinary windows, shortcuts and
	// the taskbar do not exist until a persistent user profile has been created.
	gpu_present_startup_stage(c'checking user profile')
	desktop.ensure_registered_user(mut fb, mut pointer, mut keyboard, options.frame_interval,
		options.idle_interval)
	gpu_present_startup_stage(c'user profile ready')
	if !desktop.running {
		return
	}
	// A newly created user then chooses which optional apps to install. The
	// install itself runs in a Terminal once the ordinary desktop is up.
	gpu_present_startup_stage(c'checking first-run app choice')
	launch_install_terminal := desktop.choose_first_run_apps(mut fb, mut pointer, mut keyboard,
		options.frame_interval, options.idle_interval)
	gpu_present_startup_stage(c'first-run app choice ready')
	if !desktop.running {
		return
	}

	// An opening arrangement, kept clear of the shortcut column down the left
	// edge. The calculator remains available from its shortcut and the Start
	// menu; the Welcome page is available from Help but is not shown at launch.
	mut launch_default_files := false
	mut launch_development_terminal := false
	if options.open.len == 0 {
		gpu_present_startup_stage(c'creating initial System window')
		desktop.spawn('System', .system, 580, 60, 372, 232)
		gpu_present_startup_stage(c'initial System window created')
		// Files is a separate process. Paint the compositor-owned windows first,
		// so a delayed application handshake cannot leave the firmware console
		// looking like the desktop failed to start.
		launch_default_files = true
		// The install Terminal ends in an ordinary interactive shell, so it
		// also serves as the development session's Terminal.
		launch_development_terminal = desktop_is_development_session()
			|| launch_install_terminal
	} else {
		for title in options.open {
			desktop.launch_titled_at_startup(title)
		}
		if launch_install_terminal {
			desktop.launch_titled_at_startup('Terminal')
		}
		desktop_publish_session_ready()
	}

	mut stats := FrameStats{}
	for desktop.running {
		if desktop.frames == 0 {
			gpu_present_startup_stage(c'first compositor iteration')
		}
		// `reboot`, `poweroff` and `halt` signal PID 1 rather than powering the
		// machine down themselves. The supervising init forwards those signals
		// to this system-session compositor for an orderly teardown.
		desktop.take_power_signal()
		if !desktop.running {
			break
		}
		frame_started := monotonic_millis()

		desktop.update_taskbar_clock()
		desktop.poll_apps()
		// Keep a drag's pointer-only damage separate from independent changes
		// (a clock tick, an app frame, keyboard input, etc.). A partial compose
		// is valid only when the pointer is the sole source of new pixels.
		background_dirty := desktop.dirty
		desktop.dirty = false
		titlebar_click = desktop.pump_pointer(mut pointer, desktop.canvas.width,
			desktop.canvas.height, titlebar_click)
		pointer_dirty := desktop.dirty
		desktop.dirty = false
		desktop.pump_keyboard(mut keyboard)
		keyboard_dirty := desktop.dirty
		desktop.dirty = false
		desktop.capture_tick()
		capture_dirty := desktop.dirty
		desktop.dirty = false
		// Xorg, unlike a native ui2 application, needs the physical display and
		// input devices. Stop the compositor at a frame boundary, restore the
		// console, and reopen everything after the external application exits.
		if desktop.pending_external != '' {
			titlebar_click = TitlebarClick{}
			desktop.capture_close()
			command := desktop.pending_external
			desktop.pending_external = ''
			keyboard.close()
			pointer.close()
			fb.close()
			result := desktop_run_external(command)
			fb = open_framebuffer(options.framebuffer) or {
				eprintln('vinix-desktop: cannot reclaim the framebuffer: ${err}')
				exit(1)
			}
			pointer = open_pointer(options.pointer)
			keyboard = open_keyboard()
			desktop.pointer_present = pointer.available()
			desktop.external_finished(result)
			continue
		}
		// Settings only requests a new scale. Apply it after all input from this
		// frame and before layout so drawing and hit targets share one space.
		previous_scale := desktop_current_scale()
		desktop.apply_requested_scale()
		if !preferences.save_changes(desktop.settings, previous_scale, desktop_home) {
			eprintln('vinix-desktop: could not save desktop settings; changes may reset on restart')
		}
		desktop.update_switcher()
		other_dirty := desktop.dirty
		desktop.dirty = background_dirty || pointer_dirty || keyboard_dirty || capture_dirty
			|| other_dirty
		if desktop.frames == 0 {
			gpu_present_startup_stage(c'first input and application poll complete')
		}
		after_input := monotonic_millis()

		// Nothing has changed: the framebuffer already holds the right
		// picture, so the frame is skipped entirely rather than recomposed into
		// the same pixels. The wait is interruptible by either input descriptor;
		// its timeout only drives application housekeeping.
		if !desktop.dirty {
			elapsed := monotonic_millis() - frame_started
			app_interval := desktop.idle_wait_interval(options.idle_interval, options.frame_interval)
			interval := desktop.capture_idle_interval(app_interval, options.frame_interval)
			wait := desktop_frame_wait_ms(elapsed, interval)
			desktop_wait_for_input(pointer.fd, keyboard.fd, wait)
			continue
		}
		desktop.dirty = false

		if desktop.frames == 0 {
			gpu_present_startup_stage(c'building first element tree')
		}
		desktop.frames++
		tree := desktop.build_tree()
		if desktop.frames == 1 {
			gpu_present_startup_stage(c'first element tree built')
		}
		after_build := monotonic_millis()

		partial_drag_frame := desktop.drag.kind == .move && desktop.drag_damage.valid
			&& pointer_dirty && !background_dirty && !keyboard_dirty && !capture_dirty && !other_dirty
		if partial_drag_frame {
			desktop.render_drag_damage(tree, desktop.drag_damage)
		} else {
			desktop.render(tree)
		}
		if desktop.frames == 1 {
			gpu_present_startup_stage(c'first canvas render complete')
		}
		desktop.render_create_context_menu()
		after_render := monotonic_millis()

		if desktop.frames == 1 {
			gpu_present_startup_stage(c'presenting first canvas')
		}
		if partial_drag_frame {
			fb.present_damage(&desktop.canvas, desktop.drag_damage)
		} else {
			fb.present(&desktop.canvas, desktop_current_scale())
		}
		if desktop.frames == 1 {
			gpu_present_startup_stage(c'first canvas presented')
		}
		desktop.capture_presented(&desktop.canvas)
		after_present := monotonic_millis()
		desktop.drag_damage = DamageRect{}

		free_tree(tree)

		if launch_default_files {
			launch_default_files = false
			desktop.launch_titled_at_startup('Files')
			if launch_development_terminal {
				launch_development_terminal = false
				desktop.launch_titled_at_startup('Terminal')
			}
			desktop_publish_session_ready()
		}

		sleep_to_next_frame(frame_started, options.frame_interval)

		if options.stats {
			stats.add(after_input - frame_started, after_build - after_input, after_render - after_build, after_present - after_render, monotonic_millis() - after_present)
			stats.report_every(200, monotonic_millis())
		}
	}

	// Leave the console the way it was found rather than on top of a desktop
	// that is no longer being redrawn.
	desktop.close_apps()
	desktop.capture_close()
	if desktop.power == .reload_desktop {
		// Close every inherited device before exec, but keep this process alive:
		// graphics-mode ownership is PID based, so the last complete frame stays
		// visible until the replacement compositor presents its first one.
		keyboard.close()
		pointer.close()
		fb.close()
		println('vinix-desktop: ${desktop.frames} frames; executing replacement')
		desktop_exec_replacement()
		// execve only returns on failure. Let PID 1's ordinary crash recovery
		// start the installed binary instead of drawing through closed devices.
		return
	}
	// Power actions hand the display back to the system console.
	desktop.canvas.clip = Clip{
		x: 0
		y: 0
		w: desktop.canvas.width
		h: desktop.canvas.height
	}
	desktop.canvas.clear(0x000000)
	fb.present(&desktop.canvas, desktop_current_scale())
	println('vinix-desktop: ${desktop.frames} frames')

	// Nothing above has to be undone afterwards: this does not return unless
	// the kernel refuses, and it is keep_running for a session that was only
	// closed rather than asked to take the machine with it.
	desktop_power_apply(desktop.power)
}

// pump_pointer maps the device's own coordinate space onto the screen and
// turns the button mask into press and release events.
fn (mut d Desktop) pump_pointer(mut pointer PointerDevice, width int, height int, titlebar_click TitlebarClick) TitlebarClick {
	packet := pointer.poll() or { return titlebar_click }

	// The node exists even on a machine with no pointer hardware, and says so
	// by reporting an empty coordinate range. Without a device there is nothing
	// to draw a cursor for.
	if packet.max_x <= 0 || packet.max_y <= 0 {
		d.pointer_present = false
		return TitlebarClick{}
	}
	d.pointer_present = true

	pointer_x := int(i64(packet.x) * i64(width - 1) / i64(packet.max_x))
	pointer_y := int(i64(packet.y) * i64(height - 1) / i64(packet.max_y))
	// The level goes in before the move is handled, so a drag can see that the
	// button is no longer held.
	d.buttons = packet.buttons
	d.on_pointer_move(pointer_x, pointer_y)

	mut click := titlebar_click
	// A different pointer gesture breaks a pending double-click sequence.
	if packet.pressed & (button_middle | button_right) != 0 || packet.scroll != 0 {
		click = TitlebarClick{}
	}
	if packet.pressed & button_left != 0 {
		if d.create_context_left_down(pointer_x, pointer_y) {
			click = TitlebarClick{}
		} else {
			click = d.titlebar_pointer_down_at(click, pointer_x, pointer_y, desktop_monotonic_ms())
		}
	}
	if packet.released & button_left != 0 {
		if !take_create_context_left_release() {
			d.on_pointer_up(pointer_x, pointer_y)
		}
	}
	if packet.pressed & button_middle != 0 {
		d.on_app_pointer_button(pointer_x, pointer_y, .down, .middle)
	}
	if packet.released & button_middle != 0 {
		d.on_app_pointer_button(pointer_x, pointer_y, .up, .middle)
	}
	if packet.pressed & button_right != 0 {
		if d.open_create_context_menu(pointer_x, pointer_y) {
			click = TitlebarClick{}
		} else {
			d.on_app_pointer_button(pointer_x, pointer_y, .down, .right)
		}
	}
	if packet.released & button_right != 0 {
		if !take_create_context_right_release() {
			d.on_app_pointer_button(pointer_x, pointer_y, .up, .right)
		}
	}
	if packet.scroll != 0 {
		d.on_app_pointer_scroll(pointer_x, pointer_y, int(packet.scroll))
	}
	return click
}

fn (mut d Desktop) pump_keyboard(mut keyboard Keyboard) {
	keys := keyboard.poll()

	// Cmd-Tab is the window manager's whoever is typing, so it comes out of
	// the stream first. An empty read goes through as well: a sequence the
	// last read ended inside has to be let go when nothing completes it.
	switched := d.take_switcher_keys(keys)
	if switched.len == 0 {
		return
	}

	// Brightness is the machine's, not the focused window's: F1 and F2 dim and
	// brighten the panel whatever is on top, and are taken out of the stream so
	// a terminal does not also receive them as an escape sequence.
	mut rest := d.take_brightness_keys(switched)
	if rest.len == 0 {
		return
	}

	// Window-management chords are taken before a focused app gets text. Cmd-W
	// must close a terminal or editor window rather than inserting an escape
	// sequence into it.
	rest = d.take_window_shortcuts(rest)
	if rest.len == 0 {
		return
	}

	// An open Start menu owns typing before the focused application does:
	// printable keys search, Backspace edits, Return launches and Escape closes.
	if d.start_menu_open {
		d.start_menu_key_input(rest)
		return
	}

	// An application that takes typed input gets it while it is focused, and
	// the desktop's own shortcuts stand down: a terminal cannot have `q` close
	// the desktop out from under whoever is typing.
	if d.focused_app_takes_keys() {
		d.send_keys_to_focused(rest)
		return
	}

	// Control chords rather than bare letters. These fire whenever no
	// application has the keyboard, which on a machine with no working pointer
	// is most of the time -- and a plain `q` meaning "close the desktop" then
	// means typing a word with a q in it drops the user back to the console.
	// Esc is out for the same reason: it is a key people press.
	for i := 0; i < rest.len; i++ {
		match rest[i] {
			key_ctrl_p {
				d.toggle_start_menu()
			}
			key_ctrl_q {
				d.running = false
			}
			key_ctrl_n {
				d.spawn_scattered()
			}
			key_ctrl_k {
				// The first native application, for a keyboard-only session.
				if available_apps.len > 0 {
					d.launch(available_apps[0])
				}
			}
			else {}
		}
	}
}

// take_brightness_keys acts on every F1/F2 in the input and returns what is
// left. The common case is a string containing neither, which is returned as
// it came rather than rebuilt -- there is no garbage collector here, and this
// runs on every frame that has input.
fn (mut d Desktop) take_brightness_keys(keys string) string {
	if keys.index_u8(0x1b) < 0 {
		return keys
	}
	mut kept := []u8{cap: keys.len}
	mut i := 0
	for i < keys.len {
		if i + key_f1.len <= keys.len {
			three := keys[i..i + key_f1.len]
			if three == key_f1 {
				adjust_brightness(-brightness_step)
				i += key_f1.len
				continue
			}
			if three == key_f2 {
				adjust_brightness(brightness_step)
				i += key_f2.len
				continue
			}
		}
		kept << keys[i]
		i++
	}
	if kept.len == keys.len {
		unsafe { kept.free() }
		return keys
	}
	return kept.bytestr()
}

// adjust_brightness moves the panel by one step, reading first so that a
// change made in Settings, or by the other key, is where it starts from.
fn adjust_brightness(delta int) {
	mut state := BacklightState{}
	if read_backlight(mut state) != .ok || !state.online || !state.writable {
		return
	}
	current := backlight_percent(&state)
	if current < 0 {
		return
	}
	mut target := current + delta
	if target < 0 {
		target = 0
	}
	if target > 100 {
		target = 100
	}
	if target != current {
		set_backlight_percent(target)
	}
}

// FrameStats accumulates where a frame's milliseconds went. It is only kept
// when --stats is given, and it reports to the serial console rather than to
// the screen it is measuring.
struct FrameStats {
mut:
	started i64
	count   int
	input   i64
	build   i64
	render  i64
	present i64
	sleep   i64
}

fn (mut s FrameStats) add(input i64, build i64, render i64, present i64, sleep i64) {
	s.count++
	s.input += input
	s.build += build
	s.render += render
	s.present += present
	s.sleep += sleep
}

// report_every writes one line per batch. Printing to the console is itself
// expensive here — it goes through the kernel's terminal, which draws into the
// very framebuffer being measured — so the batch is large and the line carries
// the wall clock the batch took, which is the only honest way to read a rate
// off it.
fn (mut s FrameStats) report_every(frames int, now i64) {
	if s.started == 0 {
		s.started = now
	}
	if s.count < frames {
		return
	}
	n := i64(s.count)
	span := now - s.started
	eprintln('frames=${s.count} in ${span}ms; avg ms input=${s.input / n} build=${s.build / n} render=${s.render / n} present=${s.present / n} sleep=${s.sleep / n}')
	s = FrameStats{
		started: now
	}
}
