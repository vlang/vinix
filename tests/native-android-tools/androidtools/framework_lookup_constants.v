// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Native clients resolve these public fields through JNI rather than using
// Java's compile-time constant inlining. This adds names, not service authority
// or a fabricated persistent boot count.
pub fn framework_lookup_constants(smali string) ! {
	for entry in [
		['android/content/Context', 'APP_OPS_SERVICE', 'appops']!,
		[r'android/provider/Settings$Global', 'BOOT_COUNT', 'boot_count']!,
	] {
		path := smali + '/' + entry[0] + '.smali'
		mut text := os.read_file(path)!
		if text.contains(' ' + entry[1] + ':Ljava/lang/String;') { return error('lookup constant already installed: ' + entry[1]) }
		text += '\n.field public static final ' + entry[1] + ':Ljava/lang/String; = "' + entry[2] + '"\n'
		os.write_file(path, text)!
	}
}
