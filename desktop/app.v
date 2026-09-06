// Hosting ui2 applications in the desktop's windows.
//
// A ui2 application normally calls `run_qml`, which opens a platform window
// and blocks until it closes. There is no platform here to ask — the desktop
// *is* the window system — so it uses ui2's embeddable host instead: the
// application hands over an element tree for a content area of whatever size
// its window happens to be, and gets back the id of whatever the user hit.
//
// The applications themselves are ui2's own examples, compiled in verbatim by
// the build's staging step (see tools/stage_app.py). Nothing about them is
// rewritten for Vinix.
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

// AppFactory names an application the desktop can open and the size its window
// should start at.
struct AppFactory {
	title  string
	width  int
	height int
	open   fn () !HostedApp @[required]
}

// available_apps is what the taskbar offers. The calculator's window is sized
// from the constants its own source declares, so the window matches what the
// example asks for rather than a number guessed here.
const available_apps = [
	AppFactory{
		title: 'Calculator'
		width: window_width
		height: window_height + title_height
		open: open_calculator
	},
]

fn open_calculator() !HostedApp {
	return ui2.new_qml_app[Calculator](calculator_qml_source, initial_calculator())!
}
