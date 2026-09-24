// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// X11 applications embedded in native Vinix windows. Xvfb owns the upstream
// application's display while the Vinix compositor maps its live XWD surface.
module main

import ui2

const firefox_surface_width = 1280
const firefox_surface_height = 900
const firefox_window_width = 1280
const firefox_window_height = 900
// The floor below which a hosted surface is blitted even with no damage
// reported, so a host that under-reports cannot freeze a window.
const hosted_refresh_floor_ms = i64(1000)
// Polls spent looking for a counter that a host may never publish. The X
// server is up well inside this; after it, stop asking the filesystem.
const hosted_damage_attempts = 400
const chromium_surface_width = 1280
const chromium_surface_height = 900
const chromium_window_width = 1280
const chromium_window_height = 900
const gimp_surface_width = 1280
const gimp_surface_height = 900
const gimp_window_width = 1280
const gimp_window_height = 900
const obs_surface_width = 1280
const obs_surface_height = 900
const obs_window_width = 1280
const obs_window_height = 900
// Writer lays a page out for the width it is given. 1280x900 is the same
// surface the browsers use, and wide enough for a document page beside the
// sidebar without the toolbars wrapping onto a third row.
const libreoffice_surface_width = 1280
const libreoffice_surface_height = 900
const libreoffice_window_width = 1280
const libreoffice_window_height = 900
const wine_surface_width = 326
const wine_surface_height = 430
const wine_notepad_surface_width = 310
const wine_notepad_surface_height = 230
// Office 2013 restores a 768x576 top-level window in a fresh prefix. Matching
// the private X server to it avoids unused root-window bands, and its 4:3
// aspect ratio maps exactly into the native 680x510 Vinix frame.
const wine_word2013_surface_width = 768
const wine_word2013_surface_height = 576
const wine_word2013_window_width = 680
const wine_word2013_window_height = 510
const minecraft_surface_width = 1280
const minecraft_surface_height = 720
// Keep Minecraft windowed, but give its 16:9 game surface enough desktop
// space to be comfortably playable. This is 30% larger than the previous
// 1520x856 frame and still fits the standard 2048x1536 QEMU desktop with its
// title bar and the Vinix taskbar visible.
const minecraft_window_width = 1976
const minecraft_window_height = 1113
// Steam's sign-in window is 700x440. Match its private X11 root and native
// frame so the root background does not surround the client window.
const steam_surface_width = 700
const steam_surface_height = 440
const steam_window_width = 700
const steam_window_height = 440
const qemu_surface_width = 1024
const qemu_surface_height = 768
const qemu_window_width = 1024
const qemu_window_height = 768
const doom_surface_width = 720
const doom_surface_height = 540
const doom_window_width = 720
const doom_window_height = 540
const wine_host_event_magic = u32(0x56574831) // VWH1

enum WineHostEventKind as u32 {
	motion = 1
	button_down
	button_up
	keys
	middle_down
	middle_up
	right_down
	right_up
	wheel_up
	wheel_down
}

struct WineHostEvent {
	magic u32
	kind  u32
	// The receiving C host uses int32_t and asserts a 20-byte wire record.
	x      i32
	y      i32
	length u32
}

struct HostedX11App {
mut:
	host_pid        int = -1
	input_fd        int = -1
	directory       string
	xwd_path        string
	damage_path     string
	image_path      string
	surface_width   int
	surface_height  int
	icon            string
	starting        HostedText
	exited          HostedText
	ready           bool
	damage_counter  &u32 = unsafe { nil }
	damage_attempts int
	damage_sequence u32
	last_blit_ms    i64
	failed          bool
	failure         HostedText
}

