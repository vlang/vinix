// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import slabreport

fn require(ok bool, message string) ! {
	if !ok { return error(message) }
}

// The expected bytes are independent of the production decimal formatter.
fn expected(sizes []u64, live u64, pages u64, large u64, written u64) string {
	mut text := '# class      size    objects   pages\n'
	for size in sizes { text += 'size-${size} ${size} ${live} ${pages}\n' }
	return text + 'large - - ${large}\n# written after free ${written}\n'
}

fn render(buffer voidptr, offset u64, count u64, sizes []u64, live u64,
	pages u64, large u64, written u64) u64 {
	mut output := slabreport.writer(buffer, offset, count)
	output.header()
	for size in sizes { output.class(size, live, pages) }
	output.footer(large, written)
	return output.count()
}

fn controls() ! {
	mut checks := 0
	for sizes in [
		[]u64{},
		[u64(16), 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048],
		[u64(16), 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048, 3072, 4096, 6144, 8192],
		[u64(0), 9, 10, 99, 100, 999, 1000, u64(-1)],
	] {
		for value in [u64(0), 9, 10, 99, 100, 999999999, u64(1) << 63, u64(-1)] {
			live, pages, large, written := value, u64(-1) - value, value / 3, value / 7
			text := expected(sizes, live, pages, large, written)
			for offset in 0 .. text.len + 2 {
				for count in [u64(0), 1, 2, 7, 19, 20, 21, 63, 4096, u64(-1)] {
					mut buffer := []u8{len: text.len + 2, init: 0xa5}
					n := render(unsafe { &buffer[1] }, u64(offset), count,
						sizes, live, pages, large, written)
					left := if offset < text.len { u64(text.len - offset) } else { u64(0) }
					wanted := if count < left { count } else { left }
					require(n == wanted, 'partial read length differs')!
					require(buffer[0] == 0xa5, 'prefix guard changed')!
					for i in 0 .. int(n) {
						require(buffer[i + 1] == text[offset + i], 'partial read bytes differ')!
					}
					for i in int(n) + 1 .. buffer.len {
						require(buffer[i] == 0xa5, 'suffix guard changed')!
					}
					checks++
				}
			}
			for offset in [u64(1) << 63, u64(-2), u64(-1)] {
				require(render(unsafe { nil }, offset, u64(-1), sizes,
					live, pages, large, written) == 0, 'large EOF offset wrapped')!
				checks++
			}
			require(render(unsafe { nil }, 0, 0, sizes, live, pages, large, written) == 0,
				'zero read touched output')!
			checks++
		}
	}
	println('SLABREPORT explicit controls PASS ${checks}')
}

fn main() {
	if os.args.len != 2 || os.args[1] != 'selftest' {
		eprintln('usage: slabinfo-check selftest')
		exit(2)
	}
	controls() or { eprintln(err); exit(1) }
}
