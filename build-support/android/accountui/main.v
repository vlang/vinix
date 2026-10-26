// SPDX-License-Identifier: GPL-2.0-or-later
// A desktop-owned window for an already running authenticator ART process.
module main

import os
import strconv
import desktop.windowfb

#include <signal.h>

fn C.signal(i32, voidptr) voidptr

struct Options {
	surface  int
	input    int
	lifetime int
	socket   string
}

fn descriptor(text string) !int {
	n := strconv.atoi(text)!
	if n < 3 || n.str() != text { return error('invalid inherited descriptor') }
	return n
}

fn options(args []string) !Options {
	if args.len != 6 && args.len != 8 {
		return error('usage: vinix-android-account-ui --surface-fd N --input-fd N --lifetime-fd N [--window-socket PATH]')
	}
	if args[0] != '--surface-fd' || args[2] != '--input-fd' || args[4] != '--lifetime-fd'
		|| (args.len == 8 && args[6] != '--window-socket') {
		return error('invalid account UI arguments')
	}
	surface := descriptor(args[1])!
	input := descriptor(args[3])!
	lifetime := descriptor(args[5])!
	if surface == input || surface == lifetime || input == lifetime {
		return error('account UI descriptors must be distinct')
	}
	return Options{surface, input, lifetime, if args.len == 8 {
		args[7].clone()
	} else {
		windowfb.socket_path()
	}}
}

fn run() ! {
	args := options(os.args[1..])!
	defer { unsafe { args.socket.free() } }
	// The root broker supplies the descriptors, then execs this helper under
	// the desktop's ordinary UID. No APK-supplied paths or UI commands enter.
	authorize_lifetime(args.lifetime)!
	defer { C.close(args.lifetime) }
	if !lifetime_alive(args.lifetime)! { return error('account UI request expired') }
	prepare_input(args.input)!
	defer { C.close(args.input) }
	mut source := open_source(args.surface)!
	C.close(args.surface)
	defer { source.close() }
	unsafe { C.signal(C.SIGPIPE, C.SIG_IGN) }
	mut window := open_window(args.socket, source.width, source.height, args.lifetime)!
	defer { window.close() }
	send_ready(args.lifetime)!
	mut input := InputQueue{}
	for lifetime_alive(args.lifetime)! {
		if !bridge_tick(mut window, &source, mut input, args.input)! { return }
		wait_bridge(&window, args.input, args.lifetime, input.pending())!
	}
}

fn main() {
	run() or {
		eprintln('account UI: ' + err.msg())
		exit(1)
	}
}
