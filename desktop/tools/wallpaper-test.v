// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import os
import wallpaperhost

fn unavailable(url string, path string) ! {
	os.write_file(path, 'failed partial')!
	return error('controlled network failure')
}

fn image_fixture(width int, height int) wallpaperhost.Image {
	mut pixels := []u8{len: width * height * 3}
	for y in 0 .. height {
		for x in 0 .. width {
			pixels[(y * width + x) * 3] = u8(x)
			pixels[(y * width + x) * 3 + 1] = u8(y)
			pixels[(y * width + x) * 3 + 2] = 17
		}
	}
	return wallpaperhost.Image{width, height, pixels}
}

fn run() ! {
	if os.args.len != 3 { return error('expected captures and test directories') }
	guard := cachecli.own_commands()
	defer { guard.close() }
	captures, work := os.args[1], os.args[2]
	assert !os.exists(work)
	os.mkdir_all(work)!
	for original, dimensions in {
		'wide':  [6, 3, 4, 3, 1, 0]
		'tall':  [3, 6, 3, 2, 0, 2]
		'exact': [4, 3, 4, 3, 0, 0]
	} {
		crop := wallpaperhost.crop(image_fixture(dimensions[0], dimensions[1]))!
		assert crop.width == dimensions[2] && crop.height == dimensions[3], original
		assert crop.pixels[..3] == [u8(dimensions[4]), u8(dimensions[5]), 17], original
	}
	for dimensions in [[2, 3, 7, 9], [7, 9, 2, 3], [4, 3, 4, 3]] {
		flat := wallpaperhost.Image{dimensions[0], dimensions[1], []u8{len: dimensions[0] * dimensions[1] * 3, init: u8(83)}}
		resized := wallpaperhost.resize(flat, dimensions[2], dimensions[3])!
		assert resized.width == dimensions[2] && resized.height == dimensions[3] && resized.pixels.all(it == 83)
	}
	empty := work + '/empty'
	cache := empty + '/cache'
	assert wallpaperhost.generate(empty, cache, wallpaperhost.Effects{ download_hook: unavailable })! == 0
	assert os.read_file(empty + '/index.txt')! == ''
	assert os.ls(cache)!.len == 0
	expected_sources := 'Wallpapers from Lorem Picsum (https://picsum.photos), which\nserves photographs from Unsplash under the Unsplash License\n(https://unsplash.com/license).\n\n'
	assert os.read_file(empty + '/SOURCES.txt')! == expected_sources
	partial := work + '/partial'
	cached := partial + '/cache'
	os.mkdir_all(cached)!
	os.cp(captures + '/fixtures/1015.jpg', cached + '/1015.jpg')!
	os.cp(captures + '/fixtures/1018.jpg', cached + '/1018.jpg')!
	os.write_file(cached + '/1016.jpg', 'malformed JPEG cache')!
	os.write_file(partial + '/01.vwp', 'stale wallpaper remains outside index')!
	assert wallpaperhost.generate(partial, cached, wallpaperhost.Effects{ download_hook: unavailable })! == 2
	assert os.read_file(partial + '/index.txt')! == '00.vwp Photo 1\n02.vwp Photo 3\n'
	assert os.read_file(partial + '/SOURCES.txt')! == expected_sources + '00.vwp  https://picsum.photos/id/1015/1024/768\n02.vwp  https://picsum.photos/id/1018/1024/768\n'
	assert os.read_file(partial + '/01.vwp')! == 'stale wallpaper remains outside index'
	assert os.read_file(cached + '/1016.jpg')! == 'malformed JPEG cache'
	assert os.read_bytes(partial + '/00.vwp')! == os.read_bytes(captures + '/fixtures/00.vwp')!
	assert os.read_bytes(partial + '/02.vwp')! == os.read_bytes(captures + '/fixtures/02.vwp')!
	baseline := os.ls('/dev/fd')!.len
	for _ in 0 .. 100 {
		mut failed := false
		wallpaperhost.jpeg(cached + '/1016.jpg') or {
			failed = true
			wallpaperhost.Image{}
		}
		assert failed && os.ls('/dev/fd')!.len == baseline
	}
	os.setenv('NO_PROXY', '127.0.0.1,localhost', true)
	os.setenv('no_proxy', '127.0.0.1,localhost', true)
	wallpaperhost.download('file://' + captures + '/fixtures/1015.jpg', work + '/download.jpg')!
	assert os.read_bytes(work + '/download.jpg')! == os.read_bytes(captures + '/fixtures/1015.jpg')!
	assert !os.exists(work + '/download.jpg.partial')
	os.write_file(work + '/empty-response', '')!
	for path in [work + '/empty-response', work + '/absent-response'] {
		mut refused := false
		wallpaperhost.download('file://' + path, work + '/failed-download') or { refused = true }
		assert refused && !os.exists(work + '/failed-download') && !os.exists(work + '/failed-download.partial')
	}
	os.write_file(work + '/passed', 'PASS\n')!
	println('PASS native crop/Lanczos constants, offline and partial caches, exact indexes/sources, malformed cache retention, partial cleanup and 100 decoder error retirements')
}

fn main() { run() or { panic(err) } }
