// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Nine-patches retain the same decoded bitmap storage as bitmap drawables.
// Report its dimensions so layout does not inherit Drawable's unknown size.
// This matches BitmapDrawable's current raw-pixel dimensions; target-density
// scaling remains outside the renderer's existing bitmap drawable support.
fn framework_nine_patch_dimensions(smali string) ! {
	path := smali + '/android/graphics/drawable/NinePatchDrawable.smali'
	owner := 'Landroid/graphics/drawable/NinePatchDrawable;'
	mut text := os.read_file(path)!
	for dimension in ['Width', 'Height'] {
		if text.contains(' getIntrinsic${dimension}()I')
			|| text.contains(' nativeGetIntrinsic${dimension}(J)I') {
			return error('NinePatchDrawable intrinsic ${dimension} API already present')
		}
		text += '\n.method private static native nativeGetIntrinsic${dimension}(J)I\n.end method\n' +
			'\n.method public getIntrinsic${dimension}()I\n.locals 2\n' +
			'iget-wide v0, p0, Landroid/graphics/drawable/Drawable;->paintable:J\n' +
			'invoke-static {v0, v1}, ${owner}->nativeGetIntrinsic${dimension}(J)I\n' +
			'move-result v0\nreturn v0\n.end method\n'
	}
	os.write_file(path, text)!
}
