// SPDX-License-Identifier: GPL-2.0-or-later
// Preserved macOS/HVF investigation helper; run from the repository root.
import os

fn run(args []string) {
	r := os.exec(args)
	if r.exit_code != 0 { panic(r.output) }
}

fn main() {
	out := os.getwd() + '/build/android-native-ws'
	mode := if os.args.len > 1 { os.args[1] } else { 'direct' }
	app := if os.args.len > 2 { os.args[2] } else { 'calculator' }
	activity := match app {
		'editor' { 'org/billthefarmer/editor/Editor' }
		'sudoku' { 'org/moire/opensudoku/gui/FolderListActivity' }
		else { 'calculator/Calculator' }
	}
	os.cp(out + '/guest', out + '/overlay/opt/android-test/native-guest')!
	os.chmod(out + '/overlay/opt/android-test/native-guest', 0o755)!
	os.write_file(out + '/overlay/opt/android-test/native-mode', mode)!
	if !os.exists(out + '/vm/boot.img') {
		run(['tar', '--format=ustar', '-cf', out + '/initramfs.tar', '-C', out + '/overlay', '.'])
	}
	os.mkdir_all(out + '/vm')!
	if !os.exists(out + '/vm/boot.img') {
		run(['cp', '-c', 'build/android-framework/calculator-final/boot.img', out + '/vm/boot.img'])
		os.cp('build/android-framework/calculator-final/efivars.fd', out + '/vm/efivars.fd')!
		run(['mcopy', '-o', '-i', out + '/vm/boot.img', out + '/initramfs.tar', '::/boot/initramfs.tar'])
	}
	os.mkdir_all(out + '/qemu-runtime')!
	run(['tar', '-xf', out + '/original-qemu-runtime.tar', '-C', out + '/qemu-runtime'])
	os.write_file(out + '/qemu-runtime/sbin/init', '#!/bin/sh\nexec /opt/android-test/native-guest\n')!
	os.chmod(out + '/qemu-runtime/sbin/init', 0o755)!
	os.mkdir_all(out + '/qemu-runtime/opt/android-test')!
	os.mkdir_all(out + '/qemu-runtime/opt/vinix-android-aarch64/usr/lib/art')!
	os.mkdir_all(out + '/qemu-runtime/opt/vinix-android-aarch64/usr/bin')!
	os.cp(out + '/guest', out + '/qemu-runtime/opt/android-test/native-guest')!
	os.write_file(out + '/qemu-runtime/opt/android-test/native-mode', mode)!
	os.cp(out + '/libvinix-android-native.so', out + '/qemu-runtime/opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so')!
	os.mkdir_all(out + '/qemu-runtime/opt/vinix-android-aarch64/usr/lib/art/native-ws')!
	os.cp(out + '/libdl_bio.so.0', out + '/qemu-runtime/opt/vinix-android-aarch64/usr/lib/art/native-ws/libdl_bio.so.0')!
	os.cp(out + '/vinix-android-native', out + '/qemu-runtime/opt/vinix-android-aarch64/usr/bin/vinix-android-native')!
	os.cp(out + '/run-android', out + '/qemu-runtime/usr/bin/run-android')!
	jar_dir := out + '/qemu-runtime/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer'
	os.mkdir_all(jar_dir)!
	os.cp(out + '/api-impl.jar', jar_dir + '/api-impl.jar')!
	if app == 'editor' {
		os.cp('build/android-complex/Editor-1.98.apk', out + '/qemu-runtime/opt/android-test/application.apk')!
	} else if app == 'sudoku' {
		os.cp('build/android-complex/OpenSudoku-2.5.2.apk', out + '/qemu-runtime/opt/android-test/application.apk')!
	} else if os.exists(out + '/qemu-runtime/opt/android-test/application.apk') {
		os.rm(out + '/qemu-runtime/opt/android-test/application.apk')!
	}
	os.write_file(out + '/qemu-runtime/usr/bin/run-android-calculator', '#!/bin/sh\nexport VINIX_ANDROID_TRACE_TEXT=1 VINIX_ANDROID_TRACE_TREE=1\nexec /usr/bin/run-android /opt/android-test/application.apk -l ' + activity + '\n')!
	os.chmod(out + '/qemu-runtime/usr/bin/run-android-calculator', 0o755)!
	if os.exists(out + '/vinix-desktop') {
		os.cp(out + '/vinix-desktop', out + '/qemu-runtime/usr/bin/vinix-desktop')!
		os.cp(out + '/vinix-desktop', out + '/qemu-runtime/usr/bin/vinix-android-calculator')!
	}
	run(['tar', '--format=ustar', '-cf', out + '/qemu-runtime.tar', '-C', out + '/qemu-runtime',
		'.'])
	run(['mcopy', '-o', '-i', out + '/vm/boot.img', out + '/qemu-runtime.tar',
		'::/boot/qemu-runtime.tar'])
}