// HostedText is what a hosted window says in place of its surface. The window
// keeps which message it is showing rather than the words, so a message still
// on screen when the language changes is shown in the new one.
enum HostedText {
	none_
	firefox_starting
	firefox_missing
	firefox_exited
	chromium_starting
	chromium_missing
	chromium_exited
	gimp_starting
	gimp_missing
	gimp_exited
	obs_starting
	obs_missing
	obs_exited
	libreoffice_starting
	libreoffice_missing
	libreoffice_exited
	windows_starting
	wine_missing
	windows_exited
	word_starting
	win64_wine_missing
	word_exited
	word_setup_starting
	word_setup_closed
	word_media_missing
	steam_installing
	steam_missing
	steam_exited
	qemu_starting
	qemu_missing
	qemu_exited
	minecraft_starting
	minecraft_missing
	minecraft_exited
	doom_starting
	doom_missing
	doom_wad_missing
	doom_exited
	xvfb_missing
	host_failed
}

fn (t HostedText) text() string {
	return match t {
		.none_ { '' }
		.firefox_starting { tr('wine.firefox.starting') }
		.firefox_missing { tr('wine.firefox.missing') }
		.firefox_exited { tr('wine.firefox.exited') }
		.chromium_starting { tr('wine.chromium.starting') }
		.chromium_missing { tr('wine.chromium.missing') }
		.chromium_exited { tr('wine.chromium.exited') }
		.gimp_starting { tr('wine.gimp.starting') }
		.gimp_missing { tr('wine.gimp.missing') }
		.gimp_exited { tr('wine.gimp.exited') }
		.obs_starting { tr('wine.obs.starting') }
		.obs_missing { tr('wine.obs.missing') }
		.obs_exited { tr('wine.obs.exited') }
		.libreoffice_starting { tr('wine.libreoffice.starting') }
		.libreoffice_missing { tr('wine.libreoffice.missing') }
		.libreoffice_exited { tr('wine.libreoffice.exited') }
		.windows_starting { tr('wine.windows.starting') }
		.wine_missing { tr('wine.windows.missing') }
		.windows_exited { tr('wine.windows.exited') }
		.word_starting { tr('wine.word.starting') }
		.win64_wine_missing { tr('wine.word.missing') }
		.word_exited { tr('wine.word.exited') }
		.word_setup_starting { tr('wine.word.setup_starting') }
		.word_setup_closed { tr('wine.word.setup_closed') }
		.word_media_missing { tr('wine.word.media_missing') }
		.steam_installing { tr('wine.steam.installing') }
		.steam_missing { tr('wine.steam.missing') }
		.steam_exited { tr('wine.steam.exited') }
		.qemu_starting { tr('wine.qemu.starting') }
		.qemu_missing { tr('wine.qemu.missing') }
		.qemu_exited { tr('wine.qemu.exited') }
		.minecraft_starting { tr('wine.minecraft.starting') }
		.minecraft_missing { tr('wine.minecraft.missing') }
		.minecraft_exited { tr('wine.minecraft.exited') }
		.doom_starting { tr('wine.doom.starting') }
		.doom_missing { tr('wine.doom.missing') }
		.doom_wad_missing { tr('wine.doom.wad_missing') }
		.doom_exited { tr('wine.doom.exited') }
		.xvfb_missing { tr('wine.xvfb_missing') }
		.host_failed { tr('wine.host_failed') }
	}
}

// Release images leave Firefox out: the first-run app page and
// `pkg install firefox` fetch it from Alpine. Report that from the window
// rather than starting a private X server for a browser that is not there.
fn open_firefox(mut _ Desktop) !NativeApp {
	if C.access(c'/usr/lib/firefox-esr/firefox-esr', C.X_OK) != 0
		&& C.access(c'/usr/lib/firefox/firefox', C.X_OK) != 0 {
		return &HostedX11App{
			surface_width: firefox_surface_width
			surface_height: firefox_surface_height
			icon: 'asset:firefox'
			failed: true
			failure: .firefox_missing
		}
	}
	return open_hosted_x11_app('firefox', '/usr/bin/run-firefox', firefox_surface_width,
		firefox_surface_height, 'asset:firefox', .firefox_starting, .firefox_missing,
		.firefox_exited)
}

