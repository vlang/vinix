// SPDX-License-Identifier: GPL-2.0-or-later
// Desktop-wide integer display scaling shared by Settings and the compositor.
@[has_globals]
module main

const desktop_scale_100 = 1
const desktop_scale_200 = 2

// Vinix's simple framebuffer exposes pixel geometry but no panel DPI/model to
// userspace. Retina MacBooks use native modes above this threshold, while the
// normal QEMU/low-density modes stay below it.
const desktop_hidpi_min_width = 2300
const desktop_hidpi_min_height = 1400

__global (
	desktop_scale_factor = desktop_scale_100
	desktop_applied_scale = desktop_scale_100
	desktop_physical_width int
	desktop_physical_height int
)

fn desktop_scale_valid(scale int) bool {
	return scale == desktop_scale_100 || scale == desktop_scale_200
}

fn desktop_default_scale(width int, height int) int {
	if width >= desktop_hidpi_min_width && height >= desktop_hidpi_min_height {
		return desktop_scale_200
	}
	return desktop_scale_100
}

// A scaled canvas is the logical desktop. Round up so an odd final physical
// row/column is still represented and can be expanded by the presenter.
fn desktop_scaled_extent(pixels int, scale int) int {
	if scale != desktop_scale_200 {
		return pixels
	}
	return (pixels + desktop_scale_200 - 1) / desktop_scale_200
}

fn desktop_configure_scale(width int, height int) int {
	scale := desktop_default_scale(width, height)
	desktop_physical_width = width
	desktop_physical_height = height
	desktop_scale_factor = scale
	desktop_applied_scale = scale
	return scale
}
