// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Hosting ui2 applications in the desktop's windows.
//
// A ui2 application normally calls `run_qml`, which opens a platform window
// and blocks until it closes. There is no platform here to ask — the desktop
// *is* the window system — so it uses ui2's embeddable host instead: the
// application hands over an element tree for a content area of whatever size
// its window happens to be, and gets back the id of whatever the user hit.
//
// Applications can be built in (Files and Settings) or ui2 examples, compiled
// in verbatim by the build's staging step (see tools/stage_app.py).
module main

import ui2

// HostedApp is the whole of what the desktop needs from an application to give
// it a window. ui2's QmlApp satisfies it, so any QML document with a V model
// behind it can be put in a window without the window manager knowing the
// first thing about what it does.
interface HostedApp {
mut:
	build(size ui2.Rect) !ui2.Element
	handle(event_id string) !
}

// AppFactory names an application the desktop can open and the builtin glyph
// that stands for it in the taskbar and on the wallpaper. Most applications
// are hosted in a native desktop window. A large external GUI can instead ask
// for exclusive ownership of the display while its command runs.
struct AppFactory {
	title             string
	icon              string
	width             int
	height            int
	exclusive_command string
	// Given the desktop, because an application may need to read it or change
	// it — Settings does both. Most ignore the argument.
	open fn (mut desktop Desktop) !HostedApp = unsafe { nil }
}

// Action ids are literals because launchers and shortcuts are rebuilt on
// every redraw and Vinix runs without a garbage collector. Keep them parallel
// with available_apps; their numeric suffix is what launch_index reads back.
const app_launcher_actions = ['taskbar.launch.0', 'taskbar.launch.1', 'taskbar.launch.2',
	'taskbar.launch.3', 'taskbar.launch.4', 'taskbar.launch.5', 'taskbar.launch.6', 'taskbar.launch.7',
	'taskbar.launch.8']
const app_shortcut_actions = ['shortcut.0', 'shortcut.1', 'shortcut.2', 'shortcut.3', 'shortcut.4',
	'shortcut.5', 'shortcut.6', 'shortcut.7', 'shortcut.8']

// available_apps is what the taskbar and the wallpaper offer. The calculator's
// window is sized from the constants its own source declares, so the window
// matches what the example asks for rather than a number guessed here.
const available_apps = [
	AppFactory{
		title: 'Files'
		icon: 'builtin:folder'
		width: 460
		height: 360
		open: open_files
	},
	AppFactory{
		title: 'Firefox'
		icon: 'builtin:browser'
		// Firefox is an X11/GTK application. Xorg must own the framebuffer and
		// input devices while it runs, so it is deliberately not embedded in a
		// native desktop window.
		exclusive_command: '/usr/bin/run-firefox'
	},
	AppFactory{
		title: 'Calculator'
		icon: 'builtin:calculator'
		width: window_width
		height: window_height + default_title_height
		open: open_calculator
	},
	AppFactory{
		title: 'Terminal'
		icon: 'builtin:terminal'
		width: 560
		height: 340
		open: open_terminal
	},
	AppFactory{
		title: 'Settings'
		icon: 'builtin:settings'
		width: 620
		height: 410
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
		open: open_activity
	},
	AppFactory{
		title: 'Text Editor'
		icon: 'builtin:editor'
		width: 700
		height: 500
		open: open_editor
	},
	AppFactory{
		title: 'Calendar'
		icon: 'builtin:calendar'
		width: 640
		height: 500
		open: open_calendar
	},
	AppFactory{
		title: 'Clock'
		icon: 'builtin:clock'
		width: 560
		height: 410
		open: open_clock
	},
]

fn open_calculator(mut _ Desktop) !HostedApp {
	return ui2.new_qml_app[Calculator](calculator_qml_source, initial_calculator())!
}

fn open_settings_app(mut desktop Desktop) !HostedApp {
	return desktop.open_settings()!
}
