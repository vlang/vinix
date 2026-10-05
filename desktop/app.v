// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Native ui2 applications shown in the desktop's windows.
//
// A ui2 application normally calls `run_vml`, which opens a platform window.
// Here the desktop is the window system: each application runs as its own
// process, hands its element tree to the compositor over app_process.v's pipe
// protocol, and gets back the id of whatever the user hit.
//
// Applications can be native Vinix utilities or adapters around ui2 models
// compiled by the build's staging step.
module main

import ui2

// NativeApp is the client process' local application contract. A VML-backed
// adapter satisfies it, so a declarative document with a V model can be served
// to the compositor without the window manager knowing what it does.
interface NativeApp {
mut:
	build(size ui2.Rect) !ui2.Element
	handle(event_id string) !
}

// AppFactory names an application the desktop can open and the builtin glyph
// that stands for it in the taskbar and on the wallpaper. A native app has an
// exec name and a factory used by its child process. A large external GUI can
// instead ask for exclusive ownership of the display while its command runs.
struct AppFactory {
	title        string
	icon         string
	width        int
	height       int
	process_name string
	polling      bool
	// Minimum time between remote poll requests. Zero keeps per-frame
	// polling for hosted framebuffers whose pixels can always change.
	poll_interval_ms  u64
	keyboard          bool
	pointer           bool
	launch_top_right  bool
	hide_body_cursor  bool
	// A standalone app implements the pipe protocol in its own executable; it
	// therefore has no factory callback in the compositor's multicall binary.
	standalone        bool
	// A standalone app the image does not carry names the pkg package that
	// provides it. Launching it before that install explains how to get it.
	install_package   string
	exclusive_command string
	// Typing reaches it as the US keys, whatever the input source: a game's
	// controls and a virtual machine's own keyboard layout are positional.
	us_keys bool
	// Used only after exec, in the application process. Settings receives that
	// process' synchronized desktop-state proxy; most apps ignore it.
	open fn (mut desktop Desktop) !NativeApp = unsafe { nil }
}

// Action ids are literals because Start-menu entries and shortcuts are rebuilt
// on every redraw and Vinix runs without a garbage
// collector. Keep them parallel with available_apps; their numeric suffix is
// what launch_index reads back.
const app_start_actions = ['start.launch.0', 'start.launch.1', 'start.launch.2', 'start.launch.3',
	'start.launch.4', 'start.launch.5', 'start.launch.6', 'start.launch.7', 'start.launch.8',
	'start.launch.9', 'start.launch.10', 'start.launch.11', 'start.launch.12', 'start.launch.13',
	'start.launch.14', 'start.launch.15', 'start.launch.16', 'start.launch.17', 'start.launch.18',
	'start.launch.19', 'start.launch.20', 'start.launch.21', 'start.launch.22', 'start.launch.23',
	'start.launch.24', 'start.launch.25', 'start.launch.26', 'start.launch.27', 'start.launch.28', 'start.launch.29']
const app_shortcut_actions = ['shortcut.0', 'shortcut.1', 'shortcut.2', 'shortcut.3', 'shortcut.4',
	'shortcut.5', 'shortcut.6', 'shortcut.7', 'shortcut.8', 'shortcut.9', 'shortcut.10', 'shortcut.11',
	'shortcut.12', 'shortcut.13', 'shortcut.14', 'shortcut.15', 'shortcut.16', 'shortcut.17',
	'shortcut.18', 'shortcut.19', 'shortcut.20', 'shortcut.21', 'shortcut.22', 'shortcut.23',
	'shortcut.24', 'shortcut.25', 'shortcut.26', 'shortcut.27', 'shortcut.28', 'shortcut.29']

