// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Android's base Drawable has no optical adjustment. Insets.NONE is immutable,
// so inherited calls can share it without allocating or exposing mutable state.
// Keep the method virtual: drawable subclasses may provide their own insets.
fn framework_drawable_optical_insets(smali string) ! {
	path := smali + '/android/graphics/drawable/Drawable.smali'
	mut text := os.read_file(path)!
	if text.contains(' getOpticalInsets()Landroid/graphics/Insets;') {
		return error('Drawable optical insets API already present')
	}
	text += '\n.method public getOpticalInsets()Landroid/graphics/Insets;\n.locals 1\n' +
		'sget-object v0, Landroid/graphics/Insets;->NONE:Landroid/graphics/Insets;\n' +
		'return-object v0\n.end method\n'
	os.write_file(path, text)!
}
