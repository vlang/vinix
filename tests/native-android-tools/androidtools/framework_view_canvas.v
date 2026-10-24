// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// View natives need the Canvas object as well as its target: matrix/clip state
// belongs to that Canvas, and children must keep drawing into the same target.
fn framework_view_canvas(smali string) ! {
	canvas := smali + '/android/graphics/Canvas.smali'
	os.write_file(canvas, os.read_file(canvas)! + '
.method public final vinixNativeCanvas()Landroid/atl/GskCanvas;
.locals 1
instance-of v0, p0, Landroid/atl/GskCanvas;
if-eqz v0, :wrapped
move-object v0, p0
check-cast v0, Landroid/atl/GskCanvas;
return-object v0
:wrapped
iget-object v0, p0, Landroid/graphics/Canvas;->gsk_canvas:Landroid/atl/GskCanvas;
return-object v0
.end method
')!
	for class in ['View', 'ViewGroup'] {
		path := smali + '/android/view/' + class + '.smali'
		mut text := os.read_file(path)!
		for name in ['native_drawBackground', 'native_drawContent', 'native_drawChildren'] {
			text = text.replace(name + '(JJ)V', name + '(JLandroid/atl/GskCanvas;)V')
		}
		if class == 'View' {
			for method, native in {'draw': 'native_drawBackground', 'onDraw': 'native_drawContent', 'dispatchDraw': 'native_drawChildren'} {
				mut body := '.method ' + if method == 'dispatchDraw' { 'protected ' } else { 'public ' }
				body += method + '(Landroid/graphics/Canvas;)V\n.locals 3\n'
				if method == 'draw' { body += 'invoke-direct {p0}, Landroid/view/View;->vinixResolvePadding()V\n' }
				body +=
					'invoke-virtual {p1}, Landroid/graphics/Canvas;->vinixNativeCanvas()Landroid/atl/GskCanvas;\nmove-result-object v0\n' +
					'iget-wide v1, p0, Landroid/view/View;->widget:J\n' +
					'invoke-virtual {p0, v1, v2, v0}, Landroid/view/View;->' + native + '(JLandroid/atl/GskCanvas;)V\n'
				if method == 'draw' {
					body += 'invoke-virtual {p0, p1}, Landroid/view/View;->onDraw(Landroid/graphics/Canvas;)V\n' +
						'invoke-virtual {p0, p1}, Landroid/view/View;->dispatchDraw(Landroid/graphics/Canvas;)V\n'
				}
				text = framework_replace_method(text, method + '(Landroid/graphics/Canvas;)V', body + 'return-void\n.end method')!
			}
		}
		os.write_file(path, text)!
	}
}
