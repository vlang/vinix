// SPDX-License-Identifier: GPL-2.0-or-later
// Host-side end-to-end test for the same Mach-O/AppKit path used on Vinix.
module main

import ui2

#include <sys/mman.h>

#include <sys/stat.h>

#include <fcntl.h>

#include <unistd.h>

fn C.mmap(base voidptr, length usize, prot int, flags int, fd int, offset i64) voidptr

fn C.munmap(base voidptr, length usize) int

fn C.open(path &char, flags int, mode ...int) int

fn C.close(fd int) int

fn C.read(fd int, buffer voidptr, count usize) int

fn C.stat(path &char, info &C.stat) int

struct Desktop {}

interface NativeApp {
mut:
	build(size ui2.Rect) !ui2.Element
	handle(event_id string) !
}

struct DesktopFileInfo {
	size   u64
	is_dir bool
}

fn desktop_stat(path string) ?DesktopFileInfo {
	mut info := C.stat{}
	if C.stat(&char(path.str), &info) != 0 {
		return none
	}
	return DesktopFileInfo{
		size: u64(info.st_size)
		is_dir: (u32(info.st_mode) & u32(C.S_IFMT)) == u32(C.S_IFDIR)
	}
}

fn desktop_read_file(path string, buffer voidptr, maximum u64) i64 {
	fd := C.open(&char(path.str), C.O_RDONLY)
	if fd < 0 {
		return -1
	}
	mut total := u64(0)
	for total < maximum {
		read := C.read(fd, unsafe { voidptr(u64(buffer) + total) }, usize(maximum - total))
		if read <= 0 {
			C.close(fd)
			return if read == 0 { i64(total) } else { -1 }
		}
		total += u64(read)
	}
	C.close(fd)
	return i64(total)
}

fn element_with_text(element ui2.Element, text string) ?ui2.Element {
	if element.text == text {
		return element
	}
	for child in element.children {
		if found := element_with_text(child, text) {
			return found
		}
	}
	return none
}

fn press(mut app NativeApp, title string) {
	tree := app.build(ui2.rect(0, 0, 284, 364)) or { panic(err) }
	button := element_with_text(tree, title) or { panic('missing Cocoa button ${title}') }
	app.handle(button.id) or { panic(err) }
}

fn main() {
	if arguments().len > 2 {
		panic('usage: runtime-test Calculator.app')
	}
	bundle_path := if arguments().len == 2 {
		arguments()[1]
	} else {
		'/Applications/Calculator.app'
	}
	mut desktop := Desktop{}
	mut app := open_cocoa_calculator_at(bundle_path, mut desktop) or { panic(err) }
	initial := app.build(ui2.rect(0, 0, 284, 364)) or { panic(err) }
	assert initial.kind == .screen
	assert initial.children.len == 19
	assert (element_with_text(initial, '0') or { panic('missing initial display') }).id == 'cocoa.display'
	press(mut app, '7')
	press(mut app, '+')
	press(mut app, '8')
	press(mut app, '=')
	result := app.build(ui2.rect(0, 0, 284, 364)) or { panic(err) }
	assert (element_with_text(result, '15') or { panic('Objective-C action did not update display') }).id == 'cocoa.display'
	if mut app is CocoaApp {
		app.close_app()
	}
	println('PASS AArch64 Mach-O Objective-C Cocoa calculator')
}
