// SPDX-License-Identifier: GPL-2.0-or-later
module guestvalidation

import cachecli
import dl
import strconv
import math
import time

pub struct WindowAttributes {
pub mut:
	x                     i32
	y                     i32
	width                 i32
	height                i32
	border_width          i32
	depth                 i32
	visual                voidptr
	root                  u64
	window_class          i32
	bit_gravity           i32
	win_gravity           i32
	backing_store         i32
	backing_planes        u64
	backing_pixel         u64
	save_under            i32
	colormap              u64
	map_installed         i32
	map_state             i32
	all_event_masks       i64
	your_event_mask       i64
	do_not_propagate_mask i64
	override_redirect     i32
	screen                voidptr
}

type XOpen = fn (&char) voidptr
type XRoot = fn (voidptr) u64
type XTree = fn (voidptr, u64, &u64, &u64, &&u64, &u32) i32
type XAttributes = fn (voidptr, u64, &WindowAttributes) i32
type XFetch = fn (voidptr, u64, &&char) i32
type XFree = fn (voidptr) i32
type XAtom = fn (voidptr, &char, i32) u64
type XProperty = fn (voidptr, u64, u64, i64, i64, i32, u64, &u64, &i32, &u64, &u64, &&u8) i32
type XClose = fn (voidptr) i32

pub struct XLibrary {
	handle        voidptr
	open_display  XOpen       @[required]
	root          XRoot       @[required]
	tree          XTree       @[required]
	attributes    XAttributes @[required]
	fetch         XFetch      @[required]
	release       XFree       @[required]
	atom          XAtom       @[required]
	property      XProperty   @[required]
	close_display XClose      @[required]
}

pub fn open_xlib(path string) !XLibrary {
	handle := dl.open_opt(path, dl.rtld_lazy)!
	library := load_xlib(handle) or {
		dl.close(handle)
		return err
	}
	return library
}

fn load_xlib(handle voidptr) !XLibrary {
	return XLibrary{ handle: handle, open_display: unsafe { XOpen(dl.sym_opt(handle, 'XOpenDisplay')!) }, root: unsafe { XRoot(dl.sym_opt(handle, 'XDefaultRootWindow')!) }, tree: unsafe { XTree(dl.sym_opt(handle, 'XQueryTree')!) }, attributes: unsafe { XAttributes(dl.sym_opt(handle, 'XGetWindowAttributes')!) }, fetch: unsafe { XFetch(dl.sym_opt(handle, 'XFetchName')!) }, release: unsafe { XFree(dl.sym_opt(handle, 'XFree')!) }, atom: unsafe { XAtom(dl.sym_opt(handle, 'XInternAtom')!) }, property: unsafe { XProperty(dl.sym_opt(handle, 'XGetWindowProperty')!) }, close_display: unsafe { XClose(dl.sym_opt(handle, 'XCloseDisplay')!) } }
}

pub fn (library XLibrary) close() { dl.close(library.handle) }

fn xtext(bytes []u8) string {
	// X11 title buffers are UTF-8 with replacement at malformed byte sequences.
	return decode_utf8(bytes)
}

fn (library XLibrary) title(display voidptr, window u64) string {
	mut legacy := &char(unsafe { nil })
	if library.fetch(display, window, &legacy) != 0 && legacy != unsafe { nil } {
		defer { library.release(legacy) }
		return xtext(unsafe { legacy.vstring().bytes().clone() })
	}
	name := library.atom(display, c'_NET_WM_NAME', 1)
	utf8 := library.atom(display, c'UTF8_STRING', 1)
	if name == 0 || utf8 == 0 { return '' }
	mut actual_type := u64(0)
	mut format := i32(0)
	mut items := u64(0)
	mut remaining := u64(0)
	mut data := &u8(unsafe { nil })
	status := library.property(display, window, name, 0, 1024, 0, utf8, &actual_type, &format, &items, &remaining, &data)
	defer { if data != unsafe { nil } { library.release(data) } }
	if status != 0 || data == unsafe { nil } { return '' }
	return xtext(unsafe { data.vbytes(int(items)).clone() })
}

pub fn (library XLibrary) find(display voidptr, window u64, expected string, depth int) ?string {
	if depth > 8 { return none }
	mut root := u64(0)
	mut parent := u64(0)
	mut children := &u64(unsafe { nil })
	mut count := u32(0)
	defer { if children != unsafe { nil } { library.release(children) } }
	if library.tree(display, window, &root, &parent, &children, &count) == 0 { return none }
	for index in 0 .. int(count) {
		child := unsafe { children[index] }
		mut attributes := WindowAttributes{}
		if library.attributes(display, child, &attributes) != 0 {
			title := library.title(display, child)
			if attributes.map_state == 2 && title.contains(expected) { return title }
		}
		if found := library.find(display, child, expected, depth + 1) {
			if found != '' { return found }
		}
	}
	return none
}

pub fn check_xwindow(library XLibrary, name string, expected string, seconds f64) !int {
	if name.bytes().any(it > 127) { return error('X11 display name must be ASCII') }
	deadline := f64(time.sys_mono_now()) / f64(time.second) + seconds
	mut display := unsafe { nil }
	for display == unsafe { nil } {
		cachecli.checkpoint()!
		display = library.open_display(name.str)
		if display != unsafe { nil } { break }
		if f64(time.sys_mono_now()) / f64(time.second) >= deadline { return 1 }
		guest_pause(1)!
	}
	defer { library.close_display(display) }
	root := library.root(display)
	for {
		cachecli.checkpoint()!
		if title := library.find(display, root, expected, 0) {
			if title != '' {
				println('WINDOW=' + title)
				return 0
			}
		}
		if f64(time.sys_mono_now()) / f64(time.second) >= deadline { return 1 }
		guest_pause(1)!
	}
	return 1
}

pub fn xwindow_cli(argv []string) !int {
	args := cachecli.arguments(argv, [], [], [], 2, 3, 'Find a viewable X11 window by title.\nUsage: x-window-check DISPLAY TITLE [WAIT_SECONDS]') or { return error_with_code(err.msg(), 2) }
	seconds := if args.positional.len == 3 {
		strconv.atof64(args.positional[2]) or { return error_with_code(err.msg(), 2) }
	} else {
		f64(0)
	}
	if math.is_nan(seconds) || math.is_inf(seconds, 0) || seconds < 0 {
		return error_with_code('WAIT_SECONDS must be nonnegative', 2)
	}
	library := open_xlib(env('VINIX_XWINDOW_LIBRARY', 'libX11.so.6'))!
	defer { library.close() }
	return check_xwindow(library, args.positional[0], args.positional[1], seconds)!
}
