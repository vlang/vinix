// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Filesystem operations shared by the desktop and Files context menus.
module main

#include <sys/stat.h>

fn C.mkdir(path &char, mode u32) i32
fn C.rename(old_filename &char, new_filename &char) i32
fn C.rmdir(path &char) i32

const desktop_directory = '${desktop_home}/Desktop'
const file_context_clipboard_path = '/tmp/.vinix-file-clipboard'
const file_context_copy_buffer_size = 64 * 1024
const file_context_max_depth = 64
const file_context_name_attempts = 1000

enum CreateItemKind {
	file
	folder
}

enum FileClipboardMode {
	copy
	cut
}

struct FileClipboard {
	mode FileClipboardMode
	path string
}

fn ensure_directory(path string) ! {
	if info := desktop_lstat(path) {
		if info.is_dir {
			return
		}
		return error('${path} exists and is not a directory')
	}
	if C.mkdir(&char(path.str), 0o755) != 0 {
		return error('cannot create directory ${path}')
	}
}

fn ensure_desktop_directory() ! {
	ensure_directory(desktop_directory)!
}

fn create_item_base_name(kind CreateItemKind) string {
	return match kind {
		.file { 'New File' }
		.folder { 'New Folder' }
	}
}

fn create_item_path(directory string, name string) string {
	if directory == '/' {
		return '/${name}'
	}
	if directory.ends_with('/') {
		return '${directory}${name}'
	}
	return '${directory}/${name}'
}

