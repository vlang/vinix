// SPDX-License-Identifier: GPL-2.0-or-later
module winesource

import crypto.sha256
import os

pub fn file_digest(path string) !string {
	text := os.read_file(path)!
	defer { unsafe { text.free() } }
	bytes := text.bytes()
	mut hash := sha256.new()
	mut sum := []u8{len: sha256.size}
	defer { unsafe { bytes.free(); sum.free(); hash.free(); free(hash) } }
	hash.write(bytes)!
	hash.checksum_into(mut sum)
	return sum.hex()
}

fn paths(file string) ![]string {
	st := os.lstat(file)!
	if st.get_filetype() != .regular || st.size < 1 || st.size > 8 * 1024 * 1024 {
		return error('compiler source closure must be a bounded ordinary file')
	}
	text := os.read_file(file)!
	defer { unsafe { text.free() } }
	result := text.split_into_lines()
	mut accepted := false
	defer { if !accepted { close(result) } }
	if result.len == 0 || result.len > 100000 { return error('compiler source closure exceeds its bound') }
	for index, line in result {
		if line.len > 4096 || !os.is_abs_path(line) || line.contains('\x00')
			|| line.contains('\r') || !os.is_file(line) {
			return error('invalid compiler source closure path')
		}
		if index > 0 && line <= result[index - 1] {
			return error('compiler source closure is duplicated or unordered')
		}
	}
	accepted = true
	return result
}

fn close(values []string) {
	for value in values { unsafe { value.free() } }
	unsafe { (&array(&values)).free() }
}

// Capture the compiler's discovered source files before the actual build.
pub fn capture(file string, mut inputs map[string]string) ! {
	values := paths(file)!
	defer { close(values) }
	for path in values {
		actual := file_digest(path)!
		defer { unsafe { actual.free() } }
		if path in inputs {
			if inputs[path] != actual { return error('compiler source input changed before build: ' + path) }
			continue
		}
		inputs[path] = actual.clone()
	}
}

// The real build must parse the same closure and preserve every captured hash.
pub fn admit(discovered string, compiled string, inputs map[string]string) ! {
	expected := paths(discovered)!
	defer { close(expected) }
	actual := paths(compiled)!
	defer { close(actual) }
	if expected != actual { return error('compiler source closure changed during build') }
	for path in actual {
		value := file_digest(path)!
		defer { unsafe { value.free() } }
		if path !in inputs || inputs[path] != value { return error('compiler source input is absent or changed: ' + path) }
	}
}