// available_apps is what the Start menu and the wallpaper offer. The calculator's
// window is sized from the constants its own source declares, so the window
// matches what the example asks for rather than a number guessed here.
const available_apps = [
	AppFactory{
		title: 'Files'
		icon: 'asset:files'
		width: 700
		height: 400
		process_name: 'vinix-files'
		keyboard: true
		pointer: true
		open: open_files_with_context_menu
	},
	AppFactory{
		title: 'Firefox'
		icon: 'asset:firefox'
		width: firefox_window_width
		height: firefox_window_height + default_title_height
		process_name: 'vinix-firefox'
		polling: true
		poll_interval_ms: 50
		keyboard: true
		pointer: true
		open: open_firefox
	},
	AppFactory{
		title: 'Calculator'
		icon: 'asset:calculator'
		width: window_width
		height: window_height + default_title_height
		process_name: 'vinix-calculator'
		open: open_calculator
	},
	AppFactory{
		title: 'Terminal'
		icon: 'asset:terminal'
		width: 560
		height: 340
		process_name: 'vinix-terminal'
		polling: true
		// Key input gets one immediate poll. If that races PTY echo, come back
		// quickly enough that typing still feels interactive instead of waiting
		// for the old one-second idle cadence.
		poll_interval_ms: 100
		keyboard: true
		open: open_terminal
	},
	AppFactory{
		title: 'Settings'
		icon: 'asset:settings'
		width: 620
		height: 410
		process_name: 'vinix-settings'
		open: open_settings_app
	},
	AppFactory{
		title: 'Activity Monitor'
		icon: 'asset:activity'
		width: 900
		height: 640
		process_name: 'vinix-activity'
		keyboard: true
		pointer: true
		polling: true
		poll_interval_ms: 250
		open: open_activity
	},
	AppFactory{
		title: 'Text Editor'
		icon: 'asset:editor'
		width: 700
		height: 500
		process_name: 'vinix-editor'
		keyboard: true
		open: open_editor
	},
	AppFactory{
		title: 'Calendar'
		icon: 'asset:calendar'
		width: 640
		height: 500
		process_name: 'vinix-calendar'
		open: open_calendar
	},
	AppFactory{
		title: 'Clock'
		icon: 'asset:clock'
		width: 560
		height: 410
		process_name: 'vinix-clock'
		polling: true
		poll_interval_ms: 100
		open: open_clock
	},
	AppFactory{
		title: 'Minecraft'
		icon: 'asset:minecraft'
		width: minecraft_window_width
		height: minecraft_window_height + default_title_height
		process_name: 'vinix-minecraft'
		polling: true
		keyboard: true
		pointer: true
		open: open_minecraft
	},
	AppFactory{
		title: 'Wine Calculator'
		icon: 'builtin:calculator'
		width: wine_surface_width
		height: wine_surface_height + default_title_height
		process_name: 'vinix-wine-calculator'
		polling: true
		keyboard: true
		pointer: true
		open: open_wine_calculator
	},
	AppFactory{
		title: 'Wine Notepad'
		icon: 'builtin:editor'
		width: wine_notepad_surface_width
		height: wine_notepad_surface_height + default_title_height
		process_name: 'vinix-wine-notepad'
		polling: true
		keyboard: true
		pointer: true
		open: open_wine_notepad
	},
	AppFactory{
		title: 'Microsoft Word 2013'
		icon: 'builtin:editor'
		width: wine_word2013_window_width
		height: wine_word2013_window_height + default_title_height
		process_name: 'vinix-wine-word2013'
		polling: true
		keyboard: true
		pointer: true
		open: open_wine_word2013
	},
	AppFactory{
		title: 'Blender'
		icon: 'asset:blender'
		width: blender_window_width
		height: blender_window_height + default_title_height
		process_name: 'vinix-blender'
		polling: true
		poll_interval_ms: 50
		keyboard: true
		pointer: true
		open: open_blender
	},
	AppFactory{
		title: capture_app_title
		icon: 'asset:capture'
		width: 560
		height: 430
		process_name: 'vinix-capture'
		polling: true
		poll_interval_ms: 100
		open: open_capture
	},
	AppFactory{
		title: 'OBS Studio'
		icon: 'asset:capture'
		width: obs_window_width
		height: obs_window_height + default_title_height
		process_name: 'vinix-obs'
		polling: true
		poll_interval_ms: 50
		keyboard: true
		pointer: true
		open: open_obs
	},
	AppFactory{
		title: 'GIMP'
		icon: 'builtin:editor'
		width: gimp_window_width
		height: gimp_window_height + default_title_height
		process_name: 'vinix-gimp'
		polling: true
		poll_interval_ms: 50
		keyboard: true
		pointer: true
		open: open_gimp
	},
	AppFactory{
		title: 'Disk Usage'
		icon: 'asset:disk_usage'
		// Two ranking panels side by side, each wide enough for a name, a size
		// and a path that is not cut in half.
		width: 880
		height: 580
		process_name: 'vinix-disk-usage'
		// A scan is a state machine the compositor advances; without polling
		// the walk would only move when the window was clicked.
		polling: true
		poll_interval_ms: 33
		open: open_disk_usage
	},
	AppFactory{
		title:            'VOffice Writer'
		icon:             '/usr/bin/assets/logo.png'
		width:            900
		height:           680
		process_name:     'voffice-writer'
		polling:          true
		poll_interval_ms: 50
		keyboard:         true
		pointer:          true
		standalone:       true
		install_package:  'voffice'
	},
	AppFactory{
		title:            'VOffice Calc'
		icon:             '/usr/bin/assets/logo.png'
		width:            940
		height:           680
		process_name:     'voffice-calc'
		polling:          true
		poll_interval_ms: 50
		keyboard:         true
		pointer:          true
		standalone:       true
		install_package:  'voffice'
	},
	AppFactory{
		title:            'LibreOffice'
		icon:             'builtin:editor'
		width:            libreoffice_window_width
		height:           libreoffice_window_height + default_title_height
		process_name:     'vinix-libreoffice'
		polling:          true
		poll_interval_ms: 50
		keyboard:         true
		pointer:          true
		open:             open_libreoffice
	},
	AppFactory{
		title:            'Chromium'
		icon:             'asset:chromium'
		width:            chromium_window_width
		height:           chromium_window_height + default_title_height
		process_name:     'vinix-chromium'
		polling:          true
		poll_interval_ms: 50
		keyboard:         true
		pointer:          true
		open:             open_chromium
	},
	AppFactory{
		title: 'DOOM'
		icon: 'asset:doom'
		width: doom_window_width
		height: doom_window_height + default_title_height
		process_name: 'vinix-doom'
		polling: true
		poll_interval_ms: 50
		keyboard: true
		pointer: true
		launch_top_right: true
		hide_body_cursor: true
		us_keys: true
		open: open_doom
	},
	AppFactory{
		title: 'Vinix in QEMU'
		icon: 'asset:terminal'
		width: qemu_window_width
		height: qemu_window_height + default_title_height
		process_name: 'vinix-qemu-window'
		polling: true
		keyboard: true
		pointer: true
		us_keys: true
		open: open_qemu_desktop
	},
	AppFactory{
		title: 'Steam'
		icon: 'asset:steam'
		width: steam_window_width
		height: steam_window_height + default_title_height
		process_name: 'vinix-steam'
		polling: true
		keyboard: true
		pointer: true
		open: open_steam
	},
	AppFactory{
		title: 'Gothic II'
		icon: 'builtin:gamepad'
		width: gothic_window_width
		height: gothic_window_height + default_title_height
		process_name: 'vinix-opengothic'
		polling: true
		keyboard: true
		pointer: true
		us_keys: true
		open: open_opengothic
	},
	AppFactory{
		title: 'Android Calculator'
		icon: 'asset:calculator'
		width: android_surface_width
		height: android_surface_height + default_title_height
		process_name: 'vinix-android-calculator'
		polling: true
		poll_interval_ms: 50
		keyboard: true
		pointer: true
		open: open_android_calculator
	},
	AppFactory{
		title: 'Roblox'
		icon: 'builtin:gamepad'
		width: roblox_surface_width
		height: roblox_surface_height + default_title_height
		process_name: 'vinix-roblox'
		polling: true
		poll_interval_ms: 50
		keyboard: true
		pointer: true
		us_keys: true
		open: open_roblox
	},
	AppFactory{
		title: 'Dota 2'
		icon: 'builtin:gamepad'
		width: dota2_surface_width
		height: dota2_surface_height + default_title_height
		process_name: 'vinix-dota2'
		polling: true
		poll_interval_ms: 50
		keyboard: true
		pointer: true
		hide_body_cursor: true
		us_keys: true
		open: open_dota2
	},
	AppFactory{
		title: 'iOS Calculator'
		icon: 'asset:calculator'
		width: 390
		height: 680 + default_title_height
		process_name: 'vinix-ios-calculator'
		keyboard: true
		standalone: true
	},
]

