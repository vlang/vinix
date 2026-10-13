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
	for i,arg in all_args { if arg=='--session-dialog' && i+2<all_args.len { kind:=all_args[i+1].int(); session_dialog_cli(kind,all_args[i+2],if i+3<all_args.len { all_args[i+3] } else { '' }); return } }
	if '--time-service' in all_args {
		mut server := 'pool.ntp.org'
		for arg in all_args { if arg.starts_with('--time-server=') { server = arg['--time-server='.len..] } }
		run_time_service(server)
		return
	}
	if '--session-services' in all_args {
		mut home := desktop_home
		mut owner:=0
		for arg in all_args { if arg.starts_with('--session-home=') { home = arg['--session-home='.len..] } }
		for arg in all_args { if arg.starts_with('--session-owner=') { owner=arg['--session-owner='.len..].int() } }
		run_session_services(home,owner)
		return
	}
	if '--session-control' in all_args {
		for i, arg in all_args {
			if arg == '--session-control' && i + 1 < all_args.len {
				reply := session_call(all_args[i + 1], all_args[i + 2..]) or { eprintln(err); exit(1) }
				println(reply)
				unsafe { reply.free() }
				return
			}
		}
		eprintln('Usage: vinix-desktop --session-control COMMAND ARGUMENTS...')
		return
	}
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
	mut fb := open_desktop_outputs(options.framebuffer) or {
		eprintln('vinix-desktop: ${err}')
		exit(1)
	}
	gpu_present_startup_stage(c'framebuffer mapped')
	defer {
		fb.close()
	}

	gpu_present_startup_stage(c'loading preferences')
	mut preferences := desktop_load_preferences(desktop_home)
	set_desktop_language(preferences.settings.language)
	gpu_present_startup_stage(c'preferences loaded')
	scale := preferences.configure_scale(fb.width, fb.height)
	desktop_physical_width=fb.virtual_width(); desktop_physical_height=fb.virtual_height()
	gpu_present_startup_stage(c'display scale configured')
	gpu_present_startup_stage(c'allocating canvas')
	canvas := new_scaled_canvas(desktop_scaled_extent(fb.virtual_width(), scale),
		desktop_scaled_extent(fb.virtual_height(), scale), fb.virtual_width(), fb.virtual_height(), scale)
	gpu_present_startup_stage(c'canvas allocated')
	gpu_present_startup_stage(c'loading fonts')
	fonts := load_fonts_for_scale(scale)
	gpu_present_startup_stage(c'fonts loaded')
	mut desktop := Desktop{
		settings:          preferences.settings
		canvas:            canvas
		fonts:             fonts
		shortcut_order:    load_shortcut_order(desktop_home)
		pinned_apps:       load_taskbar_pins(desktop_home)
		start_pins:        load_start_pins(desktop_home)
		recent_programs:   load_recent_programs(desktop_home)
		tz_offset_seconds: options.tz_offset
		trace_selectors:   options.trace_selectors
	}
	gpu_present_startup_stage(c'desktop state allocated')
	desktop.configure_display_outputs(&fb)

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
	// The Desktop and Files show the user's /home/<user>/Desktop, Documents,
	// Downloads and so on from here on.
	desktop_use_user_home(desktop_prepare_user_home(desktop_home, desktop_users_directory))
	_ = session_start(desktop.home)
	gpu_present_startup_stage(c'user home ready')
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
	if options.open.len == 0 && desktop.restore_shell_session() {
		if launch_install_terminal { desktop.launch_titled_at_startup('Terminal') }
		desktop_publish_session_ready()
	} else if options.open.len == 0 {
		gpu_present_startup_stage(c'creating initial System window')
		desktop.spawn('System', .system, 580, 60, 372, 232)
		gpu_present_startup_stage(c'initial System window created')
		// Files is a separate process. Paint the compositor-owned windows first,
		// so a delayed application handshake cannot leave the firmware console
		// looking like the desktop failed to start.
		launch_default_files = true
		// Startup settings retain Files and the development Terminal as defaults.
	} else {
		for title in options.open {
			if !desktop.session.loaded { desktop.load_shell_session() }
			desktop.launch_titled_at_startup(title)
		}
		if launch_install_terminal {
			desktop.launch_titled_at_startup('Terminal')
		}
		desktop_publish_session_ready()
	}

	desktop.session.saving = true
	mut framebuffer_server := start_framebuffer_server(keyboard.key_events) or {
		eprintln('vinix-desktop: framebuffer window service: ${err}')
		unsafe { err.free() }
		FramebufferServer{}
	}
	defer { framebuffer_server.close() }
	// Whether the kernel can sleep, and the lid action and performance profile
	// that were saved: the kernel keeps those two only while it runs.
	gpu_present_startup_stage(c'taking up power settings')
	desktop.start_power_session()
	gpu_present_startup_stage(c'power settings taken up')

	mut stats := FrameStats{}
	// Registration and the app picker drew into the same canvas; the desktop
	// starts from a complete frame of its own, pointer backing included.
	desktop.dirty = true
	desktop.cursor_backing.box = DamageRect{}
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
		// Sleep, from the menu or the idle timer, happens between two passes:
		// the frame that took the menu down has been presented, and nothing
		// is half done. The session goes on from here when the machine wakes.
		if desktop.idle.sleep_requested {
			titlebar_click = TitlebarClick{}
			// The kernel darkens the screen for a sleep where the screen is
			// the boot framebuffer, and not a panel with a driver of its own,
			// such as Apple's through DCP, whose backlight it also leaves lit.
			// So the display is turned off here first, as it is for the idle
			// timeout: on that panel it is all that goes dark, and on a boot
			// framebuffer the kernel saves and brings back a black picture.
			desktop.display_turn_off()
			if desktop.idle.blank_pending {
				desktop.idle.blank_pending = false
				present_black_frame(mut fb, mut desktop.canvas)
			}
			if desktop.sleep_now() {
				desktop.drop_wake_input(mut pointer, mut keyboard)
			}
			continue
		}
		frame_started := monotonic_millis()
		stats_started := if options.stats { desktop_monotonic_us() } else { i64(0) }

		desktop.update_taskbar_clock()
		desktop.poll_framebuffer_server(mut framebuffer_server)
		desktop.poll_apps()
		desktop.poll_shell_services()
		if frame_started-desktop.session.last_output_check>=2000 {
			desktop.session.last_output_check=frame_started
			if fb.output_geometry_changed() {
				fb.close()
				fb=open_desktop_outputs(options.framebuffer) or { Framebuffer{} }
				if fb.fd>=0 { desktop.recover_display_outputs(&fb) }
			}
		}
		desktop.save_shell_session(false)
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
		desktop.poll_host_paste()
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
			fb = open_desktop_outputs(options.framebuffer) or {
				eprintln('vinix-desktop: cannot reclaim the framebuffer: ${err}')
				exit(1)
			}
			pointer = open_pointer(options.pointer)
			keyboard = open_keyboard()
			desktop.pointer_present = pointer.available()
			desktop.external_finished(result)
			desktop.recover_display_outputs(&fb)
			continue
		}
		// Settings only requests a new scale. Apply it after all input from this
		// frame and before layout so drawing and hit targets share one space.
		previous_scale := desktop_current_scale()
		desktop.apply_requested_scale()
		if previous_scale!=desktop_current_scale() { desktop.capture_shell_session(); desktop.configure_display_outputs(&fb); desktop.apply_session_placements() }
		if !preferences.save_changes(desktop.settings, previous_scale, desktop_home) {
			eprintln('vinix-desktop: could not save desktop settings; changes may reset on restart')
		}
		desktop.update_switcher()
		// Hover delays, device status and reported progress are all sampled
		// against the clock, so an idle pass costs only these comparisons.
		desktop.update_taskbar_hover()
		desktop.update_tray()
		desktop.poll_version_check()
		desktop.poll_taskbar_status()
		desktop.tick_taskbar_marquee()
		// After this pass's input: how long nobody has touched the machine, and
		// whether that turns the display off or asks for sleep.
		desktop.idle_tick()
		other_dirty := desktop.dirty
		// While the display is off nothing is composed or presented. Whatever
		// changes in the meantime is repainted, whole, when it comes back on.
		if desktop.idle.display_off {
			if desktop.idle.blank_pending {
				desktop.idle.blank_pending = false
				present_black_frame(mut fb, mut desktop.canvas)
			}
			desktop.dirty = false
			desktop.frame_damage = FrameDamage{}
			desktop.drag_damage = DamageRect{}
			elapsed := monotonic_millis() - frame_started
			desktop.wait_framebuffer_input(&framebuffer_server, pointer.fd, keyboard.fd, desktop_frame_wait_ms(elapsed,
				desktop.idle_wait(options.idle_interval)))
			continue
		}
		// A pointer that moved, where everything else the move changed has been
		// recorded as damage. See on_pointer_move.
		pointer_only := desktop.pointer_moved_only && desktop.drag.kind == .none_
		desktop.dirty = background_dirty || pointer_dirty || keyboard_dirty || capture_dirty
			|| other_dirty
		// Changes that know their area: the clock ticking, one application
		// redrawing. See frame_damage.v.
		mut damage := desktop.frame_damage
		desktop.frame_damage = FrameDamage{}
		if (pointer_only || damage.valid()) && !desktop.cursor_backing.box.valid {
			// Where the pointer was last drawn is not known, so it cannot be
			// taken off the picture by itself.
			desktop.dirty = true
		}
		if damage.valid() && desktop.taskbar_preview.open {
			// Open previews are live pictures of every window, and are only
			// captured from complete frames.
			desktop.dirty = true
		}
		if desktop.frames == 0 {
			gpu_present_startup_stage(c'first input and application poll complete')
		}
		after_input := if options.stats { desktop_monotonic_us() } else { i64(0) }

		if !desktop.dirty && pointer_only && !damage.valid() {
			old_cursor, new_cursor := desktop.move_cursor()
			after_cursor := if options.stats { desktop_monotonic_us() } else { i64(0) }
			fb.present_damages(&desktop.canvas, old_cursor, new_cursor)
			desktop.capture_presented(&desktop.canvas)
			obs_capture_presented(&desktop.canvas)
			after_present := if options.stats { desktop_monotonic_us() } else { i64(0) }
			sleep_to_next_frame(frame_started, options.frame_interval)
			if options.stats {
				now := desktop_monotonic_us()
				stats.add(after_input - stats_started, 0, after_cursor - after_input,
					after_present - after_cursor, now - after_present)
				stats.report_every(200, now)
			}
			continue
		}

		// Nothing has changed: the framebuffer already holds the right
		// picture, so the frame is skipped entirely rather than recomposed into
		// the same pixels. The wait is interruptible by either input descriptor;
		// its timeout only drives application housekeeping.
		if !desktop.dirty && !damage.valid() {
			elapsed := monotonic_millis() - frame_started
			app_interval := desktop.idle_wait_interval(options.idle_interval, options.frame_interval)
			capture_interval := desktop.capture_idle_interval(app_interval, options.frame_interval)
			hover_interval := desktop.taskbar_hover_idle_interval(capture_interval)
			status_interval := desktop.taskbar_status_idle_interval(hover_interval)
			clock_interval := desktop.taskbar_clock_idle_interval(status_interval)
			interval := desktop.idle_wait(clock_interval)
			wait := desktop_frame_wait_ms(elapsed, interval)
			desktop.wait_framebuffer_input(&framebuffer_server, pointer.fd, keyboard.fd, wait)
			continue
		}

		// A drag's pointer-only damage is kept apart from independent changes
		// (keyboard input, a window opening, etc.), which need the whole frame.
		partial_drag_frame := desktop.drag.kind == .move && desktop.drag_damage.valid
			&& pointer_dirty && !background_dirty && !keyboard_dirty && !capture_dirty && !other_dirty
		full_frame := desktop.dirty && !partial_drag_frame
		desktop.dirty = false
		if !full_frame {
			if partial_drag_frame {
				damage.add(desktop.drag_damage)
			}
			desktop.damage_frame_counters(mut damage)
			if desktop.theme().glass {
				// Glass keeps what is behind it in cells. See glass.v.
				damage.align_to_glass()
			}
		}
		desktop.paint_full = full_frame

		if desktop.frames == 0 {
			gpu_present_startup_stage(c'building first element tree')
		}
		desktop.frames++
		tree := desktop.build_tree()
		if desktop.frames == 1 {
			gpu_present_startup_stage(c'first element tree built')
		}
		after_build := if options.stats { desktop_monotonic_us() } else { i64(0) }

		if full_frame {
			desktop.render_desktop_frame(tree, desktop.canvas_damage())
		} else {
			desktop.render_partial_frame(tree, mut damage, true)
		}
		desktop.paint_full = true
		if desktop.frames == 1 {
			gpu_present_startup_stage(c'first canvas render complete')
		}
		after_render := if options.stats { desktop_monotonic_us() } else { i64(0) }

		if desktop.frames == 1 {
			gpu_present_startup_stage(c'presenting first canvas')
		}
		if full_frame {
			fb.present(&desktop.canvas, desktop_current_scale())
		} else {
			fb.present_frame_damage(&desktop.canvas, damage)
		}
		if desktop.frames == 1 {
			gpu_present_startup_stage(c'first canvas presented')
		}
		desktop.capture_presented(&desktop.canvas)
		obs_capture_presented(&desktop.canvas)
		after_present := if options.stats { desktop_monotonic_us() } else { i64(0) }
		desktop.drag_damage = DamageRect{}

		free_tree(tree)

		if launch_default_files {
			launch_default_files = false
			desktop.launch_configured_startup(launch_install_terminal)
			desktop_publish_session_ready()
		}

		sleep_to_next_frame(frame_started, options.frame_interval)

		if options.stats {
			now := desktop_monotonic_us()
			stats.add(after_input - stats_started, after_build - after_input, after_render - after_build,
				after_present - after_render, now - after_present)
			stats.report_every(200, now)
		}
	}

	// Leave the console the way it was found rather than on top of a desktop
	// that is no longer being redrawn.
	desktop.save_shell_session(true)
	desktop.close_apps()
	desktop.clipboard.close_request()
	desktop.capture_close()
	if desktop.power != .reload_desktop { session_shutdown() }
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
	present_black_frame(mut fb, mut desktop.canvas)
	println('vinix-desktop: ${desktop.frames} frames')

	// Nothing above has to be undone afterwards: this does not return unless
	// the kernel refuses, and it is keep_running for a session that was only
	// closed rather than asked to take the machine with it.
	desktop_power_apply(desktop.power)
}