// Chromium is not in the image: `pkg install chromium` fetches it from Alpine.
// Report that from the window itself rather than starting a private X server
// for a browser that cannot be there.
fn open_chromium(mut _ Desktop) !NativeApp {
	if C.access(c'/usr/lib/chromium/chrome', C.X_OK) != 0 {
		return &HostedX11App{
			surface_width: chromium_surface_width
			surface_height: chromium_surface_height
			icon: 'asset:chromium'
			failed: true
			failure: .chromium_missing
		}
	}
	return open_hosted_x11_app('chromium', '/usr/bin/run-chromium', chromium_surface_width,
		chromium_surface_height, 'asset:chromium', .chromium_starting, .chromium_missing,
		.chromium_exited)
}

fn open_gimp(mut _ Desktop) !NativeApp {
	if C.access(c'/usr/bin/gimp', C.X_OK) != 0 {
		return &HostedX11App{
			surface_width: gimp_surface_width
			surface_height: gimp_surface_height
			icon: 'builtin:editor'
			failed: true
			failure: .gimp_missing
		}
	}
	return open_hosted_x11_app('gimp', '/usr/bin/run-gimp', gimp_surface_width, gimp_surface_height, 'builtin:editor', .gimp_starting, .gimp_missing, .gimp_exited)
}

fn open_obs(mut _ Desktop) !NativeApp {
	if C.access(c'/usr/bin/obs', C.X_OK) != 0 {
		return &HostedX11App{
			surface_width: obs_surface_width
			surface_height: obs_surface_height
			icon: 'asset:capture'
			failed: true
			failure: .obs_missing
		}
	}
	return open_hosted_x11_app('obs', '/usr/bin/run-obs', obs_surface_width,
		obs_surface_height, 'asset:capture', .obs_starting, .obs_missing, .obs_exited)
}

// LibreOffice is a 900 MiB closure that an image can reasonably be built
// without, exactly like Chromium. Report that from the window rather than
// starting a private X server for a suite that cannot be there.
fn open_libreoffice(mut _ Desktop) !NativeApp {
	if C.access(c'/usr/lib/libreoffice/program/soffice.bin', C.X_OK) != 0 {
		return &HostedX11App{
			surface_width: libreoffice_surface_width
			surface_height: libreoffice_surface_height
			icon: 'builtin:editor'
			failed: true
			failure: .libreoffice_missing
		}
	}
	return open_hosted_x11_app('libreoffice', '/usr/bin/run-libreoffice', libreoffice_surface_width,
		libreoffice_surface_height, 'builtin:editor', .libreoffice_starting, .libreoffice_missing,
		.libreoffice_exited)
}

fn open_wine_calculator(mut _ Desktop) !NativeApp {
	return open_hosted_x11_app('wine', '/usr/bin/calculator', wine_surface_width, wine_surface_height, 'builtin:calculator', .windows_starting, .wine_missing, .windows_exited)
}

fn open_wine_notepad(mut _ Desktop) !NativeApp {
	return open_hosted_x11_app('wine-notepad', '/usr/bin/notepad', wine_notepad_surface_width, wine_notepad_surface_height, 'builtin:editor', .windows_starting, .wine_missing, .windows_exited)
}

