// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import fontnative
import fonthost
import json2
import os

fn run() ! {
	args := cachecli.arguments(os.args[1..], ['--atlas', '--japanese-font-dir', '--cache'], [], [], 0, 0,
		'Check actual baked font masks, coverage, line bounds and scale metrics.\nUsage: test_font_data [--atlas FILE] [--japanese-font-dir DIR] [--cache DIR]')!
	root := os.real_path(os.dir(@FILE) + '/../../..')
	desktop := root + '/desktop'
	atlas := fontnative.atlas(args.value('--atlas', desktop + '/font_data.v'))!
	constants := fonthost.constants()!.as_map()
	mut ctx := fontnative.context()!
	defer { ctx.close() }
	previous, pointer := fonthost.set_native_callback(fontnative.callback, unsafe { &ctx })
	defer { fonthost.set_native_callback(previous, pointer) }
	context := {
		'fonts':            json2.Any((root + '/third_party/ui2/assets/fonts').bytes().hex())
		'desktop':          json2.Any(desktop.bytes().hex())
		'japanese_fonts':   json2.Any(args.value('--japanese-font-dir', desktop + '/fonts').bytes().hex())
		'japanese_catalog': json2.Any((desktop + '/translations/ja.tr').bytes().hex())
		'cache':            json2.Any(args.value('--cache', os.getenv_opt('VINIX_FONT_CACHE') or { os.home_dir() + '/.cache/vinix/fonts' }).bytes().hex())
		'cjk_sources':      constants['CJK_SOURCES']!
		'cjk_url':          constants['CJK_URL']!
		'extra_runes':      constants['EXTRA_RUNES']!
		'faces':            constants['FACES']!
		'scales':           constants['RASTER_SCALES']!
	}
	mut engine := fonthost.Engine{}
	translations := engine.dispatch({
		'operation': json2.Any('translations')
		'arguments': json2.Any(map[string]json2.Any{})
		'context':   json2.Any(context)
	})!.as_array().map(it.int())
	chinese := engine.dispatch({
		'operation': json2.Any('chinese')
		'arguments': json2.Any(map[string]json2.Any{})
		'context':   json2.Any(context)
	})!.as_array().map(it.int())
	japanese := engine.dispatch({
		'operation': json2.Any('japanese')
		'arguments': json2.Any(map[string]json2.Any{})
		'context':   json2.Any(context)
	})!.as_array().map(it.int())
	assert atlas.extras == atlas.extras.sorted()
	for index in 1 .. atlas.extras.len {
		assert atlas.extras[index - 1] < atlas.extras[index]
	}
	japanese_only := japanese.filter(it !in chinese)
	assert translations.all(it in atlas.extras) && int(`の`) in japanese_only
	mut expected := []string{}
	for row in constants['FACES']!.as_array() {
		for scale in constants['RASTER_SCALES']!.as_array() {
			expected << row.as_array()[0].str() + '_' + scale.int().str() + 'x'
		}
	}
	assert atlas.faces.keys().sorted() == expected.sorted()
	mut checked := 0
	for row in constants['FACES']!.as_array() {
		definition := row.as_array()
		name, file, size, bold := definition[0].str(), definition[1].str(), definition[2].int(), definition[3].bool()
		logical := engine.dispatch({
			'operation': json2.Any('open')
			'arguments': json2.Any({
				'file': json2.Any(file)
				'size': json2.Any(size)
			})
			'context':   json2.Any(context)
		})!.int()
		metrics := fontnative.callback('metrics', {
			'font': json2.Any(logical)
		}, unsafe { &ctx })!.as_array().map(it.int())
		for scale in constants['RASTER_SCALES']!.as_array().map(it.int()) {
			face := atlas.faces[name + '_' + scale.str() + 'x']
			assert face.ascent == metrics[0] && face.descent == metrics[1]
			for point, glyph in face.glyphs {
				if scale == 2 {
					assert atlas.faces[name + '_1x'].glyphs[point].advance * 2 == glyph.advance
				}
				is_chinese := point in chinese && ((point >= 0x3000 && point <= 0x303f) || (point >= 0x3400 && point <= 0x9fff) || (point >= 0xff00 && point <= 0xffef))
				if !is_chinese && point !in japanese_only { continue }
				id := engine.dispatch({
					'operation': json2.Any('glyph_font')
					'arguments': json2.Any({
						'file':       json2.Any(file)
						'size':       json2.Any(size * scale)
						'bold':       json2.Any(bold)
						'code_point': json2.Any(point)
						'japanese':   json2.Null{}
					})
					'context':   json2.Any(context)
				})!.int()
				real := engine.dispatch({
					'operation': json2.Any('raster')
					'arguments': json2.Any({
						'font':       json2.Any(id)
						'code_point': json2.Any(point)
					})
					'context':   json2.Any(context)
				})!.as_array()
				missing := engine.dispatch({
					'operation': json2.Any('missing')
					'arguments': json2.Any({
						'font': json2.Any(id)
					})
					'context':   json2.Any(context)
				})!.as_array()
				assert real != missing && glyph.pixels.hex() == real[5].str(), name + ' U+' + point.hex()
				assert glyph.pixels.any(it != 0) && glyph.advance > 0 && glyph.by + glyph.height <= (face.ascent + face.descent) * scale
				if name == 'mono' && is_chinese {
					assert glyph.advance == 2 * face.glyphs[int(`M`)].advance
				}
				if !is_chinese {
					primary := engine.dispatch({
						'operation': json2.Any('open')
						'arguments': json2.Any({
							'file': json2.Any(file)
							'size': json2.Any(size * scale)
						})
						'context':   json2.Any(context)
					})!.int()
					if id != primary {
						fallback := engine.dispatch({
							'operation': json2.Any('open_japanese')
							'arguments': json2.Any({
								'bold': json2.Any(bold)
								'size': json2.Any(size * scale)
							})
							'context':   json2.Any(context)
						})!.int()
						assert id == fallback
						if name == 'mono' {
							assert glyph.advance == 2 * face.glyphs[int(`M`)].advance
						}
					}
				}
				checked++
			}
		}
	}
	for scale in [1, 2] {
		regular, bold := atlas.faces['ui_' + scale.str() + 'x'], atlas.faces['bold_' + scale.str() + 'x']
		assert regular.glyphs[int(`中`)].pixels != regular.glyphs[int(`文`)].pixels && regular.glyphs[int(`中`)].pixels != bold.glyphs[int(`中`)].pixels
	}
	println('PASS original catalog coverage, native masks/notdef/identity, line boxes, logical advances, terminal columns and distinct weights / ' + checked.str() + ' source masks')
	if path := os.getenv_opt('VINIX_FONT_PREVIEW') { fontnative.preview(atlas, path)! }
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	run() or {
		eprintln(err)
		exit(1)
	}
}
