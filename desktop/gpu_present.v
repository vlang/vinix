// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module main

#flag -I @VMODROOT
#include "gpu_present.h"

fn C.vinix_gpu_present_create(width int, height int) voidptr
fn C.vinix_gpu_present_frame(handle voidptr, source &u32, source_width int, source_height int, source_stride int, destination &u32, destination_width int, destination_height int, destination_stride int) int
fn C.vinix_gpu_present_destroy(handle voidptr)

struct GpuPresenter {
mut:
	handle    voidptr
	attempted bool
	failed    bool
}

fn (mut presenter GpuPresenter) present(source &Canvas, destination &u32, width int, height int, stride int) bool {
	$if vinix_gpu_present ? {
		if presenter.failed {
			return false
		}
		if !presenter.attempted {
			presenter.attempted = true
			presenter.handle = C.vinix_gpu_present_create(width, height)
			if presenter.handle == unsafe { nil } {
				presenter.failed = true
				return false
			}
		}
		if C.vinix_gpu_present_frame(presenter.handle, source.pixels, source.width,
			source.height, source.stride, destination, width, height, stride) != 0 {
			return true
		}
		C.vinix_gpu_present_destroy(presenter.handle)
		presenter.handle = unsafe { nil }
		presenter.failed = true
	}
	return false
}

fn (mut presenter GpuPresenter) close() {
	$if vinix_gpu_present ? {
		if presenter.handle != unsafe { nil } {
			C.vinix_gpu_present_destroy(presenter.handle)
			presenter.handle = unsafe { nil }
		}
	}
}
