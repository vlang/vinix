// SPDX-License-Identifier: MIT
module gfx

pub fn is_valid() bool { return false }

pub enum PixelFormat {
	rgba8
	bgra8
}

pub enum Wrap {
	clamp_to_edge
	repeat
	mirrored_repeat
}

pub enum Filter {
	nearest
	linear
}