fn open_wine_word2013(mut _ Desktop) !NativeApp {
	for word in [
		'/root/.wine-word2013-x86_64/drive_c/Program Files/Microsoft Office 15/root/office15/WINWORD.EXE',
		'/root/.wine-word2013-x86_64/drive_c/Program Files/Microsoft Office/Office15/WINWORD.EXE',
	] {
		if C.access(&char(word.str), 0) == 0 {
			mut app := open_hosted_x11_app('wine-word2013', '/usr/bin/word2013', wine_word2013_surface_width, wine_word2013_surface_height, 'builtin:editor', .word_starting, .win64_wine_missing, .word_exited)
			app.image_path = '${office_xwd_image_prefix}${app.xwd_path}'
			return app
		}
	}
	for setup in ['/root/word2013-media/office/setup64.exe', '/root/word2013-media/office/SETUP64.EXE',
		'/root/word2013-media/setup.exe', '/root/word2013-media/SETUP.EXE'] {
		if C.access(&char(setup.str), 0) == 0 {
			return open_hosted_x11_app('wine-word2013-setup', '/usr/bin/word2013-setup', wine_word2013_surface_width, wine_word2013_surface_height, 'builtin:editor', .word_setup_starting, .win64_wine_missing, .word_setup_closed)
		}
	}
	return &HostedX11App{
		surface_width: wine_word2013_surface_width
		surface_height: wine_word2013_surface_height
		icon: 'builtin:editor'
		failed: true
		failure: .word_media_missing
	}
}

// Steam is Valve's x86 Linux client on the translators, staged by
// build-steam-aarch64.sh. It is not in the default image.
fn open_steam(mut _ Desktop) !NativeApp {
	if C.access(c'/usr/bin/steam', C.X_OK) != 0 {
		return &HostedX11App{
			surface_width: steam_surface_width
			surface_height: steam_surface_height
			icon: 'asset:steam'
			failed: true
			failure: .steam_missing
		}
	}
	return open_hosted_x11_app('steam', '/usr/bin/steam-hosted', steam_surface_width,
		steam_surface_height, 'asset:steam', .steam_installing, .steam_missing, .steam_exited)
}

fn open_qemu_desktop(mut _ Desktop) !NativeApp {
	return open_hosted_x11_app('qemu', '/usr/bin/vinix-qemu-desktop', qemu_surface_width,
		qemu_surface_height, 'asset:terminal', .qemu_starting, .qemu_missing, .qemu_exited)
}

fn open_minecraft(mut _ Desktop) !NativeApp {
	if C.access(c'/usr/bin/minecraft', C.X_OK) != 0 {
		return &HostedX11App{
			surface_width:  minecraft_surface_width
			surface_height: minecraft_surface_height
			icon:           'asset:minecraft'
			failed:         true
			failure:        .minecraft_missing
		}
	}
	return open_hosted_x11_app('minecraft', '/usr/bin/minecraft', minecraft_surface_width,
		minecraft_surface_height, 'asset:minecraft', .minecraft_starting, .minecraft_missing,
		.minecraft_exited)
}

fn open_doom(mut _ Desktop) !NativeApp {
	if C.access(c'/usr/bin/chocolate-doom', C.X_OK) != 0 {
		return &HostedX11App{
			surface_width: doom_surface_width
			surface_height: doom_surface_height
			icon: 'asset:doom'
			failed: true
			failure: .doom_missing
		}
	}
	if C.access(c'/usr/share/games/doom/doom1.wad', C.R_OK) != 0 {
		return &HostedX11App{
			surface_width: doom_surface_width
			surface_height: doom_surface_height
			icon: 'asset:doom'
			failed: true
			failure: .doom_wad_missing
		}
	}
	return open_hosted_x11_app('doom', '/usr/bin/run-doom', doom_surface_width,
		doom_surface_height, 'asset:doom', .doom_starting, .doom_missing, .doom_exited)
}

