// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Outline clips use the same device-space path clips as ordinary Canvas calls.
// Keeping the clip in Canvas state also preserves it through child matrices,
// display-list playback, and RenderNode's save/restore and opacity layers.
fn framework_render_node_outline(smali string) ! {
	canvas_path := smali + '/android/graphics/Canvas.smali'
	mut canvas := os.read_file(canvas_path)!
	canvas = framework_replace_method(canvas, 'clipPath(Landroid/graphics/Path;)Z',
		touch_method('public clipPath(Landroid/graphics/Path;)Z', '
invoke-virtual {p0}, Landroid/graphics/Canvas;->vinixNativeCanvas()Landroid/atl/GskCanvas;
move-result-object v0
iget-object v1, p0, Landroid/graphics/Canvas;->bitmap:Landroid/graphics/Bitmap;
invoke-virtual {v1}, Landroid/graphics/Bitmap;->getSnapshot()J
move-result-wide v1
iput-wide v1, v0, Landroid/atl/GskCanvas;->snapshot:J
invoke-virtual {v0, p1}, Landroid/atl/GskCanvas;->clipPath(Landroid/graphics/Path;)Z
move-result v0
return v0'))!
	canvas = framework_replace_method(canvas, 'clipPath(Landroid/graphics/Path;Landroid/graphics/Region$Op;)Z',
		touch_method('public clipPath(Landroid/graphics/Path;Landroid/graphics/Region$Op;)Z', '
sget-object v0, Landroid/graphics/Region$Op;->INTERSECT:Landroid/graphics/Region$Op;
if-ne p2, v0, :unsupported
invoke-virtual {p0, p1}, Landroid/graphics/Canvas;->clipPath(Landroid/graphics/Path;)Z
move-result v0
return v0
:unsupported
new-instance v0, Ljava/lang/UnsupportedOperationException;
const-string v1, "Native WS Canvas supports intersecting path clips only"
invoke-direct {v0, v1}, Ljava/lang/UnsupportedOperationException;-><init>(Ljava/lang/String;)V
throw v0'))!
	os.write_file(canvas_path, canvas)!
	gsk_path := smali + '/android/atl/GskCanvas.smali'
	os.write_file(gsk_path, os.read_file(gsk_path)! + '
.method private native native_clipPath(JJI)Z
.end method
' + touch_method('public clipPath(Landroid/graphics/Path;)Z', '
move-object v0, p0
iget-wide v1, p0, Landroid/atl/GskCanvas;->snapshot:J
invoke-virtual {p1}, Landroid/graphics/Path;->getGskPath()J
move-result-wide v3
invoke-virtual {p1}, Landroid/graphics/Path;->getFillType()Landroid/graphics/Path$FillType;
move-result-object v5
invoke-virtual {v5}, Ljava/lang/Enum;->ordinal()I
move-result v5
invoke-direct/range {v0 .. v5}, Landroid/atl/GskCanvas;->native_clipPath(JJI)Z
move-result v0
return v0'))!
	node_path := smali + '/android/graphics/RenderNode.smali'
	mut node := os.read_file(node_path)!
	contents := render_node_draw_contents()
	clipped := contents.all_before('\n:outline\n') + '\n:outline\n' +
		'invoke-direct {p0, p1}, Landroid/graphics/RenderNode;->vinixClipOutline(Landroid/graphics/Canvas;)V\n:draw\n' +
		contents.all_after('\n:draw\n')
	node = framework_replace_method(node, 'vinixDrawContents(Landroid/graphics/Canvas;)V',
		touch_method('private vinixDrawContents(Landroid/graphics/Canvas;)V', clipped))!
	node += touch_method('private vinixClipOutline(Landroid/graphics/Canvas;)V', '
iget-boolean v0, p0, Landroid/graphics/RenderNode;->ClipToOutline:Z
if-eqz v0, :done
iget-object v0, p0, Landroid/graphics/RenderNode;->outline:Landroid/graphics/Outline;
if-eqz v0, :done
iget v1, v0, Landroid/graphics/Outline;->mMode:I
const/4 v2, 1
if-eq v1, v2, :round_rect
const/4 v2, 2
if-ne v1, v2, :empty
iget-object v0, v0, Landroid/graphics/Outline;->mPath:Landroid/graphics/Path;
invoke-virtual {p1, v0}, Landroid/graphics/Canvas;->clipPath(Landroid/graphics/Path;)Z
goto :done
:round_rect
iget-object v1, v0, Landroid/graphics/Outline;->mRect:Landroid/graphics/Rect;
iget v6, v0, Landroid/graphics/Outline;->mRadius:F
const/4 v2, 0
cmpg-float v2, v6, v2
if-gtz v2, :rounded
invoke-virtual {p1, v1}, Landroid/graphics/Canvas;->clipRect(Landroid/graphics/Rect;)Z
goto :done
:rounded
iget v2, v1, Landroid/graphics/Rect;->left:I
iget v3, v1, Landroid/graphics/Rect;->top:I
iget v4, v1, Landroid/graphics/Rect;->right:I
iget v5, v1, Landroid/graphics/Rect;->bottom:I
int-to-float v2, v2
int-to-float v3, v3
int-to-float v4, v4
int-to-float v5, v5
move v7, v6
sget-object v8, Landroid/graphics/Path$Direction;->CW:Landroid/graphics/Path$Direction;
new-instance v1, Landroid/graphics/Path;
invoke-direct {v1}, Landroid/graphics/Path;-><init>()V
invoke-virtual/range {v1 .. v8}, Landroid/graphics/Path;->addRoundRect(FFFFFFLandroid/graphics/Path$Direction;)V
invoke-virtual {p1, v1}, Landroid/graphics/Canvas;->clipPath(Landroid/graphics/Path;)Z
goto :done
:empty
const/4 v0, 0
invoke-virtual {p1, v0, v0, v0, v0}, Landroid/graphics/Canvas;->clipRect(IIII)Z
:done
return-void')
	os.write_file(node_path, node)!
}
