// SPDX-License-Identifier: GPL-2.0-or-later
module main

import fontnative
import os

fn run() ! {
	if os.args.len != 3 { return error('expected two font atlas source files') }
	expected, actual := fontnative.atlas(os.args[1])!, fontnative.atlas(os.args[2])!
	assert expected.extras == actual.extras && expected.faces.keys().sorted() == actual.faces.keys().sorted()
	mut masks, headers, count := 0, 0, 0
	for name in expected.faces.keys().sorted() {
		a, b := expected.faces[name], actual.faces[name]
		assert a.size == b.size && a.scale == b.scale && a.ascent == b.ascent && a.descent == b.descent && a.bold == b.bold && a.mono == b.mono, name
		for point, glyph in a.glyphs {
			other := b.glyphs[point] or { return error('missing glyph') }
			if glyph.pixels != other.pixels {
				if masks < 12 { eprintln('mask mismatch ' + name + ' U+' + point.hex()) }
				masks++
			}
			if glyph.width != other.width || glyph.height != other.height || glyph.bx != other.bx || glyph.by != other.by || glyph.advance != other.advance {
				if headers < 12 { eprintln('header mismatch ' + name + ' U+' + point.hex()) }
				headers++
			}
			count++
		}
	}
	println(count.str() + ' glyphs / mask mismatches=' + masks.str() + ' / header mismatches=' + headers.str())
	assert masks == 0 && headers == 0
}

fn main() { run() or { panic(err) } }