fn open_hosted_x11_app(name string, command string, surface_width int, surface_height int,
	icon string, starting HostedText, missing HostedText, exited HostedText) &HostedX11App {
	mut app := &HostedX11App{
		surface_width: surface_width
		surface_height: surface_height
		icon: icon
		starting: starting
		exited: exited
	}
	process_id := C.getpid()
	// Xvfb writes its framebuffer through a shared mmap. Use the per-boot
	// scratch mount when init provided it, keeping constant frame updates off
	// the persistent root filesystem.
	base := if C.access(c'/run/vinix-hosted-x11/.tmpfs-ready', C.R_OK) == 0 {
		'/run/vinix-hosted-x11'
	} else {
		'/tmp'
	}
	// PIDs can be reused while the compositor still has the previous XWD file
	// mapped. Give each launch a new path so its surface cannot resolve to a
	// cached frame from an earlier X server.
	app.directory = '${base}/vinix-${name}-${process_id}-${monotonic_millis()}'
	app.xwd_path = '${app.directory}/Xvfb_screen0'
	app.damage_path = '${app.directory}/damage'
	app.image_path = '${xwd_image_prefix}${app.xwd_path}'

	if C.access(c'/usr/bin/Xvfb', C.X_OK) != 0 {
		app.failed = true
		app.failure = .xvfb_missing
		return app
	}
	if C.access(&char(command.str), C.X_OK) != 0 {
		app.failed = true
		app.failure = missing
		return app
	}
	// Minecraft's saved launch description can outlive the package that
	// generated it. Ask the host to enforce the Xvfb dimensions as well as
	// passing them to the launcher, so an old or ignored game-size option can
	// never leave a smaller GLFW window floating in a white root surface.
	host := desktop_spawn_wine_host(app.directory, surface_width, surface_height, command,
		name == 'minecraft', name == 'doom' || name == 'qemu', name == 'obs') or {
		app.failed = true
		app.failure = .host_failed
		return app
	}
	app.host_pid = host.pid
	app.input_fd = host.input
	return app
}

fn (mut app HostedX11App) build(size ui2.Rect) !ui2.Element {
	width := int(size.width)
	height := int(size.height)
	mut children := frame_elements(2)
	if app.ready {
		children << ui2.image('', app.image_path, ui2.rect(0, 0, f64(width), f64(height)))
	} else {
		message := if app.failed { app.failure.text() } else { app.starting.text() }
		children << ui2.button_with_image('', '', app.icon, ui2.rect(f64((width - 48) / 2), f64((height - 82) / 2), 48, 48), ui2.BoxStyle{ transparent: true }, ui2.TextStyle{ color: app_accent })
		children << ui2.label('', message, ui2.rect(16, f64((height - 82) / 2 + 58), f64(width - 32), 20), ui2.TextStyle{
			color: if app.failed { u32(0xb42318) } else { body_muted }
			size: 12
			align: .center
		})
	}
	return ui2.screen(0xf3f4f6, children)
}

fn (mut app HostedX11App) handle(_ string) ! {}

fn (mut app HostedX11App) poll() bool {
	if app.host_pid > 0 && desktop_child_exited(app.host_pid) {
		app.host_pid = -1
		if app.input_fd >= 0 {
			desktop_close(app.input_fd)
			app.input_fd = -1
		}
		app.ready = false
		app.failed = true
		app.failure = app.exited
		return true
	}
	if !app.ready {
		desktop_stat(app.xwd_path) or { return false }
		app.ready = true
		return true
	}
	return app.surface_changed()
}

// Xvfb changes its shared XWD mapping in place, so nothing in the ui2 model
// says that a new frame arrived. The host watches the X DAMAGE stream and
// publishes a counter beside the framebuffer; rescaling 1280x900 pixels only
// when that counter moves is the difference between a hosted browser sharing
// the emulated processor and being buried under its own compositor.
//
// A host that cannot report damage never writes the file, and every poll blits
// as Vinix always did.
fn (mut app HostedX11App) surface_changed() bool {
	now := monotonic_millis()
	if app.damage_counter == unsafe { nil } {
		app.map_damage_counter()
	}
	if app.damage_counter == unsafe { nil } {
		app.last_blit_ms = now
		return true
	}
	// The host writes this through the same file's pages, so asking costs a
	// load rather than a read() that would queue behind whatever the machine
	// is paging in.
	sequence := unsafe { *app.damage_counter }
	if sequence != app.damage_sequence {
		app.damage_sequence = sequence
		app.last_blit_ms = now
		return true
	}
	// A host that reports less than its application draws would otherwise
	// leave a window stale for ever. Coming back once a second bounds that
	// mistake to something nobody would call a freeze, and still costs a
	// twentieth of what blitting every frame did.
	if now - app.last_blit_ms >= hosted_refresh_floor_ms {
		app.last_blit_ms = now
		return true
	}
	return false
}

