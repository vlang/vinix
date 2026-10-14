// SPDX-License-Identifier: GPL-2.0-or-later
module main

const zed_surface_width = 850
const zed_surface_height = 600

fn open_zed(mut _ Desktop) !NativeApp {
	return open_hosted_x11_app('zed', '/usr/bin/run-zed', zed_surface_width, zed_surface_height,
		'asset:zed', .zed_starting, .zed_missing, .zed_exited)
}
