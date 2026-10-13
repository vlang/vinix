// SPDX-License-Identifier: GPL-2.0-or-later
module main

import fontnative
import fonthost
import math
import os

fn check_face(lib &fontnative.Library, root string, face fontnative.BakedFace, chinese []int) !int {
	filename := if face.mono {
		'RobotoMono-Regular.ttf'
	} else if face.bold {
		'Roboto-Bold.ttf'
	} else {
		'Roboto-Regular.ttf'
	}
	mut primary := lib.open(root + '/third_party/ui2/assets/fonts/' + filename, face.size * face.scale)!
	defer { primary.close() }
	mut cjk := lib.open(os.home_dir() + '/.cache/vinix/fonts/noto-cjk-2.004/NotoSansCJKsc-' + if face.bold {
		'Bold.otf'
	} else {
		'Regular.otf'
	}, face.size * face.scale)!
	defer { cjk.close() }
	mut japanese := lib.open(root + '/desktop/fonts/VinixJapanese-' + if face.bold {
		'Bold.ttf'
	} else {
		'Regular.ttf'
	}, face.size * face.scale)!
	defer { japanese.close() }
	missing := primary.raster(0xe000)!
	mut checked := 0
	for point, baked in face.glyphs {
		mut real := primary.raster(point)!
		if point in chinese && ((point >= 0x3000 && point <= 0x303f) || (point >= 0x3400 && point <= 0x9fff) || (point >= 0xff00 && point <= 0xffef)) {
			real = cjk.raster(point)!
		} else if point > 126 && real == missing {
			real = japanese.raster(point)!
		}
		if real.height == 0 || real.width == 0 {
			assert baked.width == 0 && baked.height == 0 && baked.pixels.len == 0, face.name + ' U+' + point.hex()
		} else {
			if real.width != baked.width || real.height != baked.height || real.pixels != baked.pixels {
				eprintln('actual ' + real.width.str() + 'x' + real.height.str() + ' at ' + real.bx.str() + '/' + real.by.str() + ', advance64=' + real.advance64.str())
				eprintln('baked ' + baked.width.str() + 'x' + baked.height.str() + ' at ' + baked.bx.str() + '/' + baked.by.str() + ', advance=' + baked.advance.str())
				eprintln('actual mask ' + real.pixels[..math.min(real.pixels.len, 128)].hex())
				eprintln('baked mask ' + baked.pixels[..math.min(baked.pixels.len, 128)].hex())
			}
			assert real.width == baked.width && real.height == baked.height && real.pixels == baked.pixels, face.name + ' U+' + point.hex()
		}
		checked++
	}
	println('PASS native source masks ' + face.name + ' / ' + checked.str())
	return checked
}

fn run() ! {
	root := os.real_path(os.dir(@FILE) + '/../..')
	path := if os.args.len == 2 { os.args[1] } else { root + '/desktop/font_data.v' }
	atlas := fontnative.atlas(path)!
	mut chinese := fonthost.catalog_runes([root + '/desktop/translations/zh.tr'])!
	for point in '中文（简体）'.runes() {
		if int(point) !in chinese { chinese << int(point) }
	}
	mut lib := fontnative.library()!
	defer { lib.close() }
	mut count := 0
	for name in atlas.faces.keys().sorted() {
		count += check_face(&lib, root, atlas.faces[name], chinese)!
	}
	println('PASS ' + count.str() + ' independent baked source glyph comparisons')
}

fn main() { run() or { panic(err) } }