// The counter file appears once the host's X server is up, which is a moment
// after the framebuffer does, so this keeps trying until it is there. A host
// that never publishes one leaves the desktop blitting every frame, which is
// what it did before the counter existed.
fn (mut app HostedX11App) map_damage_counter() {
	if app.damage_attempts >= hosted_damage_attempts {
		return
	}
	app.damage_attempts++
	fd := desktop_open_ro_nonblock(app.damage_path)
	if fd < 0 {
		return
	}
	mapping := desktop_mmap_readonly(fd, sizeof(u32))
	desktop_close(fd)
	if mapping == unsafe { nil } {
		return
	}
	app.damage_counter = unsafe { &u32(mapping) }
}

fn (mut app HostedX11App) pointer_input_enabled() bool {
	return app.ready && app.input_fd >= 0
}

fn (mut app HostedX11App) send_host_event(kind WineHostEventKind, x int, y int, keys string) {
	if app.input_fd < 0 || keys.len > 4096 {
		return
	}
	event := WineHostEvent{
		magic: wine_host_event_magic
		kind: u32(kind)
		x: i32(x)
		y: i32(y)
		length: u32(keys.len)
	}
	if !desktop_write_all(app.input_fd, &event, sizeof(WineHostEvent)) {
		return
	}
	if keys.len > 0 {
		desktop_write_all(app.input_fd, keys.str, u64(keys.len))
	}
}

fn (mut app HostedX11App) pointer_event(phase AppPointerPhase, button AppPointerButton, scroll int, x int, y int, width int, height int) {
	if !app.pointer_input_enabled() || width <= 0 || height <= 0 {
		return
	}
	mut surface_x := x * app.surface_width / width
	mut surface_y := y * app.surface_height / height
	if surface_x < 0 {
		surface_x = 0
	}
	if surface_y < 0 {
		surface_y = 0
	}
	if surface_x >= app.surface_width {
		surface_x = app.surface_width - 1
	}
	if surface_y >= app.surface_height {
		surface_y = app.surface_height - 1
	}
	kind := match phase {
		.move { WineHostEventKind.motion }
		.down {
			match button {
				.left { WineHostEventKind.button_down }
				.middle { WineHostEventKind.middle_down }
				.right { WineHostEventKind.right_down }
				else { return }
			}
		}
		.up {
			match button {
				.left { WineHostEventKind.button_up }
				.middle { WineHostEventKind.middle_up }
				.right { WineHostEventKind.right_up }
				else { return }
			}
		}
		.scroll {
			if scroll == 0 {
				return
			}
			count := if scroll < -4 || scroll > 4 { 4 } else if scroll < 0 { -scroll } else { scroll }
			for _ in 0 .. count {
				app.send_host_event(if scroll > 0 { WineHostEventKind.wheel_up } else { WineHostEventKind.wheel_down },
					surface_x, surface_y, '')
			}
			return
		}
	}
	app.send_host_event(kind, surface_x, surface_y, '')
}

fn (mut app HostedX11App) key_input(text string) {
	if text.len > 0 {
		app.send_host_event(.keys, 0, 0, text)
	}
}

fn (mut app HostedX11App) close_app() {
	if app.input_fd >= 0 {
		// The host treats EOF as its shutdown request and owns the Wine and Xvfb
		// process tree. Do not synchronously wait for that cleanup here: under
		// translation a Windows process can take long enough to stop that it
		// would freeze the compositor while an otherwise ordinary Vinix window
		// is being closed. The app process exits after replying to the close
		// request, and init reaps the now-orphaned host when it finishes.
		desktop_close(app.input_fd)
		app.input_fd = -1
	}
	app.host_pid = -1
}
