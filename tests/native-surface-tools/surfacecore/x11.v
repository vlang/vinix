// SPDX-License-Identifier: GPL-2.0-or-later
module surfacecore

import dl

struct Image {
	width   i32
	height  i32
	xoffset i32
	format  i32
	data    &u8
}

type OpenDisplay = fn (&char) voidptr
type ScreenCount = fn (voidptr) i32
type Query = fn (voidptr, &char, &i32, &i32, &i32) i32
type RootWindow = fn (voidptr, i32) u64
type GetImage = fn (voidptr, u64, i32, i32, u32, u32, u64, i32) &Image
type CloseDisplay = fn (voidptr) i32
type DestroyImage = fn (&Image) i32

pub fn obs_capture(path string, library string, display_name string) ! {
	handle := dl.open_opt(library, dl.rtld_now)!
	defer { dl.close(handle) }
	open_display := unsafe { OpenDisplay(dl.sym_opt(handle, 'XOpenDisplay')!) }
	screen_count := unsafe { ScreenCount(dl.sym_opt(handle, 'XScreenCount')!) }
	query := unsafe { Query(dl.sym_opt(handle, 'XQueryExtension')!) }
	root_window := unsafe { RootWindow(dl.sym_opt(handle, 'XRootWindow')!) }
	get_image := unsafe { GetImage(dl.sym_opt(handle, 'XGetImage')!) }
	close_display := unsafe { CloseDisplay(dl.sym_opt(handle, 'XCloseDisplay')!) }
	destroy_image := unsafe { DestroyImage(dl.sym_opt(handle, 'XDestroyImage')!) }
	display := open_display(display_name.str)
	if display == unsafe { nil } { return error('cannot open OBS X11 display') }
	defer { close_display(display) }
	if screen_count(display) != 2 { return error('OBS display does not have two screens') }
	mut major, first_event, first_error := i32(0), i32(0), i32(0)
	if query(display, c'MIT-SHM', &major, &first_event, &first_error) == 0 {
		return error('MIT-SHM is unavailable to OBS')
	}
	if query(display, c'RANDR', &major, &first_event, &first_error) != 0 {
		return error('RandR hides Display 1 from OBS XSHM capture')
	}
	mut framebuffer := map_file(path, true)!
	defer { framebuffer.close() }
	offset := u64(framebuffer.word(0)!) + u64(framebuffer.word(76)!) * 12
	if offset + 4 > u64(framebuffer.length) { return error('incomplete capture framebuffer') }
	mut previous := [4]u8{}
	marker := [u8(0x56), 0x34, 0x12, 0]!
	for index in 0 .. 4 { previous[index] = unsafe { framebuffer.data[int(offset) + index] } }
	defer { for index in 0 .. 4 {
		unsafe { framebuffer.data[int(offset) + index] = previous[index] }
	}
	 }
	for index in 0 .. 4 {
		unsafe { framebuffer.data[int(offset) + index] = marker[index] }
	}
	root := root_window(display, 1)
	image := get_image(display, root, 0, 0, 1, 1, 0xffffffff, 2)
	if image == unsafe { nil } {
		return error('compositor capture framebuffer is not visible on Display 1')
	}
	defer { destroy_image(image) }
	if image.data == unsafe { nil } {
		return error('compositor capture framebuffer is not visible on Display 1')
	}
	for index in 0 .. 4 {
		if unsafe { image.data[index] } != marker[index] {
			return error('compositor capture framebuffer is not visible on Display 1')
		}
	}
}
