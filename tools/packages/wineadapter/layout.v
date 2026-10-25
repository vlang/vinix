// SPDX-License-Identifier: GPL-2.0-or-later
module wineadapter

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
		n := C.read(fd, unsafe { &bytes[count] }, usize(bytes.len - count))
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
	for part in ['/usr/bin/wineserver', '/usr/lib/wine/x86_64-unix/ntdll.so']! {
		original := layout_input(inputs, part)!
		defer { unsafe { original.free() } }
		bytes := layout_bytes(original)!
		defer { unsafe { bytes.free() } }
		patched := private_server_patch(bytes, part.ends_with('ntdll.so'))!
		defer { unsafe { patched.free() } }
		path := runtime + '/root' + if part == '/usr/bin/wineserver' {
			'/usr/libexec/vinix-wine/wineserver'
		} else { part }
		defer { unsafe { path.free() } }
		consumed := layout_bytes(path)!
		defer { unsafe { consumed.free() } }
		if patched != consumed {
			return error('Wine binary differs from the exact private-server patch: ' + part)
		}
	}
}
