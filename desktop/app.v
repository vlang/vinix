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

// AppFactory names an application the desktop can open, the size its window
// should start at, and the builtin glyph that stands for it in the taskbar and
// on the wallpaper.
struct AppFactory {
	title  string
	icon   string
	width  int
	height int
	open   fn () !HostedApp @[required]
}

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
		title: 'Calculator'
		icon: 'builtin:calculator'
		width: window_width
		height: window_height + title_height
		open: open_calculator
	},
	AppFactory{
		title: 'Settings'
		icon: 'builtin:maximize'
		width: 620
		height: 410
		open: open_settings
	},
]

fn open_calculator() !HostedApp {
	return ui2.new_qml_app[Calculator](calculator_qml_source, initial_calculator())!
}
