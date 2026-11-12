// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

import os

pub struct GraphicsLibrary {
pub:
	source string
	name string
}

pub fn graphics_libraries() [2]GraphicsLibrary {
	return [GraphicsLibrary{'libfreetype.so.6.20.2', 'libfreetype.so.6'},
		GraphicsLibrary{'libfontconfig.so.1.12.1', 'libfontconfig.so.1'}]!
}

// Graphical startup also consumes libraries loaded by name and font data.
// Require each original ordinary file and the complete copied font set;
// hashes on the prepared payload cannot replace distribution provenance.
pub fn admit_graphics_layout(runtime string, inputs map[string]string) ! {
	mut distribution := ''
	defer { unsafe { distribution.free() } }
	for library in graphics_libraries() {
		suffix := '/usr/lib/' + library.source
		destination := runtime + '/root/usr/lib/' + library.name
		defer { unsafe { suffix.free(); destination.free() } }
		original := layout_input(inputs, suffix)!
		defer { unsafe { original.free() } }
		parent := unsafe { tos(original.str, original.len - suffix.len) }
		if distribution == '' { distribution = parent.clone() }
		else if parent != distribution { return error('Wine graphics libraries use different distributions') }
		bytes := layout_bytes(destination)!
		digest := patch_digest(bytes)
		defer { unsafe { bytes.free(); digest.free() } }
		if digest != inputs[original] { return error('Wine graphics library differs: ' + library.name) }
	}
	font_root := distribution + '/usr/share/fonts'
	copied_root := runtime + '/root/usr/share/fonts'
	defer { unsafe { font_root.free(); copied_root.free() } }
	font_paths := os.walk_ext(font_root, '', hidden: true)
	copy_paths := os.walk_ext(copied_root, '', hidden: true)
	defer {
		for path in font_paths { unsafe { path.free() } }
		for path in copy_paths { unsafe { path.free() } }
		unsafe { (&array(&font_paths)).free(); (&array(&copy_paths)).free() }
	}
	mut count := 0
	mut truetype := false
	for path in font_paths {
		if !os.is_file(path) { continue }
		if count >= 1024 || path !in inputs { return error('missing Wine graphics font input: ' + path) }
		original := layout_bytes(path)!
		defer { unsafe { original.free() } }
		relative := unsafe { tos(path.str + font_root.len, path.len - font_root.len) }
		destination := copied_root + relative
		defer { unsafe { destination.free() } }
		copied := layout_bytes(destination)!
		digest := patch_digest(original)
		defer { unsafe { copied.free(); digest.free() } }
		if digest != inputs[path] || copied != original { return error('Wine graphics font differs: ' + path) }
		truetype = truetype || path.ends_with('.ttf')
		count++
	}
	mut copies := 0
	for path in copy_paths { if os.is_file(path) { copies++ } }
	if !truetype || count == 0 || copies != count {
		return error('Wine graphics font inventory differs')
	}
}

fn layout_bytes(path string) !string {
	fd := C.open(path.str, C.O_RDONLY | C.O_NOFOLLOW | C.O_NONBLOCK | C.O_CLOEXEC)
	if fd < 0 { return error('Wine layout file is unavailable or linked: ' + path) }
	defer { C.close(fd) }
	mut before := C.stat{}
	if C.fstat(fd, unsafe { &before }) != 0 || u32(before.st_mode) & 0o170000 != 0o100000
		|| before.st_size < 0 || before.st_size > 64 * 1024 * 1024 {
		return error('Wine layout requires a bounded ordinary file: ' + path)
	}
	mut bytes := []u8{len: int(before.st_size)}
	defer { unsafe { bytes.free() } }
	mut count := 0
	for count < bytes.len {
		n := C.read(fd, unsafe { &bytes[count] }, uint(bytes.len - count))
		if n <= 0 { return error('incomplete Wine layout file: ' + path) }
		count += int(n)
	}
	mut sentinel := u8(0)
	mut after := C.stat{}
	if C.read(fd, unsafe { &sentinel }, 1) != 0 || C.fstat(fd, unsafe { &after }) != 0
		|| before.st_dev != after.st_dev || before.st_ino != after.st_ino || before.st_size != after.st_size
		|| before.st_mtime != after.st_mtime || before.st_ctime != after.st_ctime {
		return error('Wine layout file changed while reading: ' + path)
	}
	return bytes.bytestr()
}

