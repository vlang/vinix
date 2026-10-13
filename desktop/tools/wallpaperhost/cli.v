// SPDX-License-Identifier: GPL-2.0-or-later
module wallpaperhost

import cachecli
import os
import sourcecommand

pub const picsum_ids = [1015, 1016, 1018, 1019, 1024, 1036, 1039, 1043, 1047, 1057]

pub fn source_url(id int) string { return 'https://picsum.photos/id/' + id.str() + '/1024/768' }

pub struct Effects {
pub:
	download_hook fn (string, string) ! = unsafe { nil }
	convert_hook  fn (string, string) ! = unsafe { nil }
}

fn (effects Effects) fetch(url string, target string) ! {
	if effects.download_hook != unsafe { nil } {
		effects.download_hook(url, target)!
	} else {
		download(url, target)!
	}
}

fn (effects Effects) raster(source string, target string) ! {
	if effects.convert_hook != unsafe { nil } {
		effects.convert_hook(source, target)!
	} else {
		convert(source, target)!
	}
}

pub fn download(url string, destination string) ! {
	temporary := destination + '.partial'
	defer { if os.exists(temporary) { os.rm(temporary) or {} } }
	mut flags := []string{}
	for attempt in 0 .. 2 {
		cachecli.checkpoint()!
		result := sourcecommand.capture_full(['curl', '--fail', '--location', '--silent', '--show-error',
			'--connect-timeout', '30', '--speed-limit', '1', '--speed-time', '30', '--user-agent',
			'vinix-desktop/1', ...flags, '--output', temporary, url], os.environ(), -1, 1024 * 1024, cachecli.cancelled)!
		if result.status == 0 {
			if os.file_size(temporary) == 0 { return error('empty response') }
			if C.rename(temporary.str, destination.str) != 0 { return os.error_posix() }
			return
		}
		if attempt == 1 { return error(result.stderr.trim_space()) }
		flags = ['--insecure']
	}
}

pub fn generate(output string, cache string, effects Effects) !int {
	os.mkdir_all(output)!
	os.mkdir_all(cache)!
	mut written := []int{}
	for slot, id in picsum_ids {
		cachecli.checkpoint()!
		cached := cache + '/' + id.str() + '.jpg'
		if !os.exists(cached) || os.file_size(cached) == 0 {
			url := source_url(id)
			effects.fetch(url, cached) or {
				if cachecli.cancelled() { return err }
				println('    SKIPPED id ' + id.str() + ': ' + err.msg())
				if os.exists(cached) { os.rm(cached)! }
				continue
			}
			println('    downloaded ' + url)
		}
		destination := output + '/0' + slot.str() + '.vwp'
		effects.raster(cached, destination) or {
			if cachecli.cancelled() { return err }
			println('    SKIPPED id ' + id.str() + ': cannot convert: ' + err.msg())
			continue
		}
		written << slot
	}
	mut index := ''
	mut sources := 'Wallpapers from Lorem Picsum (https://picsum.photos), which\nserves photographs from Unsplash under the Unsplash License\n(https://unsplash.com/license).\n\n'
	for slot in written {
		name := '0' + slot.str() + '.vwp'
		index += name + ' Photo ' + (slot + 1).str() + '\n'
		sources += name + '  ' + source_url(picsum_ids[slot]) + '\n'
	}
	os.write_file(output + '/index.txt', index)!
	os.write_file(output + '/SOURCES.txt', sources)!
	println('    ' + written.len.str() + ' wallpaper(s) in ' + output)
	if written.len == 0 {
		println('    (no network and no cache: the desktop will offer colours only)')
	}
	return written.len
}

pub fn cli(argv []string) !int {
	args := cachecli.arguments(argv, ['--cache'], [], [], 1, 1, 'Download and convert desktop wallpaper photographs.\nUsage: fetch_wallpapers OUTPUT_DIR [--cache DIR]') or { return error_with_code(err.msg(), 2) }
	output := args.positional[0]
	cache := args.value('--cache', '')
	generate(output, if cache == '' { output + '/.cache' } else { cache }, Effects{})!
	return 0
}
