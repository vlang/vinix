// SPDX-License-Identifier: GPL-2.0-or-later
// Inventory fixed dispatcher references; semantic analysis, not qualification.
module main

import crypto.sha256
import json2
import os

struct Reference { offset int kind string context string value u32 }
struct Image { path string sha256 string references []Reference }
struct Inventory { source_sha256 string executable_sha256 string inputs map[string]string images []Image }

fn run() ! {
	if os.args.len != 3 || os.exists(os.args[2]) { return error('usage: wine-dispatcher-sites DISTRIBUTION_ROOT FRESH_JSON') }
	if sha256.hexhash(os.read_file(@FILE)!) != sha256.hexhash($embed_file('wine-dispatcher-sites.v').to_string()) { return error('compiled dispatcher analyzer source differs') }
	mut files := os.walk_ext(os.args[1] + '/usr/lib/wine/x86_64-windows', '', hidden: true)
	files.sort()
	mut images := []Image{}
	mut inputs := map[string]string{}
	for path in files {
		if !os.is_file(path) { continue }
		data := os.read_file(path)!
		defer { unsafe { data.free() } }
		inputs[path] = sha256.hexhash(data)
		mut refs := []Reference{}
		for at in 0 .. data.len - 3 {
			if data[at + 1] & 0xf0 != 0x10 || data[at + 2] != 0xfe || data[at + 3] != 0x7f { continue }
			kind := if at >= 3 && data[at - 3..at] == '\xff\x14\x25' { 'call' } else { 'other' }
			start := if at >= 6 { at - 6 } else { 0 }
			end := if at + 10 < data.len { at + 10 } else { data.len }
			value := u32(data[at]) | (u32(data[at + 1]) << 8) | u32(0x7ffe0000)
			refs << Reference{at, kind, data[start..end].bytes().hex(), value}
		}
		if refs.len > 0 {
			println(os.base(path) + ' references=' + refs.len.str())
			for item in refs { if item.kind == 'other' { println('  other ' + item.offset.str() + ' ' + item.context) } }
			images << Image{path, sha256.hexhash(data), refs}
		}
	}
	for path, expected in inputs { if sha256.hexhash(os.read_file(path)!) != expected { return error('dispatcher input changed during scan') } }
	os.write_file(os.args[2], json2.encode(Inventory{sha256.hexhash(os.read_file(@FILE)!), sha256.hexhash(os.read_file(os.executable())!), inputs, images}))!
}

fn main() { run() or { eprintln(err); exit(1) } }
