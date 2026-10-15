// SPDX-License-Identifier: GPL-2.0-or-later
module main

import encoding.base64
import os

// The paragraph builder budgets eight logical pixels per UTF-8 byte. Check
// the native renderer's generated mono metrics at both display scales without
// loading raster coverage. Supplemental glyphs use at least two UTF-8 bytes.
fn check() ! {
	source := os.read_file(os.args[1])!
	defer { unsafe { source.free() } }
	for scale in ['1x', '2x']! {
		marker := 'const face_mono_' + scale + ' = FaceBlob{'
		assert source.contains(marker)
		face := source.all_after(marker).all_before('\n}')
		defer { unsafe { marker.free(); face.free() } }
		mut encoded := ''
		mut ascent := 0
		mut descent := 0
		mut raster_scale := 0
		for line in face.split_into_lines() {
			field := line.trim_space()
			if field.starts_with('metrics:') { encoded = field.all_after(':').trim_space().trim("'") }
			if field.starts_with('ascent:') { ascent = field.all_after(':').trim_space().int() }
			if field.starts_with('descent:') { descent = field.all_after(':').trim_space().int() }
			if field.starts_with('raster_scale:') { raster_scale = field.all_after(':').trim_space().int() }
		}
		assert encoded.len > 0 && ascent + descent <= 18 && raster_scale == scale[..1].int()
		metrics := base64.decode(encoded)
		defer { unsafe { metrics.free() } }
		assert metrics.len > 95 * 5 && metrics.len % 5 == 0
		for index in 0 .. metrics.len / 5 {
			advance := int(metrics[index * 5 + 4]) / raster_scale
			assert advance <= if index < 95 { 8 } else { 16 }, 'paragraph width budget exceeded by mono ${scale} glyph ${index}'
		}
	}
	println('Software paragraph fonts: both native mono scales fit eight logical pixels per UTF-8 byte and eighteen-pixel rows PASS')
}

fn main() { check() or { eprintln(err); exit(1) } }
