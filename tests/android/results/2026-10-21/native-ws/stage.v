// SPDX-License-Identifier: GPL-2.0-or-later
// Preserved macOS/HVF investigation helper; run from the repository root.
import os

fn checked(args []string) {
	result := os.exec(args)
	if result.exit_code != 0 { panic(args.str() + '\n' + result.output) }
}

fn main() {
	root := os.getwd()
	out := root + '/build/android-native-ws'
	overlay := out + '/overlay'
	if !os.exists(overlay) {
		os.mkdir_all(overlay)!
		checked(['rsync', '-aH',
			root + '/build/android-calculator-20261020-borderless-prepared/overlay/', overlay + '/'])
	}
	runtime := overlay + '/opt/vinix-android-aarch64'
	os.cp(out + '/libvinix-android-native.so', runtime + '/usr/lib/art/libvinix-android-native.so')!
	os.cp(out + '/vinix-android-native', runtime + '/usr/bin/vinix-android-native')!
	os.cp(out + '/run-android', overlay + '/usr/bin/run-android')!
	os.chmod(overlay + '/usr/bin/run-android', 0o755)!
	if os.exists(out + '/vinix-desktop') {
		os.cp(out + '/vinix-desktop', overlay + '/usr/bin/vinix-desktop')!
		os.cp(out + '/vinix-desktop', overlay + '/usr/bin/vinix-android-calculator')!
	}
	smali := out + '/smali'
	if !os.exists(smali) {
		os.cp_all(root + '/build/android-framework/extended/smali', smali, false)!
	}
	viewpath := smali + '/android/view/View.smali'
	mut view := os.read_file(viewpath)!
	if !view.contains('vinixWsWatchers:') {
		view += '\n.field private vinixWsWatchers:Ljava/util/ArrayList;\n.field private vinixWsEditorAction:Ljava/lang/Object;\n'
		os.write_file(viewpath, view)!
	}
	checked(['/opt/homebrew/opt/openjdk@25/bin/java', '-cp', root + '/build/android-framework/tools/*',
		'org.jf.smali.Main', 'assemble', '--jobs', '2', smali, '-o', out + '/classes.dex'])
	os.cp(root + '/build/android-framework/api-impl.jar', out + '/api-impl.jar')!
	checked(['zip', '-q', '-j', out + '/api-impl.jar', out + '/classes.dex'])
	os.cp(out + '/api-impl.jar', runtime + '/usr/lib/java/dex/android_translation_layer/api-impl.jar')!
	// The APK is untouched. Only its launcher selects ART's native WS backend.
	os.write_file(overlay + '/usr/bin/run-android-calculator', '#!/bin/sh\nexec /usr/bin/run-android /opt/android-test/application.apk -l calculator/Calculator\n')!
	os.chmod(overlay + '/usr/bin/run-android-calculator', 0o755)!
	checked(['tar', '--format=ustar', '-cf', out + '/initramfs.tar', '-C', overlay, '.'])
}
