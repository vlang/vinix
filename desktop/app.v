// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Native ui2 applications shown in the desktop's windows.
//
// A ui2 application normally calls `run_vml`, which opens a platform window.
// Here the desktop is the window system: each application runs as its own
// process, hands its element tree to the compositor over app_process.v's pipe
// protocol, and gets back the id of whatever the user hit.
//
// Applications can be native Vinix utilities or adapters around ui2 example
// models compiled by the build's staging step.
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
	exclusive_command string
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
	'start.launch.9', 'start.launch.10', 'start.launch.11', 'start.launch.12', 'start.launch.13']
const app_shortcut_actions = ['shortcut.0', 'shortcut.1', 'shortcut.2', 'shortcut.3', 'shortcut.4',
	'shortcut.5', 'shortcut.6', 'shortcut.7', 'shortcut.8', 'shortcut.9', 'shortcut.10', 'shortcut.11',
	'shortcut.12', 'shortcut.13']

// available_apps is what the Start menu and the wallpaper offer. The calculator's
// window is sized from the constants its own source declares, so the window
// matches what the example asks for rather than a number guessed here.
const available_apps = [
	AppFactory{
		title: 'Files'
		icon: 'builtin:folder'
		width: 460
		height: 360
		process_name: 'vinix-files'
		open: open_files
	},
	AppFactory{
		title: 'Firefox'
		icon: 'builtin:browser'
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
		icon: 'builtin:calculator'
		width: window_width
		height: window_height + default_title_height
		process_name: 'vinix-calculator'
		open: open_calculator
	},
	AppFactory{
		title: 'Terminal'
		icon: 'builtin:terminal'
		width: 560
		height: 340
		process_name: 'vinix-terminal'
		polling: true
		poll_interval_ms: 1000
		keyboard: true
		open: open_terminal
	},
	AppFactory{
		title: 'Settings'
		icon: 'builtin:settings'
		width: 620
		height: 410
		process_name: 'vinix-settings'
		open: open_settings_app
	},
	AppFactory{
		title: 'Activity Monitor'
		icon: 'builtin:activity'
		// Wide enough for four columns without the process names truncating,
		// and tall enough that the list is worth scrolling rather than a
		// glimpse of one.
		width: 520
		height: 400
		process_name: 'vinix-activity'
		polling: true
		poll_interval_ms: 1000
		open: open_activity
	},
	AppFactory{
		title: 'Text Editor'
		icon: 'builtin:editor'
		width: 700
		height: 500
		process_name: 'vinix-editor'
		keyboard: true
		open: open_editor
	},
	AppFactory{
		title: 'Calendar'
		icon: 'builtin:calendar'
		width: 640
		height: 500
		process_name: 'vinix-calendar'
		open: open_calendar
	},
	AppFactory{
		title: 'Clock'
		icon: 'builtin:clock'
		width: 560
		height: 410
		process_name: 'vinix-clock'
		polling: true
		poll_interval_ms: 100
		open: open_clock
	},
	AppFactory{
		title: 'Cocoa Calculator'
		icon: 'builtin:calculator'
		width: 284
		height: 364 + default_title_height
		process_name: 'vinix-cocoa-calculator'
		open: open_cocoa_calculator
	},
	AppFactory{
		title: 'Minecraft'
		icon: 'builtin:block'
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
		title: 'Microsoft Word 2010'
		icon: 'builtin:editor'
		width: wine_word2010_window_width
		height: wine_word2010_window_height + default_title_height
		process_name: 'vinix-wine-word2010'
		polling: true
		keyboard: true
		pointer: true
		open: open_wine_word2010
	},
]

fn open_calculator(mut _ Desktop) !NativeApp {
	return open_native_calculator()
}

fn open_settings_app(mut desktop Desktop) !NativeApp {
	return desktop.open_settings()!
}
