// SPDX-License-Identifier: GPL-2.0-or-later
module main

const emacs_surface_width = 900
const emacs_surface_height = 650

fn open_emacs(mut _ Desktop) !NativeApp {
	return open_hosted_x11_app('emacs', '/usr/bin/run-emacs', emacs_surface_width,
		emacs_surface_height, 'builtin:editor', .emacs_starting, .emacs_missing, .emacs_exited)
}
