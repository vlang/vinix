// SPDX-License-Identifier: GPL-2.0-or-later
// Derive fresh successor tooling without changing retained369 evidence.
module main

import os

fn replace_once(source string, before string, after string) string {
	assert source.count(before) == 1, before
	return source.replace_once(before, after)
}

fn main() {
	assert os.args.len == 1
	dir := os.dir(@FILE)
	for name in ['run-recorder', 'action-recorder', 'action-recorder-build'] {
		from := dir + '/intent-uri369-' + name + '.v'
		to := dir + '/intent-uri371-' + name + '.v'
		assert !os.exists(to) && !os.is_link(to)
		mut source := os.read_file(from)!.replace('369', '371')
		if name == 'run-recorder' {
			source = replace_once(source, "const root = state + '/intent-uri371-run-bootstrap-build-b-2026-10-26'", "const root = state + '/intent-uri371-run-bootstrap-build-2026-10-26'")
			source = replace_once(source, '// The sealed first bootstrap retains the complete qualified367 readback and\n// frozen compiler. Reuse that audited input after the ordering correction.', '// Retain the corrected369 bootstrap compiler and its qualified367 receipt.\n// The successor harness reuses the original old control without a guest boot.')
			source = replace_once(source, "const baseline = state + '/intent-uri371-run-bootstrap-build-2026-10-26'", "const baseline = state + '/intent-uri369-run-bootstrap-build-b-2026-10-26'")
			source = replace_once(source, "const baseline_pin = 'f3aeac7aa1ff66543a1afd520c1cd2363982fe9250c6dfb475e5c3e1e1c8873a'", "const baseline_pin = '0de15d5f6e3f96dabba630779e3b17e34c8c50fff33ddd8a705d8a14191b591a'")
			source = source.replace("baseline + '/baseline-receipt.json'", "baseline + '/framework367-receipt.json'")
			source = replace_once(source, "source := vroot + '/source/intent-uri371-run-corrected.v'", "source := vroot + '/source/intent-uri371-run.v'")
			source = replace_once(source, 'assert pins.len > 0', 'assert pins.len == 270')
			source = replace_once(source, "\tcompiler := vroot + '/v'", "\tos.cp(os.executable(), root + '/recorder')!\n\tcompiler := vroot + '/v'")
			source = replace_once(source, "'binary_sha256': json2.Any(hash(output)!), 'compiler_sha256': json2.Any(compiler_pin),", "'binary_sha256': json2.Any(hash(output)!), 'compiler_sha256': json2.Any(compiler_pin),\n\t\t'recorder_source_sha256': json2.Any(hash(root + '/recorder.v')!),\n\t\t'recorder_binary_sha256': json2.Any(hash(root + '/recorder')!),")
		} else if name == 'action-recorder' {
			source = replace_once(source, "['prepare', 'old', 'new', 'qualify', 'seal']", "['prepare', 'new', 'qualify', 'seal']")
		} else {
			source = replace_once(source, "const baseline = state + '/intent-uri371-run-bootstrap-build-b-2026-10-26'", "const baseline = state + '/intent-uri371-run-bootstrap-build-2026-10-26'")
			source = replace_once(source, 'assert os.args.len == 1 && !os.exists(root) && !os.is_link(root)', 'assert os.args.len == 2 && !os.exists(root) && !os.is_link(root)\n\tmanifest_pin := os.args[1]\n\tassert manifest_pin.len == 64 && manifest_pin.bytes().all(it in \'0123456789abcdef\'.bytes())')
			source = replace_once(source, "assert hash(baseline + '/sha256.json')! == '0de15d5f6e3f96dabba630779e3b17e34c8c50fff33ddd8a705d8a14191b591a'", "assert hash(baseline + '/sha256.json')! == manifest_pin")
		}
		os.write_file(to, source)!
		println(to)
	}
}
