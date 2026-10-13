// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import fontnative
import fonthost
import json2
import os

fn run() ! {
	args := cachecli.arguments(os.args[1..], ['--japanese-source', '--output', '--japanese-font-dir',
		'--cache'], [], ['--update-japanese-subsets'], 0, 0,
		'Rasterise Roboto with Chinese and Japanese fallback into V source.\nUsage: genfont [--update-japanese-subsets] [--japanese-source TTF]\n               [--output FILE] [--japanese-font-dir DIR] [--cache DIR]') or { return error_with_code(err.msg(), 2) }
	if '--japanese-source' in args.options && '--update-japanese-subsets' !in args.options {
		return error_with_code('--japanese-source requires --update-japanese-subsets', 2)
	}
	root := os.real_path(os.dir(@FILE) + '/../..')
	desktop := root + '/desktop'
	constants := fonthost.constants()!.as_map()
	mut context := fontnative.context()!
	defer { context.close() }
	previous, pointer := fonthost.set_native_callback(fontnative.callback, unsafe { &context })
	defer { fonthost.set_native_callback(previous, pointer) }
	mut engine := fonthost.Engine{}
	engine.dispatch({
		'operation': json2.Any('generate')
		'arguments': json2.Any({
			'update': json2.Any('--update-japanese-subsets' in args.options)
			'source': json2.Any(args.value('--japanese-source', '').bytes().hex())
		})
		'context':   json2.Any({
			'fonts':            json2.Any((root + '/third_party/ui2/assets/fonts').bytes().hex())
			'desktop':          json2.Any(desktop.bytes().hex())
			'japanese_fonts':   json2.Any(args.value('--japanese-font-dir', desktop + '/fonts').bytes().hex())
			'japanese_catalog': json2.Any((desktop + '/translations/ja.tr').bytes().hex())
			'cache':            json2.Any(args.value('--cache', os.getenv_opt('VINIX_FONT_CACHE') or { os.home_dir() + '/.cache/vinix/fonts' }).bytes().hex())
			'target':           json2.Any(args.value('--output', desktop + '/font_data.v').bytes().hex())
			'cjk_sources':      constants['CJK_SOURCES']!
			'cjk_url':          constants['CJK_URL']!
			'japanese_url':     constants['JAPANESE_FONT_URL']!
			'japanese_sha256':  constants['JAPANESE_FONT_SHA256']!
			'extra_runes':      constants['EXTRA_RUNES']!
			'faces':            constants['FACES']!
			'scales':           constants['RASTER_SCALES']!
		})
	})!
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	run() or {
		eprintln(err)
		exit(if cachecli.cancelled() {
			cachecli.interrupt_status()
		} else if err.code() == 2 {
			2
		} else {
			1
		})
	}
}