fn layout_input(inputs map[string]string, suffix string) !string {
	target := '/usr/libexec/vinix-x86_64/root' + suffix
	defer { unsafe { target.free() } }
	mut selected := ''
	mut accepted := false
	defer { if !accepted { unsafe { selected.free() } } }
	for path, _ in inputs {
		// V's map iteration clones string keys; selected owns a separate copy.
		defer { unsafe { path.free() } }
		if path.ends_with(target) {
			if path.len > 4096 { return error('Wine layout input path exceeds its bound') }
			if selected != '' { return error('ambiguous Wine layout input: ' + suffix) }
			selected = path.clone()
		}
	}
	if selected == '' { return error('missing Wine layout input: ' + suffix) }
	bytes := layout_bytes(selected)!
	digest := patch_digest(bytes)
	defer { unsafe { bytes.free(); digest.free() } }
	if digest != inputs[selected] {
		return error('Wine layout input digest differs: ' + selected)
	}
	accepted = true
	return selected
}

struct LayoutCopy {
	original string
	consumed string
}

// The explicit musl executable determines Wine's /proc/self/exe directory.
// Keep its ordinary copy beside the native bridges, preserving ../share/wine.
// This admits layout/provenance only; it does not establish native execution.
pub fn admit_private_layout(runtime string, inputs map[string]string) ! {
	if inputs.len == 0 || inputs.len > 100000 { return error('Wine layout input inventory exceeds its bound') }
	runner_path := runtime + '/bin/wine-runner'
	defer { unsafe { runner_path.free() } }
	runner := layout_bytes(runner_path)!
	defer { unsafe { runner.free() } }
	for suffix in ['/bin/wine64', '/bin/wineserver', '/root/usr/bin/wine',
		'/root/usr/bin/wine64', '/root/usr/bin/wineserver']! {
		path := runtime + suffix
		defer { unsafe { path.free() } }
		bytes := layout_bytes(path)!
		defer { unsafe { bytes.free() } }
		if bytes != runner { return error('Wine private bridge differs: ' + suffix) }
	}
	for copy in [
		LayoutCopy{'/lib/ld-musl-x86_64.so.1', '/root/lib/ld-musl-x86_64.so.1'},
		LayoutCopy{'/lib/ld-musl-x86_64.so.1', '/root/usr/bin/vinix-wine-musl'},
		LayoutCopy{'/usr/bin/wine', '/root/usr/libexec/vinix-wine/wine'},
	]! {
		original := layout_input(inputs, copy.original)!
		path := runtime + copy.consumed
		defer { unsafe { original.free(); path.free() } }
		bytes := layout_bytes(path)!
		digest := patch_digest(bytes)
		defer { unsafe { bytes.free(); digest.free() } }
		if digest != inputs[original] {
			return error('Wine private loader/client differs: ' + copy.consumed)
		}
	}
	for part in ['/usr/bin/wineserver', '/usr/lib/wine/x86_64-unix/ntdll.so', '/usr/lib/wine/x86_64-unix/winex11.so', '/usr/lib/wine/x86_64-windows/wineboot.exe', '/usr/lib/wine/x86_64-windows/ntdll.dll', '/usr/lib/wine/x86_64-windows/win32u.dll']! {
		original := layout_input(inputs, part)!
		defer { unsafe { original.free() } }
		bytes := layout_bytes(original)!
		defer { unsafe { bytes.free() } }
		patched := if part.ends_with('winex11.so') { private_graphics_patch(bytes)! }
			else if part.ends_with('wineboot.exe') { private_bootstrap_patch(bytes)! }
			else if part.ends_with('.dll') { private_dispatcher_pe_patch(bytes, part.ends_with('/ntdll.dll'))! }
			else { private_runtime_patch(bytes, part.ends_with('ntdll.so'))! }
		defer { unsafe { patched.free() } }
		path := runtime + '/root' + if part == '/usr/bin/wineserver' {
			'/usr/libexec/vinix-wine/wineserver'
		} else { part }
		defer { unsafe { path.free() } }
		consumed := layout_bytes(path)!
		defer { unsafe { consumed.free() } }
		if patched != consumed {
			return error('Wine binary differs from the exact private-runtime patch: ' + part)
		}
	}
}