// One black frame: what a display that is off shows, and what the console is
// handed back over. Whoever goes on drawing repaints the canvas whole.
fn present_black_frame(mut fb Framebuffer, mut canvas Canvas) {
	canvas.clip = Clip{
		x: 0
		y: 0
		w: canvas.width
		h: canvas.height
	}
	canvas.clear(0x000000)
	fb.present(canvas, desktop_current_scale())
}

// pump_pointer maps the device's own coordinate space onto the screen and
// turns the button mask into press and release events.
fn (mut d Desktop) pump_pointer(mut pointer PointerDevice, width int, height int, titlebar_click TitlebarClick) TitlebarClick {
	d.pointer_moved_only = false
	packet := pointer.poll() or { return titlebar_click }

	// The node exists even on a machine with no pointer hardware, and says so
	// by reporting an empty coordinate range. Without a device there is nothing
	// to draw a cursor for.
	if packet.max_x <= 0 || packet.max_y <= 0 {
		d.pointer_present = false
		return TitlebarClick{}
	}
	d.pointer_present = true
	// A packet that only turns the display back on is not also a move or a
	// click on whatever is under the pointer.
	if d.idle_pointer_input(packet) {
		return TitlebarClick{}
	}

	pointer_x := int(i64(packet.x) * i64(width - 1) / i64(packet.max_x))
	pointer_y := int(i64(packet.y) * i64(height - 1) / i64(packet.max_y))
	// The level goes in before the move is handled, so a drag can see that the
	// button is no longer held.
	d.buttons = packet.buttons
	if d.session_gesture(packet,pointer_x,pointer_y) { d.pointer_x=pointer_x; d.pointer_y=pointer_y; d.dirty=true; return TitlebarClick{} }
	d.on_pointer_move(pointer_x, pointer_y)
	if packet.pressed != 0 || packet.released != 0 || packet.scroll != 0 || packet.scroll_x != 0 {
		// A click or a scroll recomposes everything, including the pointer
		// the move above would otherwise have redrawn by itself.
		d.pointer_moved_only = false
		d.dirty = true
	}

	mut click := titlebar_click
	// A different pointer gesture breaks a pending double-click sequence.
	if packet.pressed & (button_middle | button_right | button_back) != 0 || packet.scroll != 0 || packet.scroll_x != 0 {
		click = TitlebarClick{}
	}
	if packet.pressed & button_left != 0 {
		if !d.window_overlay_active() && d.create_context_left_down(pointer_x, pointer_y) {
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
		if d.window_actions_right_down(pointer_x, pointer_y) {
			click = TitlebarClick{}
		} else if d.snap_assist.active {
			d.close_window_snap_assist()
			d.window_layout_right_release = true
			click = TitlebarClick{}
		} else if d.window_layout_right_down(pointer_x, pointer_y) {
			click = TitlebarClick{}
		} else if d.open_create_context_menu(pointer_x, pointer_y) {
			click = TitlebarClick{}
		} else {
			d.on_app_pointer_button(pointer_x, pointer_y, .down, .right)
		}
	}
	if packet.released & button_right != 0 {
		if d.window_layout_right_release {
			d.window_layout_right_release = false
		} else if !take_create_context_right_release() {
			d.on_app_pointer_button(pointer_x, pointer_y, .up, .right)
		}
	}
	if packet.pressed & button_back != 0 {
		d.on_app_pointer_button(pointer_x, pointer_y, .down, .back)
	}
	if packet.released & button_back != 0 {
		d.on_app_pointer_button(pointer_x, pointer_y, .up, .back)
	}
	if packet.scroll != 0 {
		d.on_app_pointer_scroll(pointer_x, pointer_y, int(packet.scroll))
	}
	if packet.scroll_x != 0 {
		d.on_app_pointer_horizontal_scroll(pointer_x, pointer_y, int(packet.scroll_x))
	}
	if packet.pressed!=0 { d.mark_session_gesture() }
	return click
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

// Times are in microseconds. report_every writes one line per batch. Printing to the console is itself
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
	eprintln('frames=${s.count} in ${span / 1000}ms; avg us input=${s.input / n} build=${s.build / n} render=${s.render / n} present=${s.present / n} sleep=${s.sleep / n}')
	s = FrameStats{
		started: now
	}
}
