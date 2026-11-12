// SPDX-License-Identifier: GPL-2.0-or-later
// Render captured frame bytes for inspection, including failed runs. This
// does not inspect outcome, producer provenance or package admission.
module main

import crypto.sha256
import json2
import os
import stbi
import tests.packages.winegui
import tests.packages.winesource

struct Captures {
	scope string = 'captured RGB decoding for visual inspection only; no GUI launch or package qualification'
	serial string
	serial_sha256 string
	producer_sha256 string
	source_sha256 string
	images map[string]string
}

fn run() ! {
	if os.args.len != 3 { return error('usage: wine-gui-captures SERIAL_LOG FRESH_OUTPUT') }
	for path, source in { @FILE: $embed_file('wine-gui-captures.v').to_string(),
		os.dir(@FILE) + '/winegui/frame.v': $embed_file('winegui/frame.v').to_string() } {
		if winesource.file_digest(path)! != sha256.hexhash(source) { return error('compiled frame decoder source differs') }
	}
	serial := os.real_path(os.args[1]); out := os.abs_path(os.args[2])
	if os.exists(out) || os.is_link(out) { return error('capture output must be fresh') }
	before := winesource.file_digest(serial)!
	mut frames := []winegui.Frame{}
	for line in os.read_file(serial)!.split_into_lines() {
		if line.trim_space().starts_with('WINE GUI FRAME ') { frames << winegui.decode_frame(line.trim_space())! }
	}
	if frames.len != 2 || frames[0].name != 'before' || frames[1].name != 'after' { return error('requires exactly before/after frame records') }
	os.mkdir_all(out)!
	mut images := map[string]string{}
	for frame in frames {
		path := out + '/' + frame.name + '.png'
		stbi.stbi_write_png(path, frame.width, frame.height, 3, frame.rgb.data, frame.width * 3)!
		images[frame.name + '.png'] = winesource.file_digest(path)!
	}
	if winesource.file_digest(serial)! != before { return error('serial log changed during extraction') }
	os.write_file(out + '/captures.json', json2.encode(Captures{serial: serial, serial_sha256: before,
		producer_sha256: winesource.file_digest(os.executable())!, source_sha256: winesource.file_digest(@FILE)!, images: images}))!
	println('WINE GUI CAPTURES decoded for inspection only; no launch qualification')
}

fn main() { run() or { eprintln(err); exit(1) } }
