// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_stable_density(smali string) ! {
	path := smali + '/android/util/DisplayMetrics.smali'
	mut text := os.read_file(path)!
	if text.contains('DENSITY_DEVICE_STABLE:') { return error('stable density already present') }
	init := text.all_after('.method static constructor <clinit>()V').all_before('.end method')
	anchor := 'sput v0, Landroid/util/DisplayMetrics;->DENSITY_DEVICE:I'
	if init.count(anchor) != 1 || !init.contains('->getDeviceDensity()I') {
		return error('device density initialization required')
	}
	// Capture the backend's boot density once. The deprecated mutable field
	// and individual DisplayMetrics instances must not change this value.
	text = text.replace(init, init.replace(anchor, anchor + '\nsput v0, Landroid/util/DisplayMetrics;->DENSITY_DEVICE_STABLE:I'))
	text += '\n.field public static final DENSITY_DEVICE_STABLE:I\n'
	os.write_file(path, text)!
}
