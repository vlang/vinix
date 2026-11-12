// SPDX-License-Identifier: GPL-2.0-or-later
// Inspect one class across an APK's DEX files without whole-APK disassembly.
module main
import os
fn main() {
	if os.args.len != 4 { panic('usage: maps-caller APK CLASS FRESH_OUTPUT') }
	root := os.abs_path(os.args[3])
	if os.exists(root) { panic('fresh output required') }
	os.mkdir_all(root + '/dex')!
	if os.system_args(['/usr/bin/unzip', '-q', os.abs_path(os.args[1]), 'classes*.dex', '-d', root + '/dex']) != 0 { panic('extract failed') }
	for name in os.ls(root + '/dex')! {
		if os.system_args(['/opt/homebrew/opt/openjdk@25/bin/java', '-Xmx256m', '-cp', '/Users/alex/code/vinix/build/android-framework/tools/*',
			'org.jf.baksmali.Main', 'disassemble', '--classes', os.args[2], '-j', '1', '-o', root + '/' + name, root + '/dex/' + name]) != 0 { panic('disassembly failed') }
	}
}
