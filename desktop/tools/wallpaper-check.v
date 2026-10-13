// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import wallpaperhost

fn main() { run() or { panic(err) } }

fn run() ! {
	if os.args.len != 3 { return error('expected captures and output directories') }
	base, work := os.args[1], os.args[2]
	os.mkdir_all(work)!
	captures := json2.decode[json2.Any](os.read_file(base + '/captures.json')!)!.as_array()
	for capture in captures {
		row := capture.as_map()
		id := row['id']!.int()
		slot := row['slot']!.int()
		name := '0' + slot.str() + '.vwp'
		source := base + '/fixtures/' + id.str() + '.jpg'
		assert sha256.sum(os.read_bytes(source)!).hex() == row['input_sha256']!.str()
		target := work + '/' + name
		wallpaperhost.convert(source, target)!
		actual := os.read_bytes(target)!
		expected := os.read_bytes(base + '/fixtures/' + name)!
		assert sha256.sum(expected).hex() == row['output_sha256']!.str()
		mut different := 0
		for index, value in actual {
			if index >= expected.len || value != expected[index] { different++ }
		}
		println(id.str() + ' bytes=' + actual.len.str() + ' different=' + different.str())
		assert actual == expected, 'wallpaper ' + id.str() + ' does not match its frozen RGB capture'
	}
	os.write_file(work + '/passed', 'PASS\n')!
}
