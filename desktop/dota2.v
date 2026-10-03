// SPDX-License-Identifier: GPL-2.0-or-later
// Valve's Linux Dota 2 client on the x86 translator and private X11 display.
module main

const dota2_surface_width = 1280
const dota2_surface_height = 720

fn open_dota2(mut _ Desktop) !NativeApp {
	return open_hosted_x11_app('dota2', '/usr/bin/run-dota2', dota2_surface_width,
		dota2_surface_height, 'builtin:gamepad', .dota2_starting, .dota2_missing, .dota2_exited)
}
