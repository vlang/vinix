// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import surfacecore
import time

fn run() ! {
	if os.args[1..] == ['--help'] {
		println('surface-probe colors|colors-with-size|damage|crc|obs-paint|obs-capture PATH')
		return
	}
	if os.args.len != 3 { return error('expected surface operation and path') }
	operation, path := os.args[1], os.args[2]
	if operation == 'obs-capture' {
		surfacecore.obs_capture(path, os.getenv_opt('VINIX_SURFACE_XLIB') or { 'libX11.so.6' }, ':99')!
		return
	}
	if operation == 'damage' {
		value := surfacecore.damage(path) or {
			println('-1')
			return
		}
		println(value)
		return
	}
	if operation == 'crc' {
		value := surfacecore.sampled_crc(path) or {
			println('-1')
			return
		}
		println(value)
		return
	}
	if operation !in ['colors', 'colors-with-size', 'obs-paint'] {
		return error('unknown surface operation')
	}
	mut mapping := surfacecore.map_file(path, false)!
	defer { mapping.close() }
	if operation == 'obs-paint' {
		mapping.wait_for_paint(45 * time.second)!
		return
	}
	count := mapping.colors()!
	if operation == 'colors-with-size' {
		println('${mapping.length} ${count}')
	} else {
		println(count)
	}
}

fn main() {
	run() or {
		eprintln(err)
		exit(1)
	}
}
