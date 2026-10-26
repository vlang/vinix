// SPDX-License-Identifier: GPL-2.0-or-later
// Read a fixed helper from original boot modules without extracting a module.
module main

import crypto.sha256
import json2
import os
import tarstream

struct HelperEntry {
	module_name string
	name        string
	kind        u8
	mode        u32
	size        u64
	linkname    string
	sha256      string
	static_arm64 bool
}

fn le16(data []u8, at int) u16 { return u16(data[at]) | u16(data[at + 1]) << 8 }
fn le32(data []u8, at int) u32 { return u32(le16(data, at)) | u32(le16(data, at + 2)) << 16 }
fn le64(data []u8, at int) u64 { return u64(le32(data, at)) | u64(le32(data, at + 4)) << 32 }

fn static_arm64(data []u8) bool {
	if data.len < 64 || data[..6] != [u8(127), `E`, `L`, `F`, 2, 1]
		|| le16(data, 18) != 183 || le16(data, 16) !in [2, 3] { return false }
	offset := le64(data, 32)
	stride := u64(le16(data, 54))
	count := u64(le16(data, 56))
	if stride < 56 || count == 0 || offset > u64(data.len)
		|| count > (u64(data.len) - offset) / stride { return false }
	mut executable := false
	for index in u64(0) .. count {
		at := int(offset + index * stride)
		if le32(data, at) == 3 { return false }
		if le32(data, at) == 1 && le32(data, at + 4) & 1 != 0 { executable = true }
	}
	return executable
}

fn inspect(image string, module_name string) ![]HelperEntry {
	if module_name.len > 255 || !module_name.ends_with('.tar')
		|| module_name.contains_any('/\\\x00\r\n') { return error('literal module basename required') }
	mut child := os.new_process('/opt/homebrew/bin/mcopy')
	child.set_args(['-i', image, '::/boot/' + module_name, '-'])
	child.set_stdin_path('/dev/null')
	child.set_redirect_stdio()
	child.run()
	defer { child.close() }
	mut completed := false
	defer {
		if !completed {
			child.signal_kill()
			child.wait()
		}
	}
	mut archive := tarstream.from_descriptor(i32(child.stdio_fd[1]))!
	defer { archive.close() }
	mut result := []HelperEntry{}
	for {
		member := archive.next() or {
			if err is tarstream.End { break }
			return err
		}
		if member.name.trim_string_left('./') !in ['usr/bin/xkbcomp', 'lib/ld-musl-aarch64.so.1'] { continue }
		mut data := []u8{}
		if member.regular() {
			if member.size > 16 * 1024 * 1024 { return error('helper exceeds bounded inspection size') }
			mut block := []u8{len: 65536}
			for {
				n := archive.read(mut block)!
				if n == 0 { break }
				data << block[..n]
			}
		}
		result << HelperEntry{module_name, member.name, member.kind, member.mode, member.size,
			member.linkname, if member.regular() { sha256.sum(data).hex() } else { '' },
			static_arm64(data)}
	}
	// Tar may finish before its producer's trailing padding has drained.
	for {
		out := child.stdout_read()
		if !child.is_alive() && out == '' { break }
	}
	child.wait()
	completed = true
	if child.code != 0 { return error('mcopy failed: ' + child.stderr_read()) }
	return result
}

fn main() {
	if os.args.len < 3 {
		eprintln('usage: inspect-helper BOOT_IMG MODULE.tar [MODULE.tar ...]')
		exit(2)
	}
	mut result := []HelperEntry{}
	for module_name in os.args[2..] {
		result << inspect(os.args[1], module_name) or {
			eprintln(err)
			exit(1)
		}
	}
	println(json2.encode(result, prettify: true))
}
