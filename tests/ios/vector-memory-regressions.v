// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import crypto.sha256

// Focused controls for the vector-memory profile expansion. Original checkers
// keep their full entry points. Generated copies replace only main: dedicated
// control suites run in full; inline controls use an i32 batch (six widths for
// the constant-extraction checker, which asserts its complete batch size).
// Usage: v run this_file V_COMPILER LLVM_AS FRESH_EXTERNAL_DIR
fn checked(args []string, log string) ! {
	r := os.exec(args)
	os.write_file(log + '.command.txt', args.map(os.quoted_path(it)).join(' ') + '\n')!
	os.write_file(log + '.log', r.output)!
	os.write_file(log + '.status.txt', r.exit_code.str() + '\n')!
	assert r.exit_code == 0 && !r.output.contains('runtime error:') && !r.output.contains('ERROR: AddressSanitizer'), r.output
}

fn main() {
	assert os.args.len == 4
	root := os.abs_path(os.args[3])
	assert !os.exists(root) && !root.starts_with(os.getwd() + '/')
	os.mkdir_all(root)!
	files := ['air-constant-extract', 'air-vector-binary', 'air-vector-bitcast', 'air-vector-compare',
		'air-vector-float-binary', 'air-vector-float-int', 'air-vector-fma', 'air-vector-fmuladd',
		'air-vector-fneg', 'air-vector-fpclass', 'air-vector-freeze', 'air-vector-int-float',
		'air-vector-integer-cast', 'air-vector-lane-select', 'air-vector-ldexp',
		'air-vector-minmax-intrinsics', 'air-vector-number-minmax-intrinsics', 'air-vector-precision',
		'air-vector-round-intrinsics', 'air-vector-select', 'air-vector-shuffle',
		'air-vector-sign-intrinsics', 'air-vector-sqrt-intrinsics']
	for name in files {
		original := os.read_file('tests/ios/' + name + '.v')!
		assert original.contains('load volatile <')
		start := original.index('fn main() {') or { panic(name) }
		tail := original[start..]
		end := if i := tail.index('\nfn ') { start + i } else { original.len }
		mut body := ''
		for call in ['controls', 'focused_controls', 'attribute_controls', 'lane_controls'] {
			if original.contains('fn ' + call + '(') {
				body += '${call}(os.args[1], os.args[2] + "/${call}")!\n'
			}
		}
		if body.len == 0 {
			body = if name == 'air-constant-extract' {
				'run_batch(os.args[1], os.args[2] + "/batch", 30, 36)!\n'
			} else {
				'run_batch(os.args[1], os.args[2] + "/batch", 31)!\n'
			}
		}
		dir := root + '/' + name
		os.mkdir_all(dir)!
		os.write_file(dir + '/original.v', original)!
		os.write_file(dir + '/source.sha256', sha256.sum(original.bytes()).hex() + '\n')!
		generated := original[..start] + original[end..] + '\nfn main() {\n' + body + '\n}\n'
		os.write_file(dir + '/focused.v', generated)!
		checked([os.args[1], '-nocache', '-gc', 'none', '-cflags',
			'-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags',
			'-fsanitize=address,undefined', '-path', '@vlib|' + os.getwd() + '/compat/ios|@vmodules',
			'-o', dir + '/focused', dir + '/focused.v'], dir + '/build')!
		checked([dir + '/focused', os.args[2], dir + '/results'], dir + '/run')!
		assert os.read_file('tests/ios/' + name + '.v')! == original
		println(name + ': focused controls PASS')
	}
	os.write_file(root + '/result.txt', 'VECTOR-MEMORY-REGRESSIONS: 23 focused legacy suites PASS; full historical matrices not rerun\n')!
}
