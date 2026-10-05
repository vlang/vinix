// SPDX-License-Identifier: GPL-2.0-or-later
// OpenGothic's native ARM64 Vulkan client, hosted in a Vinix desktop window.
module main

const gothic_surface_width = 1280
const gothic_surface_height = 720
const gothic_window_width = 1280
const gothic_window_height = 720

fn open_opengothic(mut _ Desktop) !NativeApp {
	// The engine ships without the game. Name the directory that wants the
	// original archives rather than let the launcher exit at once.
	if C.access(c'/usr/bin/run-opengothic', C.X_OK) == 0
		&& C.access(c'/usr/share/games/gothic2/_work/Data', C.R_OK) != 0 {
		return &HostedX11App{
			surface_width:  gothic_surface_width
			surface_height: gothic_surface_height
			icon:           'builtin:gamepad'
			failed:         true
			failure:        .gothic_data_missing
		}
	}
	return open_hosted_x11_app('opengothic', '/usr/bin/run-opengothic', gothic_surface_width,
		gothic_surface_height, 'builtin:gamepad', .gothic_starting, .gothic_missing, .gothic_exited)
}
