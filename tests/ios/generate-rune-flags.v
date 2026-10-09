// SPDX-License-Identifier: GPL-2.0-or-later
// Observe character-classification facts from the installed Mac library.
// No native library code or file is copied to the guest or repository.
module main

import os
import strings

#include <ctype.h>
#include <locale.h>
fn C.__maskrune(i32, u64) i32
fn C.setlocale(i32, &char) &char

fn main() {
	if os.args.len != 2 { panic('usage: generate-rune-flags OUTPUT.v') }
	mut output := strings.new_builder(180000)
	output.writeln('// SPDX-License-Identifier: GPL-2.0-or-later')
	output.writeln('// Generated character-classification facts. Regenerate on macOS with')
	output.writeln('// v run tests/ios/generate-rune-flags.v compat/ios/runner/rune_flags.v')
	output.writeln('module main\n')
	for name, locale in {'c': 'C', 'utf8': 'en_US.UTF-8'} {
		if C.setlocale(C.LC_CTYPE, locale.str) == unsafe { nil } {
			panic('native reference locale is unavailable: ${locale}')
		}
		output.writeln('const darwin_rune_${name}_ranges = [')
		mut previous := u32(C.__maskrune(0, 0xffffffff))
		mut digest := (u64(14695981039346656037) ^ previous) * 1099511628211
		mut count := 0
		for point in 1 .. 0x110000 {
			flags := u32(C.__maskrune(i32(point), 0xffffffff))
			digest = (digest ^ flags) * 1099511628211
			if flags != previous {
				output.writeln('\tDarwinRuneRange{0x${u32(point - 1):06x}, 0x${previous:08x}},')
				count++
				previous = flags
			}
		}
		output.writeln('\tDarwinRuneRange{0x10ffff, 0x${previous:08x}},')
		output.writeln(']!\n')
		println('${locale}: ${count + 1} ranges, FNV64 ${digest:016x}')
	}
	os.write_file(os.args[1], output.str())!
}