fn files_settings_factory() AppFactory {
	return AppFactory{
		title:           files_settings_window_title
		icon:            'asset:files'
		width:           540
		height:          550
		process_name:    files_settings_process_name
		keyboard:        true
		pointer:         true
		open:            open_files_settings_window
	}
}

fn open_calculator(mut _ Desktop) !NativeApp {
	return open_native_calculator()
}

fn open_settings_app(mut desktop Desktop) !NativeApp {
	return desktop.open_settings()!
}

// app_title_text is how an application's or a window's title is shown. The
// titles themselves stay English, because the window manager recognises
// windows by them and `--open` names applications by them. Product names read
// the same in every language and are shown as they are.
fn app_title_text(title string) string {
	key := match title {
		'Files' { 'app.files' }
		'Calculator' { 'app.calculator' }
		'Terminal' { 'app.terminal' }
		'Settings' { 'app.settings' }
		'Activity Monitor' { 'app.activity_monitor' }
		'Text Editor' { 'app.text_editor' }
		'Calendar' { 'app.calendar' }
		'Clock' { 'app.clock' }
		'Wine Calculator' { 'app.wine_calculator' }
		'Wine Notepad' { 'app.wine_notepad' }
		'Vinix in QEMU' { 'app.qemu' }
		'Android Calculator' { 'app.android_calculator' }
		capture_app_title { 'app.capture' }
		files_settings_window_title { 'app.files_settings' }
		external_app_title { 'window.external_app' }
		outdated_window_title { 'window.outdated' }
		'Welcome' { 'window.welcome' }
		'System' { 'window.system' }
		'Palette' { 'window.palette' }
		'Notes' { 'window.notes' }
		else { '' }
	}
	return if key.len > 0 { tr(key) } else { title }
}
