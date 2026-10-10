// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module hwhost

import os

fn pixmap(header string, pixels []u8) []u8 {
	mut data := header.bytes()
	data << pixels
	return data
}

fn test_a_black_picture_is_dark_and_a_console_is_not() {
	black := read_picture(pixmap('P6\n4 2\n255\n', []u8{len: 24}))!
	assert black.width == 4
	assert black.height == 2
	assert black.lit == 0
	assert judge_picture(black, true) == ''
	assert judge_picture(black, false).contains('was to show something')

	mut pixels := []u8{len: 24}
	pixels[5] = 1 // the blue of the second pixel, barely
	pixels[21] = 255
	one := read_picture(pixmap('P6\n4 2\n255\n', pixels))!
	assert one.lit == 2
	assert judge_picture(one, true).contains('2 of 8 pixels are lit')
	assert judge_picture(one, false) == ''
}

fn test_a_few_stray_pixels_are_not_a_picture() {
	// One pixel in a 100 by 100 frame is under one in a thousand.
	mut pixels := []u8{len: 100 * 100 * 3}
	pixels[300] = 9
	speck := read_picture(pixmap('P6\n100 100\n255\n', pixels))!
	assert speck.lit == 1
	assert judge_picture(speck, false) != ''
	assert judge_picture(speck, true) != ''
	for i in 0 .. 10 {
		pixels[3000 + i * 3] = 200
	}
	text := read_picture(pixmap('P6\n100 100\n255\n', pixels))!
	assert text.lit == 11
	assert judge_picture(text, false) == ''
}

fn test_the_header_is_read_as_pixmaps_are_written() {
	// Comments, and any white space between the numbers.
	commented := read_picture(pixmap('P6\n# made by QEMU\n2\t1 # wide\n255\n', [u8(0), 0, 0, 7, 7, 7]))!
	assert commented.width == 2
	assert commented.lit == 1
	// A pixel byte that looks like white space is still a pixel: only one
	// byte ends the header.
	spaces := read_picture(pixmap('P6 1 1 255 ', [u8(32), 10, 9]))!
	assert spaces.lit == 1
}

fn test_what_is_not_a_picture_is_refused() {
	read_picture('P5\n1 1\n255\n\x00'.bytes()) or { assert err.msg() == 'not a binary pixmap' }
	read_picture([]u8{}) or { assert err.msg() == 'not a binary pixmap' }
	if _ := read_picture(pixmap('P6\n2 2\n255\n', []u8{len: 11})) {
		assert false, 'a picture one byte short was accepted'
	}
	if _ := read_picture('P6\n0 4\n255\n'.bytes()) {
		assert false, 'a picture with no width was accepted'
	}
	if _ := read_picture(pixmap('P6\n1 1\n65535\n', []u8{len: 6})) {
		assert false, 'a deep pixmap was accepted'
	}
	if _ := read_picture('P6\nwide 1\n255\n'.bytes()) {
		assert false, 'a header with a word in it was accepted'
	}
	if _ := read_picture('P6\n99999999999 1\n255\n'.bytes()) {
		assert false, 'an absurd width was accepted'
	}
}

fn test_a_picture_is_judged_from_its_file() {
	state := os.join_path(os.temp_dir(), 'vinix-hwtest-screen-${os.getpid()}')
	os.mkdir_all(state)!
	defer {
		os.rmdir_all(state) or {}
	}
	os.write_file_array(os.join_path(state, 'dark.ppm'), pixmap('P6\n2 2\n255\n', []u8{len: 12}))!
	check_screen(Screen{ file: 'dark.ppm', dark: true }, state)!
	check_screen(Screen{ file: 'dark.ppm' }, state) or {
		assert err.msg().starts_with('dark.ppm: 0 of 4 pixels are lit')
	}
	check_screen(Screen{ file: 'never-taken.ppm', dark: true }, state) or {
		assert err.msg() == 'never-taken.ppm: the picture was not taken'
		return
	}
	assert false, 'a picture that was never taken passed'
}
