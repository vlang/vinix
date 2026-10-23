// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_canvas_save_flags(smali string) ! {
	path := smali + '/android/graphics/Canvas.smali'
	os.write_file(path, os.read_file(path)! +
		'\n.method public saveLayer(FFFFLandroid/graphics/Paint;I)I\n.locals 1\n' +
			'invoke-virtual/range {p0 .. p5}, Landroid/graphics/Canvas;->saveLayer(FFFFLandroid/graphics/Paint;)I\n' +
			'move-result v0\nreturn v0\n.end method\n')!
}
