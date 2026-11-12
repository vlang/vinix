// SPDX-License-Identifier: GPL-2.0-or-later
module main
import androidtools
import os
fn main() {
	if os.args.len != 3 { panic('usage: bluetooth-values-build FRAMEWORK FRESH_OUTPUT') }
	base, root := os.abs_path(os.args[1]), os.abs_path(os.args[2])
	if os.exists(root) { panic('fresh output required') }
	os.mkdir_all(root)!
	os.cp_all(base + '/smali', root + '/smali', false)!
	androidtools.framework_bluetooth_values(root + '/smali')!
	os.cp(base + '/api-impl.jar', root + '/api-impl.jar')!
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	cp := '/Users/alex/code/vinix/build/android-framework/tools/*'
	for args in [[java, '-Xmx256m', '-cp', cp, 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', root + '/smali', '-o', root + '/classes.dex'],
		['/usr/bin/zip', '-q', '-j', root + '/api-impl.jar', root + '/classes.dex'],
		[java, '-Xmx256m', '-cp', cp, 'org.jf.baksmali.Main', 'disassemble', '--classes', r'Landroid/bluetooth/BluetoothDevice;,Landroid/bluetooth/BluetoothClass;,Landroid/bluetooth/BluetoothDevice$VinixCreator;,Landroid/bluetooth/BluetoothClass$VinixCreator;', '--jobs', '2', root + '/classes.dex', '-o', root + '/roundtrip']] {
		if os.system_args(args) != 0 { panic('assembly/readback failed') }
	}
	println('BLUETOOTH-VALUES-BUILD-PASS ' + root)
}
