// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Native WS queries the fixed primary framebuffer's physical pixel mode.
// Display.window_width/window_height describe an app surface and must not be
// substituted for that geometry. The native backend creates a fresh Point,
// including an empty Point when physical geometry is unavailable.
pub fn framework_stable_display_source(original string) !string {
	lines := original.split_into_lines().map(it.trim_space())
	if lines.filter(it.starts_with('.class ')) != ['.class public final Landroid/hardware/display/DisplayManager;']
		|| lines.filter(it.starts_with('.super ')) != ['.super Ljava/lang/Object;']
		|| lines.any(it.starts_with('.field ')) {
		return error('canonical fieldless DisplayManager required')
	}
	expected := ['public constructor <init>()V', 'public getDisplay(I)Landroid/view/Display;',
		'public getDisplays()[Landroid/view/Display;',
		'public registerDisplayListener(Landroid/hardware/display/DisplayManager$DisplayListener;Landroid/os/Handler;)V',
		'public unregisterDisplayListener(Landroid/hardware/display/DisplayManager$DisplayListener;)V']
	mut actual := lines.filter(it.starts_with('.method ')).map(it.all_after('.method '))
	actual.sort()
	if actual != expected.sorted() || lines.filter(it == '.end method').len != expected.len {
		return error('exact original DisplayManager method schema required')
	}
	for block in original.split('.method ')[1..] {
		if block.count('.end method') != 1 {
			return error('balanced DisplayManager methods required')
		}
	}
	return original + '\n.method public native getStableDisplaySize()Landroid/graphics/Point;\n.end method\n'
}

pub fn framework_stable_display(smali string) ! {
	path := smali + '/android/hardware/display/DisplayManager.smali'
	patched := framework_stable_display_source(os.read_file(path)!)!
	os.write_file(path, patched)!
}
