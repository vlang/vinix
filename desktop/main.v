// vinix-desktop — a small desktop environment for Vinix.
//
// It maps /dev/fb0, reads the pointer from /dev/pointer and the keyboard from
// its controlling terminal, and composes every frame itself. The screen is
// described as a ui2 element tree that is rebuilt each frame; render.v paints
// that tree and collects the hit targets the window manager routes clicks
// through.
module main

// What the loop asks to wait between frames. Vinix wakes a sleeping thread on
// the scheduler's timeslice, so the shortest sleep that actually happens is
// around twice this and never less than about 12 ms; 10 settles at roughly 35
// frames a second, which tracks a dragged window closely while leaving most of
// the CPU to everything else. Splitting the wait into shorter sleeps makes it
// worse, not better: each one pays that floor again.
const default_frame_interval_ms = i64(16)

struct Options {
	framebuffer    string = '/dev/fb0'
	pointer        string = '/dev/pointer'
	tz_offset      i64
	frame_interval i64 = default_frame_interval_ms
	stats          bool
}

fn parse_options(args []string) Options {
	mut options := Options{}
	for arg in args {
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
			// measured separately from the cost of waiting between frames.
			options = Options{
				...options
				frame_interval: arg[11..].i64()
			}
		} else if arg == '--stats' {
			options = Options{
				...options
				stats: true
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
	return options
}

fn sleep_ms(ms i64) {
	desktop_sleep_ms(ms)
}

fn sleep_to_next_frame(frame_started i64, interval i64) {
	elapsed := monotonic_millis() - frame_started
	if elapsed < interval {
		sleep_ms(interval - elapsed)
	}
}

fn main() {
	options := parse_options(arguments()[1..])

	mut fb := open_framebuffer(options.framebuffer) or {
		eprintln('vinix-desktop: ${err}')
		exit(1)
	}
	defer {
		fb.close()
	}

	mut desktop := Desktop{
		canvas: new_canvas(fb.width, fb.height)
		fonts: load_fonts()
		tz_offset_seconds: options.tz_offset
	}

	mut pointer := open_pointer(options.pointer)
	defer {
		pointer.close()
	}
	desktop.pointer_present = pointer.available()
	desktop.pointer_x = fb.width / 2
	desktop.pointer_y = fb.height / 2

	mut keyboard := open_keyboard()
	defer {
		keyboard.close()
	}

	// An opening arrangement, kept clear of the shortcut column down the left
	// edge. The calculator is not opened: it has a shortcut and a launcher, and
	// three windows is enough to show what the taskbar is for.
	desktop.spawn('Welcome', .welcome, 150, 60, 396, 244)
	desktop.spawn('System', .system, 580, 60, 372, 232)
	desktop.launch_titled('Files')

	mut stats := FrameStats{}
	for desktop.running {
		frame_started := monotonic_millis()

		desktop.update_clock()
		desktop.pump_pointer(mut pointer, fb.width, fb.height)
		desktop.pump_keyboard(mut keyboard)
		after_input := monotonic_millis()

		// Nothing has changed: the framebuffer already holds the right
		// picture, so the frame is skipped entirely rather than recomposed
		// into the same pixels.
		if !desktop.dirty {
			sleep_to_next_frame(frame_started, options.frame_interval)
			continue
		}
		desktop.dirty = false

		desktop.frames++
		tree := desktop.build_tree()
		after_build := monotonic_millis()

		desktop.render(tree)
		after_render := monotonic_millis()

		fb.present(&desktop.canvas)
		after_present := monotonic_millis()

		free_tree(tree)

		sleep_to_next_frame(frame_started, options.frame_interval)

		if options.stats {
			stats.add(after_input - frame_started, after_build - after_input, after_render - after_build, after_present - after_render, monotonic_millis() - after_present)
			stats.report_every(200, monotonic_millis())
		}
	}

	// Leave the console the way it was found rather than on top of a desktop
	// that is no longer being redrawn.
	desktop.canvas.clip = Clip{
		x: 0
		y: 0
		w: desktop.canvas.width
		h: desktop.canvas.height
	}
	desktop.canvas.clear(0x000000)
	fb.present(&desktop.canvas)
	println('vinix-desktop: ${desktop.frames} frames')
}

// pump_pointer maps the device's own coordinate space onto the screen and
// turns the button mask into press and release events.
fn (mut d Desktop) pump_pointer(mut pointer PointerDevice, width int, height int) {
	packet := pointer.poll() or { return }

	// The node exists even on a machine with no pointer hardware, and says so
	// by reporting an empty coordinate range. Without a device there is nothing
	// to draw a cursor for.
	if packet.max_x <= 0 || packet.max_y <= 0 {
		d.pointer_present = false
		return
	}
	d.pointer_present = true

	d.pointer_x = int(i64(packet.x) * i64(width - 1) / i64(packet.max_x))
	d.pointer_y = int(i64(packet.y) * i64(height - 1) / i64(packet.max_y))
	// The level goes in before the move is handled, so a drag can see that the
	// button is no longer held.
	d.buttons = packet.buttons
	d.on_pointer_move(d.pointer_x, d.pointer_y)

	if packet.pressed & button_left != 0 {
		d.on_pointer_down(d.pointer_x, d.pointer_y)
	}
	if packet.released & button_left != 0 {
		d.on_pointer_up(d.pointer_x, d.pointer_y)
	}
}

fn (mut d Desktop) pump_keyboard(mut keyboard Keyboard) {
	keys := keyboard.poll()
	for i := 0; i < keys.len; i++ {
		match keys[i] {
			27, `q`, `Q` {
				d.running = false
			}
			`n`, `N` {
				d.spawn_scattered()
			}
			`c`, `C` {
				// The first hosted application, for a keyboard-only session.
				if available_apps.len > 0 {
					d.launch(available_apps[0])
				}
			}
			else {}
		}
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
