// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// This runtime has no Android keyguard PIN, pattern or password configuration
// or credential backend. Thus no Android lock-screen credential is configured.
// Unix login/account credentials do not configure an Android device lock. The
// legacy isKeyguardSecure implementation is preserved, not used as this query.
pub fn framework_device_secure_source(original string) !string {
	lines := original.split_into_lines().map(it.trim_space())
	if lines.filter(it.starts_with('.class ')) != ['.class public Landroid/app/KeyguardManager;']
		|| lines.filter(it.starts_with('.super ')) != ['.super Ljava/lang/Object;']
		|| lines.any(it.starts_with('.field ')) {
		return error('canonical fieldless KeyguardManager required')
	}
	expected := ['public constructor <init>()V', 'public inKeyguardRestrictedInputMode()Z',
		'public isKeyguardLocked()Z', 'public isKeyguardSecure()Z']
	mut actual := lines.filter(it.starts_with('.method ')).map(it.all_after('.method '))
	actual.sort()
	if actual != expected.sorted() || lines.filter(it == '.end method').len != expected.len {
		return error('exact original KeyguardManager method schema required')
	}
	for block in original.split('.method ')[1..] {
		if block.count('.end method') != 1 {
			return error('balanced KeyguardManager methods required')
		}
	}
	return original + '\n.method public isDeviceSecure()Z\n    .registers 2\n\n    const/4 v0, 0x0\n\n    return v0\n.end method\n'
}

pub fn framework_device_secure(smali string) ! {
	path := smali + '/android/app/KeyguardManager.smali'
	patched := framework_device_secure_source(os.read_file(path)!)!
	os.write_file(path, patched)!
}