// create_unique_item returns the full path so the caller can immediately put
// the new item into rename mode instead of making the user find it again.
fn create_unique_item(directory string, kind CreateItemKind) !string {
	base := create_item_base_name(kind)
	for attempt in 0 .. file_context_name_attempts {
		name := if attempt == 0 { base } else { '${base} (${attempt + 1})' }
		path := create_item_path(directory, name)
		if desktop_lstat(path) == none {
			ok := match kind {
				.file {
					fd := C.open(&char(path.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL, 0o644)
					if fd >= 0 {
						desktop_close(fd)
						true
					} else {
						false
					}
				}
				.folder { C.mkdir(&char(path.str), 0o755) == 0 }
			}
			if ok {
				if attempt > 0 {
					unsafe { name.free() }
				}
				return path
			}
			message := 'cannot create ${path}'
			unsafe {
				path.free()
				if attempt > 0 { name.free() }
			}
			return error(message)
		}
		unsafe {
			path.free()
			if attempt > 0 { name.free() }
		}
	}
	return error('cannot find an unused ${base} name in ${directory}')
}

fn file_context_valid_name(name string) bool {
	if name.len == 0 || name.len > 255 || name == '.' || name == '..' {
		return false
	}
	for ch in name {
		if ch == 0 || ch == `/` {
			return false
		}
	}
	return true
}

fn rename_item_path(path string, name string) !string {
	if !file_context_valid_name(name) {
		return error('invalid file name')
	}
	old_name := file_path_name(path)
	if old_name == name {
		return path.clone()
	}
	parent := parent_path(path)
	next := create_item_path(parent, name)
	if desktop_lstat(next) != none {
		message := '${next} already exists'
		unsafe { next.free() }
		return error(message)
	}
	if C.rename(&char(path.str), &char(next.str)) != 0 {
		message := 'cannot rename ${path}'
		unsafe { next.free() }
		return error(message)
	}
	return next
}

fn file_context_clipboard_store(mode FileClipboardMode, path string) bool {
	if desktop_lstat(path) == none {
		return false
	}
	mut data := []u8{cap: path.len + 1}
	data << if mode == .copy { `C` } else { `X` }
	for ch in path {
		data << ch
	}
	ok := desktop_write_file(file_context_clipboard_path, data.data, u64(data.len))
	unsafe { data.free() }
	return ok
}

fn file_context_clipboard_load() ?FileClipboard {
	info := desktop_stat(file_context_clipboard_path) or { return none }
	if info.is_dir || info.size < 2 || info.size > 4097 {
		return none
	}
	mut data := []u8{len: int(info.size)}
	got := desktop_read_file(file_context_clipboard_path, data.data, info.size)
	if got < 2 {
		unsafe { data.free() }
		return none
	}
	mode := match data[0] {
		`C` { FileClipboardMode.copy }
		`X` { FileClipboardMode.cut }
		else {
			unsafe { data.free() }
			return none
		}
	}
	path := data[1..int(got)].bytestr()
	unsafe { data.free() }
	if desktop_lstat(path) == none {
		unsafe { path.free() }
		return none
	}
	return FileClipboard{
		mode: mode
		path: path
	}
}

fn file_context_clipboard_clear() {
	desktop_unlink(file_context_clipboard_path)
}

fn file_context_clipboard_available() bool {
	clipboard := file_context_clipboard_load() or { return false }
	unsafe { clipboard.path.free() }
	return true
}

fn file_context_path_inside(path string, directory string) bool {
	if path == directory {
		return true
	}
	if directory == '/' {
		return path.starts_with('/')
	}
	return path.len > directory.len && path.starts_with(directory)
		&& path[directory.len] == `/`
}

fn file_context_copy_regular_file(source string, destination string) ! {
	input := C.open(&char(source.str), C.O_RDONLY)
	if input < 0 {
		return error('cannot open ${source}')
	}
	output := C.open(&char(destination.str), C.O_WRONLY | C.O_CREAT | C.O_EXCL, 0o644)
	if output < 0 {
		desktop_close(input)
		return error('cannot create ${destination}')
	}
	mut buffer := []u8{len: file_context_copy_buffer_size}
	mut ok := true
	for {
		got := desktop_read(input, buffer.data, u64(buffer.len))
		if got < 0 {
			if C.errno == C.EINTR {
				continue
			}
			ok = false
			break
		}
		if got == 0 {
			break
		}
		if !desktop_write_all(output, buffer.data, u64(got)) {
			ok = false
			break
		}
	}
	unsafe { buffer.free() }
	if desktop_close(input) != 0 {
		ok = false
	}
	if desktop_close(output) != 0 {
		ok = false
	}
	if !ok {
		desktop_unlink(destination)
		return error('cannot copy ${source}')
	}
}

fn file_context_copy_path_depth(source string, destination string, depth int) ! {
	if depth > file_context_max_depth {
		return error('folder nesting is too deep')
	}
	info := desktop_lstat(source) or { return error('${source} no longer exists') }
	if info.is_file {
		file_context_copy_regular_file(source, destination)!
		return
	}
	if !info.is_dir {
		return error('copying this file type is not supported')
	}
	if C.mkdir(&char(destination.str), 0o755) != 0 {
		return error('cannot create ${destination}')
	}
	dir := desktop_opendir(source)
	if dir == unsafe { nil } {
		C.rmdir(&char(destination.str))
		return error('cannot open ${source}')
	}
	mut names_storage := [max_name_len]u8{}
	mut names := unsafe { (&names_storage[0]).vbytes(names_storage.len) }
	mut count := 0
	mut failure := ''
	for count < max_entries && desktop_readdir(dir, mut names) {
		count++
		name := unsafe { cstring_to_vstring(&char(&names_storage[0])) }
		if name == '.' || name == '..' {
			unsafe { name.free() }
			continue
		}
		source_child := create_item_path(source, name)
		destination_child := create_item_path(destination, name)
		file_context_copy_path_depth(source_child, destination_child, depth + 1) or {
			failure = err.msg()
		}
		unsafe {
			name.free()
			source_child.free()
			destination_child.free()
		}
		if failure != '' {
			break
		}
	}
	desktop_closedir(dir)
	if failure != '' {
		file_context_remove_path(destination) or {}
		return error(failure)
	}
}

fn file_context_copy_path(source string, destination string) ! {
	file_context_copy_path_depth(source, destination, 0)!
}

fn file_context_remove_path_depth(path string, depth int) ! {
	if depth > file_context_max_depth {
		return error('folder nesting is too deep')
	}
	info := desktop_lstat(path) or { return error('${path} no longer exists') }
	if !info.is_dir {
		if desktop_unlink(path) != 0 {
			return error('cannot delete ${path}')
		}
		return
	}
	dir := desktop_opendir(path)
	if dir == unsafe { nil } {
		return error('cannot open ${path}')
	}
	mut names_storage := [max_name_len]u8{}
	mut names := unsafe { (&names_storage[0]).vbytes(names_storage.len) }
	mut count := 0
	mut failure := ''
	for count < max_entries && desktop_readdir(dir, mut names) {
		count++
		name := unsafe { cstring_to_vstring(&char(&names_storage[0])) }
		if name == '.' || name == '..' {
			unsafe { name.free() }
			continue
		}
		child := create_item_path(path, name)
		file_context_remove_path_depth(child, depth + 1) or {
			failure = err.msg()
		}
		unsafe {
			name.free()
			child.free()
		}
		if failure != '' {
			break
		}
	}
	desktop_closedir(dir)
	if failure != '' {
		return error(failure)
	}
	if C.rmdir(&char(path.str)) != 0 {
		return error('cannot delete ${path}')
	}
}

fn file_context_remove_path(path string) ! {
	file_context_remove_path_depth(path, 0)!
}

fn file_context_unique_copy_destination(directory string, source string) !string {
	base := file_path_name(source)
	if base.len == 0 || base == '/' {
		return error('cannot paste this path')
	}
	for attempt in 0 .. file_context_name_attempts {
		name := if attempt == 0 {
			base
		} else if attempt == 1 {
			'${base} copy'
		} else {
			'${base} copy (${attempt})'
		}
		path := create_item_path(directory, name)
		if desktop_lstat(path) == none {
			if attempt > 0 {
				unsafe { name.free() }
			}
			return path
		}
		unsafe {
			path.free()
			if attempt > 0 { name.free() }
		}
	}
	return error('cannot find an unused copy name in ${directory}')
}

// paste_file_clipboard returns the pasted path so a caller can select or
// refresh it. Cut prefers rename(2), then falls back to copy+delete across
// filesystems.
fn paste_file_clipboard(directory string) !string {
	destination_info := desktop_lstat(directory) or { return error('${directory} no longer exists') }
	if !destination_info.is_dir {
		return error('${directory} is not a directory')
	}
	clipboard := file_context_clipboard_load() or { return error('nothing to paste') }
	defer {
		unsafe { clipboard.path.free() }
	}
	parent := parent_path(clipboard.path)
	if clipboard.mode == .cut && parent == directory {
		file_context_clipboard_clear()
		return clipboard.path.clone()
	}
	source_info := desktop_lstat(clipboard.path) or { return error('clipboard item no longer exists') }
	if source_info.is_dir && file_context_path_inside(directory, clipboard.path) {
		return error('cannot paste a folder into itself')
	}
	destination := file_context_unique_copy_destination(directory, clipboard.path)!
	if clipboard.mode == .cut && C.rename(&char(clipboard.path.str), &char(destination.str)) == 0 {
		file_context_clipboard_clear()
		return destination
	}
	file_context_copy_path(clipboard.path, destination) or {
		unsafe { destination.free() }
		return err
	}
	if clipboard.mode == .cut {
		file_context_remove_path(clipboard.path) or {
			file_context_remove_path(destination) or {}
			unsafe { destination.free() }
			return err
		}
		file_context_clipboard_clear()
	}
	return destination
}

// Replace an open descendant path after renaming one of its ancestor folders.
fn file_context_rebased_path(path string, old_prefix string, new_prefix string) string {
	if path == old_prefix {
		return new_prefix.clone()
	}
	if file_context_path_inside(path, old_prefix) {
		return new_prefix + path[old_prefix.len..]
	}
	return path.clone()
}
